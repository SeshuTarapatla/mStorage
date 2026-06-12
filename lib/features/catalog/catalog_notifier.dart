import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/catalog_cache_manager.dart';
import '../../core/services/settings_service.dart';
import 'imdb_service.dart';
import 'models/catalog_entry.dart';

const _prefKey = 'catalog_sheet_url';

// ---------------------------------------------------------------------------
// Sheet URL persistence
// ---------------------------------------------------------------------------

final sheetUrlProvider = StateNotifierProvider<SheetUrlNotifier, String?>((ref) {
  return SheetUrlNotifier();
});

class SheetUrlNotifier extends StateNotifier<String?> {
  SheetUrlNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_prefKey);
  }

  Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
    state = url;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    state = null;
  }
}

// ---------------------------------------------------------------------------
// Catalog state
// ---------------------------------------------------------------------------

sealed class CatalogState {}

class CatalogIdle extends CatalogState {}

class CatalogLoading extends CatalogState {}

class CatalogLoaded extends CatalogState {
  final List<CatalogEntry> entries;
  CatalogLoaded(this.entries);
}

class CatalogError extends CatalogState {
  final String message;
  CatalogError(this.message);
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

final catalogProvider = StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
  return CatalogNotifier();
});

class CatalogNotifier extends StateNotifier<CatalogState> {
  CatalogNotifier() : super(CatalogIdle());

  static const _kCsvCacheTtl = Duration(hours: 1);
  String? _cacheDir;

  static String? _extractSheetId(String url) {
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  // ── CSV disk cache helpers ─────────────────────────────────────────────────

  Future<String> _ensureCacheDir() async {
    _cacheDir ??= (await getApplicationSupportDirectory()).path;
    return _cacheDir!;
  }

  Future<({String body, DateTime fetchedAt})?> _loadCsvCache(
      String sheetId) async {
    try {
      final dir = await _ensureCacheDir();
      final file = File(p.join(dir, 'catalog_csv_$sheetId.json'));
      if (!file.existsSync()) return null;
      final map =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final at = DateTime.tryParse(map['fetchedAt'] as String? ?? '');
      if (at == null) return null;
      return (body: map['body'] as String, fetchedAt: at);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearCsvCache(String sheetId) async {
    try {
      final dir = await _ensureCacheDir();
      final file = File(p.join(dir, 'catalog_csv_$sheetId.json'));
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  Future<void> clearAllCsvCaches() async {
    try {
      final dir = await _ensureCacheDir();
      for (final f in Directory(dir).listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('catalog_csv_')) await f.delete();
      }
    } catch (_) {}
  }

  Future<void> _saveCsvCache(String sheetId, String body) async {
    try {
      final dir = await _ensureCacheDir();
      await File(p.join(dir, 'catalog_csv_$sheetId.json')).writeAsString(
        jsonEncode(
            {'fetchedAt': DateTime.now().toIso8601String(), 'body': body}),
      );
    } catch (_) {}
  }

  // ── CSV → entries pipeline (shared by cached and fresh paths) ─────────────

  Future<List<CatalogEntry>> _buildEntries(String csvBody) async {
    // Normalize CRLF → LF so the parser works regardless of what Google returns.
    final normalized = csvBody.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(normalized);
    if (rows.length < 2) return [];

    final headers = {
      for (var i = 0; i < rows[0].length; i++)
        rows[0][i]
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[\s_\-]+'), ''): i,
    };

    // Index of the visibility column. Canonical name is 'show'; legacy aliases kept for backward compat.
    final visIdx = headers['show'] ?? headers['enabled'] ?? headers['visible'] ??
        headers['active'];

    final rawEntries = rows
        .skip(1)
        .where((row) {
          if (row.isEmpty || row[0].toString().trim().isEmpty) return false;
          if (visIdx != null && visIdx < row.length) {
            final val = row[visIdx].toString().trim().toLowerCase();
            if (val == 'false') return false;
          }
          return true;
        })
        .map((row) => CatalogEntry.fromRow(row, headers))
        .toList();

    final imdbIds = rawEntries
        .where((e) => e.imdbId.isNotEmpty)
        .map((e) => e.imdbId)
        .toList();

    final imdbMap = imdbIds.isNotEmpty
        ? await ImdbService().resolve(imdbIds)
        : <String, dynamic>{};

    return rawEntries.map((e) {
      final data = imdbMap[e.imdbId];
      return data != null ? e.mergeImdb(data) : e;
    }).toList();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load(String sheetUrl, {bool forceRefresh = false}) async {
    state = CatalogLoading();

    final sheetId = _extractSheetId(sheetUrl);
    if (sheetId == null) {
      state = CatalogError('Invalid Google Sheets URL.');
      return;
    }

    final csvUrl =
        'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv&gid=0';

    if (forceRefresh) {
      // Clear all caches in the background — don't wait on them, and don't
      // read the disk cache below (the unawaited save from a prior load can
      // race with the delete and recreate a stale file before we read it).
      unawaited(Future.wait([
        _clearCsvCache(sheetId),
        ImdbService().clearCache(),
        CatalogCacheManager.instance.emptyCache(),
      ]));
    } else {
      // Serve from disk cache immediately if available.
      final cached = await _loadCsvCache(sheetId);
      if (cached != null) {
        final entries = await _buildEntries(cached.body);
        if (mounted) state = CatalogLoaded(entries);

        final age = DateTime.now().difference(cached.fetchedAt);
        if (age < _kCsvCacheTtl) return; // fresh enough — skip network

        // Stale: refresh silently in the background.
        _silentRefresh(sheetId, csvUrl, cached.body);
        return;
      }
    }

    // No cache — fetch fresh (show loading until done).
    try {
      final response = await http.get(Uri.parse(csvUrl));

      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<')) {
        if (mounted) {
          state = CatalogError(
            'Could not load sheet. Make sure it is shared as "Anyone with the link can view".',
          );
        }
        return;
      }

      unawaited(_saveCsvCache(sheetId, response.body));
      final entries = await _buildEntries(response.body);
      if (mounted) state = CatalogLoaded(entries);
    } catch (e) {
      if (mounted) state = CatalogError('Failed to fetch catalog: $e');
    }
  }

  /// Fetches fresh CSV in the background; updates state only if content changed.
  Future<void> _silentRefresh(
      String sheetId, String csvUrl, String cachedBody) async {
    try {
      final response = await http.get(Uri.parse(csvUrl));
      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<')) { return; }
      if (response.body == cachedBody) {
        // Content unchanged — just bump the cache timestamp.
        unawaited(_saveCsvCache(sheetId, cachedBody));
        return;
      }
      unawaited(_saveCsvCache(sheetId, response.body));
      final entries = await _buildEntries(response.body);
      if (mounted) state = CatalogLoaded(entries);
    } catch (_) {}
  }

  void reset() => state = CatalogIdle();
}

// ---------------------------------------------------------------------------
// Download job (internal queue entry)
// ---------------------------------------------------------------------------

class _DownloadJob {
  final String url;
  final String suggestedFilename;
  final String title;
  final String? subtitle;
  final String thumbnailUrl;

  const _DownloadJob({
    required this.url,
    required this.suggestedFilename,
    required this.title,
    this.subtitle,
    required this.thumbnailUrl,
  });
}

// ---------------------------------------------------------------------------
// Download history record
// ---------------------------------------------------------------------------

class DownloadRecord {
  final String title;
  final String? subtitle;
  final String filename;
  final String filePath;
  final String thumbnailUrl;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  const DownloadRecord({
    required this.title,
    this.subtitle,
    required this.filename,
    required this.filePath,
    required this.thumbnailUrl,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String?,
        filename: j['filename'] as String? ?? '',
        filePath: j['filePath'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        fileSizeBytes: j['fileSizeBytes'] as int? ?? 0,
        downloadedAt: DateTime.parse(j['downloadedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'filename': filename,
        'filePath': filePath,
        'thumbnailUrl': thumbnailUrl,
        'fileSizeBytes': fileSizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Download history notifier
// ---------------------------------------------------------------------------

const _kHistoryKey = 'catalog_download_history';

final downloadHistoryProvider =
    NotifierProvider<DownloadHistoryNotifier, List<DownloadRecord>>(
        DownloadHistoryNotifier.new);

class DownloadHistoryNotifier extends Notifier<List<DownloadRecord>> {
  bool _disposed = false;

  @override
  List<DownloadRecord> build() {
    ref.onDispose(() => _disposed = true);
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey) ?? '[]';
    try {
      final decoded = jsonDecode(raw) as List;
      final seen = <String>{};
      final list = decoded
          .map((e) => DownloadRecord.fromJson(e as Map<String, dynamic>))
          .where((r) => seen.add(r.filePath))
          .toList();
      if (!_disposed) state = list;
      if (list.length < decoded.length) await _persist(list);
    } catch (_) {}
  }

  Future<void> add(DownloadRecord record) async {
    final updated = [record, ...state.where((r) => r.filePath != record.filePath)]
        .take(100)
        .toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> remove(String filePath) async {
    final updated = state.where((r) => r.filePath != filePath).toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> pruneDeleted() async {
    final updated = state.where((r) => File(r.filePath).existsSync()).toList();
    if (updated.length == state.length) return;
    state = updated;
    await _persist(updated);
  }

  Future<void> _persist(List<DownloadRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kHistoryKey, jsonEncode(records.map((e) => e.toJson()).toList()));
  }
}

// ---------------------------------------------------------------------------
// Download state
// ---------------------------------------------------------------------------

sealed class DownloadState {}

class DownloadIdle extends DownloadState {}

class DownloadActive extends DownloadState {
  final String title;
  final String filename;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final int queueRemaining;

  DownloadActive({
    required this.title,
    required this.filename,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
    this.queueRemaining = 0,
  });
}

class DownloadDone extends DownloadState {
  final String filePath;
  DownloadDone(this.filePath);
}

class DownloadError extends DownloadState {
  final String message;
  DownloadError(this.message);
}

// ---------------------------------------------------------------------------
// Download notifier (queue-based)
// ---------------------------------------------------------------------------

final downloadProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);

class DownloadNotifier extends Notifier<DownloadState> {
  final _queue = <_DownloadJob>[];
  http.Client? _client;
  bool _cancelled = false;
  bool _running = false;
  bool _disposed = false;

  @override
  DownloadState build() {
    ref.onDispose(() => _disposed = true);
    return DownloadIdle();
  }

  String _resolveDir() {
    final custom = ref.read(settingsProvider).catalogDownloadDirectory;
    return custom.isNotEmpty ? custom : AppDirectories.downloaded;
  }

  /// Adds a job to the queue and starts processing if not already running.
  void enqueue(String url, String suggestedFilename, String title,
      String thumbnailUrl, {String? subtitle}) {
    if (!_running) _cancelled = false;
    _queue.add(_DownloadJob(
      url: url,
      suggestedFilename: suggestedFilename,
      title: title,
      subtitle: subtitle,
      thumbnailUrl: thumbnailUrl,
    ));
    if (!_running) _processQueue();
  }

  Future<void> _processQueue() async {
    _running = true;
    String? lastFilePath;
    final failed = <String>[];

    while (_queue.isNotEmpty && !_cancelled) {
      final job = _queue.removeAt(0);
      try {
        final path = await _runJob(job);
        if (path.isNotEmpty) lastFilePath = path;
      } catch (e) {
        if (_cancelled || _disposed) break;
        failed.add('"${job.title}": $e');
        // Continue with remaining jobs.
      }
    }

    _running = false;
    if (_cancelled || _disposed) return;
    if (failed.isNotEmpty) {
      final summary = '${failed.length} download(s) failed:\n${failed.join('\n')}';
      state = DownloadError(summary);
    } else if (lastFilePath != null) {
      state = DownloadDone(lastFilePath);
    } else {
      state = DownloadIdle();
    }
  }

  /// Runs a single download job. Returns the saved file path on success.
  Future<String> _runJob(_DownloadJob job) async {
    _client?.close();
    _client = http.Client();

    String filename = job.suggestedFilename;

    if (!_disposed) {
      state = DownloadActive(
        title: job.title,
        filename: filename.isNotEmpty ? filename : 'Connecting…',
        receivedBytes: 0,
        totalBytes: 0,
        speedBytesPerSec: 0,
        queueRemaining: _queue.length,
      );
    }

    final request = http.Request('GET', Uri.parse(job.url));
    final response = await _client!.send(request);

    // Resolve filename: suggested → Content-Disposition → title fallback.
    if (filename.isEmpty) {
      final cd = response.headers['content-disposition'] ?? '';
      final m = RegExp(r'filename\*?=([^;\r\n]+)', caseSensitive: false)
          .firstMatch(cd);
      filename =
          m?.group(1)?.trim().replaceAll(RegExp(r'''["']'''), '') ?? '';
    }
    if (filename.isEmpty) filename = '${job.title}.mp4';

    final total = response.contentLength ?? 0;
    final downloadDir = _resolveDir();
    await Directory(downloadDir).create(recursive: true);
    final file = File(p.join(downloadDir, filename));
    final sink = file.openWrite();

    if (!_cancelled && !_disposed) {
      state = DownloadActive(
        title: job.title,
        filename: filename,
        receivedBytes: 0,
        totalBytes: total,
        speedBytesPerSec: 0,
        queueRemaining: _queue.length,
      );
    }

    int received = 0;
    var lastTick = DateTime.now();
    int bytesInWindow = 0;
    bool downloadError = false;

    try {
      await for (final chunk in response.stream) {
        if (_cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        bytesInWindow += chunk.length;

        final now = DateTime.now();
        final elapsed = now.difference(lastTick).inMilliseconds;
        if (elapsed >= 300 && !_cancelled && !_disposed) {
          state = DownloadActive(
            title: job.title,
            filename: filename,
            receivedBytes: received,
            totalBytes: total,
            speedBytesPerSec: bytesInWindow / (elapsed / 1000),
            queueRemaining: _queue.length,
          );
          lastTick = now;
          bytesInWindow = 0;
        }
      }
    } catch (_) {
      downloadError = true;
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
      _client?.close();
      if (_cancelled || downloadError) {
        try { file.deleteSync(); } catch (_) {}
      }
    }

    if (_cancelled) return '';

    // Record in history.
    await ref.read(downloadHistoryProvider.notifier).add(DownloadRecord(
          title: job.title,
          subtitle: job.subtitle,
          filename: filename,
          filePath: file.path,
          thumbnailUrl: job.thumbnailUrl,
          fileSizeBytes: received,
          downloadedAt: DateTime.now(),
        ));

    return file.path;
  }

  void cancel() {
    _cancelled = true;
    _queue.clear();
    _client?.close();
    _client = null;
    if (!_disposed) state = DownloadIdle();
  }

  void dismiss() => state = DownloadIdle();
}

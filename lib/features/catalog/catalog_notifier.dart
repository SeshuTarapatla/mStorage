import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/settings_service.dart';
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

  static String? _extractSheetId(String url) {
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  Future<void> load(String sheetUrl) async {
    state = CatalogLoading();

    final sheetId = _extractSheetId(sheetUrl);
    if (sheetId == null) {
      state = CatalogError('Invalid Google Sheets URL.');
      return;
    }

    final csvUrl =
        'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv&gid=0';

    try {
      final response = await http.get(Uri.parse(csvUrl));

      if (response.statusCode != 200 ||
          response.body.trimLeft().startsWith('<')) {
        state = CatalogError(
          'Could not load sheet. Make sure it is shared as "Anyone with the link can view".',
        );
        return;
      }

      final rows = const CsvToListConverter(eol: '\n').convert(response.body);

      if (rows.length < 2) {
        state = CatalogLoaded([]);
        return;
      }

      // Row 0 is the header — skip it.
      final entries = rows
          .skip(1)
          .where((row) => row.isNotEmpty && row[0].toString().trim().isNotEmpty)
          .map((row) => CatalogEntry.fromRow(row))
          .toList();

      state = CatalogLoaded(entries);
    } catch (e) {
      state = CatalogError('Failed to fetch catalog: $e');
    }
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
  final String thumbnailUrl;

  const _DownloadJob({
    required this.url,
    required this.suggestedFilename,
    required this.title,
    required this.thumbnailUrl,
  });
}

// ---------------------------------------------------------------------------
// Download history record
// ---------------------------------------------------------------------------

class DownloadRecord {
  final String title;
  final String filename;
  final String filePath;
  final String thumbnailUrl;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  const DownloadRecord({
    required this.title,
    required this.filename,
    required this.filePath,
    required this.thumbnailUrl,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        title: j['title'] as String? ?? '',
        filename: j['filename'] as String? ?? '',
        filePath: j['filePath'] as String? ?? '',
        thumbnailUrl: j['thumbnailUrl'] as String? ?? '',
        fileSizeBytes: j['fileSizeBytes'] as int? ?? 0,
        downloadedAt: DateTime.parse(j['downloadedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
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
      final list = (jsonDecode(raw) as List)
          .map((e) => DownloadRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!_disposed) state = list;
    } catch (_) {}
  }

  Future<void> add(DownloadRecord record) async {
    final updated = [record, ...state].take(100).toList();
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
  final String filename;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final int queueRemaining;

  DownloadActive({
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
      String thumbnailUrl) {
    if (!_running) _cancelled = false;
    _queue.add(_DownloadJob(
      url: url,
      suggestedFilename: suggestedFilename,
      title: title,
      thumbnailUrl: thumbnailUrl,
    ));
    if (!_running) _processQueue();
  }

  Future<void> _processQueue() async {
    _running = true;
    String? lastFilePath;

    while (_queue.isNotEmpty && !_cancelled) {
      final job = _queue.removeAt(0);
      try {
        lastFilePath = await _runJob(job);
      } catch (e) {
        if (!_cancelled && !_disposed) state = DownloadError('Download failed: $e');
        _queue.clear();
        _running = false;
        return;
      }
    }

    _running = false;
    if (!_cancelled && !_disposed && state is! DownloadError) {
      state = lastFilePath != null ? DownloadDone(lastFilePath) : DownloadIdle();
    }
  }

  /// Runs a single download job. Returns the saved file path on success.
  Future<String> _runJob(_DownloadJob job) async {
    _client?.close();
    _client = http.Client();

    String filename = job.suggestedFilename;

    if (!_disposed) {
      state = DownloadActive(
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
    } finally {
      await sink.flush();
      await sink.close();
      _client?.close();
    }

    if (_cancelled) {
      try { file.deleteSync(); } catch (_) {}
      return '';
    }

    // Record in history.
    await ref.read(downloadHistoryProvider.notifier).add(DownloadRecord(
          title: job.title,
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

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models/imdb_data.dart';

class ImdbService {
  static const _baseUrl = 'https://api.imdbapi.dev';
  static const _ttl = Duration(days: 30);
  static const _batchSize = 5;

  // Singleton — one instance shares the in-memory cache across all callers.
  static final ImdbService _instance = ImdbService._();
  factory ImdbService() => _instance;
  ImdbService._();

  // ── Metadata cache ─────────────────────────────────────────────────────────
  final _cache = <String, ImdbData>{};
  final _fetchedAt = <String, DateTime>{};
  bool _loaded = false;
  String _cachePath = '';

  // ── Images URL cache ───────────────────────────────────────────────────────
  final _imagesCache = <String, List<String>>{};
  final _imagesFetchedAt = <String, DateTime>{};
  bool _imagesLoaded = false;
  String _imagesCachePath = '';

  // ── Metadata cache loading / persistence ───────────────────────────────────

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _cachePath = p.join(dir.path, 'imdb_cache.json');
      final file = File(_cachePath);
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final e in raw.entries) {
        final v = e.value as Map<String, dynamic>;
        final at = DateTime.tryParse(v['fetchedAt'] as String? ?? '');
        if (at == null) continue;
        _fetchedAt[e.key] = at;
        _cache[e.key] = ImdbData.fromJson(v['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    if (_cachePath.isEmpty) return;
    try {
      final out = {
        for (final id in _cache.keys)
          id: {
            'fetchedAt': _fetchedAt[id]!.toIso8601String(),
            'data': _cache[id]!.toJson(),
          }
      };
      await File(_cachePath).writeAsString(jsonEncode(out));
    } catch (_) {}
  }

  // ── Images cache loading / persistence ─────────────────────────────────────

  Future<void> _ensureImagesLoaded() async {
    if (_imagesLoaded) return;
    _imagesLoaded = true;
    try {
      final dir = await getApplicationSupportDirectory();
      _imagesCachePath = p.join(dir.path, 'imdb_images_cache.json');
      final file = File(_imagesCachePath);
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final e in raw.entries) {
        final v = e.value as Map<String, dynamic>;
        final at = DateTime.tryParse(v['fetchedAt'] as String? ?? '');
        if (at == null) continue;
        _imagesFetchedAt[e.key] = at;
        _imagesCache[e.key] = (v['urls'] as List<dynamic>)
            .map((u) => u.toString())
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _persistImages() async {
    if (_imagesCachePath.isEmpty) return;
    try {
      final out = {
        for (final id in _imagesCache.keys)
          if (_imagesFetchedAt.containsKey(id))
            id: {
              'fetchedAt': _imagesFetchedAt[id]!.toIso8601String(),
              'urls': _imagesCache[id],
            }
      };
      await File(_imagesCachePath).writeAsString(jsonEncode(out));
    } catch (_) {}
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool _isFresh(String id) {
    if (!_cache.containsKey(id)) return false;
    final t = _fetchedAt[id];
    return t != null && DateTime.now().difference(t) < _ttl;
  }

  /// Returns IMDB metadata for every ID in [ids].
  /// Hits the disk cache first; only fetches IDs that are missing or stale.
  Future<Map<String, ImdbData>> resolve(List<String> ids) async {
    await _ensureLoaded();

    final result = <String, ImdbData>{};
    final toFetch = <String>[];

    for (final id in ids) {
      if (_isFresh(id)) {
        result[id] = _cache[id]!;
      } else {
        toFetch.add(id);
      }
    }

    if (toFetch.isNotEmpty) {
      for (var i = 0; i < toFetch.length; i += _batchSize) {
        final batch = toFetch.sublist(i, min(i + _batchSize, toFetch.length));
        await _fetchBatch(batch, result);
      }
      await _persist();
    }

    return result;
  }

  /// Returns up to 4 extra image URLs for [imdbId].
  /// Results are persisted to disk with a 30-day TTL.
  Future<List<String>> fetchImages(String imdbId) async {
    await _ensureImagesLoaded();

    // Return from disk/memory cache if still fresh.
    if (_imagesCache.containsKey(imdbId)) {
      final at = _imagesFetchedAt[imdbId];
      if (at != null && DateTime.now().difference(at) < _ttl) {
        return _imagesCache[imdbId]!;
      }
    }

    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/titles/$imdbId/images?pageSize=4'),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        return _imagesCache[imdbId] ?? [];
      }
      final body = jsonDecode(resp.body);
      final list = body is List
          ? body
          : (body['images'] as List<dynamic>? ?? []);
      final urls = list
          .map((item) => item is String
              ? item
              : (item as Map<String, dynamic>)['url']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      _imagesCache[imdbId] = urls;
      _imagesFetchedAt[imdbId] = DateTime.now();
      unawaited(_persistImages());
      return urls;
    } catch (_) {
      return _imagesCache[imdbId] ?? [];
    }
  }

  Future<void> _fetchBatch(List<String> ids, Map<String, ImdbData> out) async {
    final qs = ids.map((id) => 'titleIds=$id').join('&');
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/titles:batchGet?$qs'),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      final list = body is List
          ? body
          : (body['titles'] as List<dynamic>? ?? []);
      for (final item in list) {
        final data = ImdbData.fromApi(item as Map<String, dynamic>);
        if (data.id.isEmpty) continue;
        _cache[data.id] = data;
        _fetchedAt[data.id] = DateTime.now();
        out[data.id] = data;
      }
    } catch (_) {}
  }

  /// Fetches image URLs for [imdbId] directly from the API (no cache).
  /// [page] is 0-indexed; the API caps pageSize at 50.
  Future<List<String>> fetchImagesUncached(String imdbId,
      {int count = 20, int page = 0}) async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/titles/$imdbId/images?pageSize=$count&page=$page'),
              headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body);
      final list = body is List
          ? body
          : (body['images'] as List<dynamic>? ?? []);
      return list
          .map((item) => item is String
              ? item
              : (item as Map<String, dynamic>)['url']?.toString() ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearCache() async {
    _cache.clear();
    _fetchedAt.clear();
    _imagesCache.clear();
    _imagesFetchedAt.clear();
    _loaded = false;
    _imagesLoaded = false;
    if (_cachePath.isNotEmpty) {
      try { await File(_cachePath).delete(); } catch (_) {}
      _cachePath = '';
    }
    if (_imagesCachePath.isNotEmpty) {
      try { await File(_imagesCachePath).delete(); } catch (_) {}
      _imagesCachePath = '';
    }
  }
}

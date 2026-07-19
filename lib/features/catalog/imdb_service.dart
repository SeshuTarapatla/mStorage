import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models/imdb_data.dart';

/// A single episode lookup request: which series/season/episode to fetch,
/// keyed for caching by the episode's own `tt` id (already known from the
/// Episodes sheet — the new API has no way to resolve an episode except via
/// its parent series + season + episode number).
typedef EpisodeRequest = ({
  String episodeImdbId,
  String seriesId,
  int season,
  int episode,
});

class ImdbService {
  static const _baseUrl = 'https://api.balloonerismm.workers.dev';
  static const _ttl = Duration(days: 30);
  static const _concurrency = 6;
  static const _headers = {'Accept': 'application/json'};

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

  // ── Low-level HTTP helper ───────────────────────────────────────────────────

  /// GETs `$_baseUrl$path`. Returns null on any failure (timeout, network
  /// error, etc.) rather than throwing — every caller treats "no data" as
  /// the normal not-found/unavailable case, same as the rest of this service.
  Future<http.Response?> _get(String path,
      {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await http
          .get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Runs [tasks] with at most [_concurrency] in flight at once.
  Future<void> _runInBatches(List<Future<void> Function()> tasks) async {
    for (var i = 0; i < tasks.length; i += _concurrency) {
      final window = tasks.sublist(i, min(i + _concurrency, tasks.length));
      await Future.wait(window.map((t) => t()));
    }
  }

  bool _isFresh(String id) {
    if (!_cache.containsKey(id)) return false;
    final t = _fetchedAt[id];
    return t != null && DateTime.now().difference(t) < _ttl;
  }

  // ── Single-title fetches ────────────────────────────────────────────────────

  Future<ImdbData?> _fetchMovie(String id) async {
    final results = await Future.wait([
      _get('/movie/$id'),
      _get('/movie/$id/credits'),
    ]);
    final detailResp = results[0];
    if (detailResp == null || detailResp.statusCode != 200) return null;
    try {
      final detail = jsonDecode(detailResp.body) as Map<String, dynamic>;
      final creditsResp = results[1];
      final credits = (creditsResp != null && creditsResp.statusCode == 200)
          ? jsonDecode(creditsResp.body) as Map<String, dynamic>
          : null;
      final data = ImdbData.fromMovieApi(detail, credits);
      return data.id.isEmpty ? null : data;
    } catch (_) {
      return null;
    }
  }

  Future<ImdbData?> _fetchTv(String id) async {
    final results = await Future.wait([
      _get('/tv/$id'),
      _get('/tv/$id/credits'),
    ]);
    final detailResp = results[0];
    if (detailResp == null || detailResp.statusCode != 200) return null;
    try {
      final detail = jsonDecode(detailResp.body) as Map<String, dynamic>;
      final creditsResp = results[1];
      final credits = (creditsResp != null && creditsResp.statusCode == 200)
          ? jsonDecode(creditsResp.body) as Map<String, dynamic>
          : null;
      final data = ImdbData.fromTvApi(detail, credits);
      return data.id.isEmpty ? null : data;
    } catch (_) {
      return null;
    }
  }

  Future<ImdbData?> _fetchEpisode(
      String seriesId, int season, int episode) async {
    final resp = await _get('/tv/$seriesId/season/$season/episode/$episode');
    if (resp == null || resp.statusCode != 200) return null;
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = ImdbData.fromEpisodeApi(json, parentId: seriesId);
      return data.id.isEmpty ? null : data;
    } catch (_) {
      return null;
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Resolves movie or TV-series metadata for every ID in [ids] — all of
  /// [kind]. Hits the disk cache first; only fetches IDs that are missing
  /// or stale.
  Future<Map<String, ImdbData>> resolve(List<String> ids, ImdbKind kind) async {
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
      await _runInBatches(toFetch.map((id) => () async {
            final data = kind == ImdbKind.movie
                ? await _fetchMovie(id)
                : await _fetchTv(id);
            if (data != null) {
              _cache[id] = data;
              _fetchedAt[id] = DateTime.now();
              result[id] = data;
            }
          }).toList());
      await _persist();
    }

    return result;
  }

  /// Resolves IDs of unknown type — tries the movie endpoint, then falls
  /// back to TV. Used where a pasted IMDb ID could be either (the request
  /// form, the admin requests queue). IDs that 404 on both are omitted
  /// from the result rather than guessed at.
  Future<Map<String, ImdbData>> resolveUnknown(List<String> ids) async {
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
      await _runInBatches(toFetch.map((id) => () async {
            final data = await _fetchMovie(id) ?? await _fetchTv(id);
            if (data != null) {
              _cache[id] = data;
              _fetchedAt[id] = DateTime.now();
              result[id] = data;
            }
          }).toList());
      await _persist();
    }

    return result;
  }

  /// Resolves a single TV episode via its series ID + season + episode
  /// number. [episodeImdbId] (from the Episodes sheet) is used as the
  /// cache key — the new API has no way to look an episode up by that ID
  /// alone.
  Future<ImdbData?> resolveEpisode({
    required String episodeImdbId,
    required String seriesId,
    required int season,
    required int episode,
  }) async {
    await _ensureLoaded();
    if (episodeImdbId.isNotEmpty && _isFresh(episodeImdbId)) {
      return _cache[episodeImdbId];
    }
    final data = await _fetchEpisode(seriesId, season, episode);
    if (data != null) {
      final key = episodeImdbId.isNotEmpty ? episodeImdbId : data.id;
      _cache[key] = data;
      _fetchedAt[key] = DateTime.now();
      unawaited(_persist());
    }
    return data;
  }

  /// Bulk version of [resolveEpisode], concurrency-capped like [resolve].
  /// Returns a map keyed by each request's `episodeImdbId`.
  Future<Map<String, ImdbData>> resolveEpisodes(
      List<EpisodeRequest> requests) async {
    await _ensureLoaded();

    final result = <String, ImdbData>{};
    final toFetch = <EpisodeRequest>[];

    for (final r in requests) {
      if (r.episodeImdbId.isNotEmpty && _isFresh(r.episodeImdbId)) {
        result[r.episodeImdbId] = _cache[r.episodeImdbId]!;
      } else {
        toFetch.add(r);
      }
    }

    if (toFetch.isNotEmpty) {
      await _runInBatches(toFetch.map((r) => () async {
            final data = await _fetchEpisode(r.seriesId, r.season, r.episode);
            if (data != null) {
              final key = r.episodeImdbId.isNotEmpty ? r.episodeImdbId : data.id;
              _cache[key] = data;
              _fetchedAt[key] = DateTime.now();
              result[key] = data;
            }
          }).toList());
      await _persist();
    }

    return result;
  }

  Future<List<String>?> _fetchAllImageUrls(String imdbId, ImdbKind kind) async {
    final path =
        kind == ImdbKind.movie ? '/movie/$imdbId/images' : '/tv/$imdbId/images';
    final resp = await _get(path, timeout: const Duration(seconds: 10));
    if (resp == null || resp.statusCode != 200) return null;
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final urls = <String>[];
      for (final key in const ['posters', 'backdrops', 'logos', 'stills']) {
        final list = body[key] as List<dynamic>? ?? const [];
        for (final item in list) {
          final url = (item as Map<String, dynamic>)['file_path']?.toString();
          if (url != null && url.isNotEmpty) urls.add(url);
        }
      }
      return urls;
    } catch (_) {
      return null;
    }
  }

  /// Returns up to 8 image URLs for [imdbId] (poster + stills, cached with
  /// a 30-day TTL). Used for on-demand extra images (e.g. card hover).
  Future<List<String>> fetchImages(String imdbId, ImdbKind kind) async {
    await _ensureImagesLoaded();

    if (_imagesCache.containsKey(imdbId)) {
      final at = _imagesFetchedAt[imdbId];
      if (at != null && DateTime.now().difference(at) < _ttl) {
        return _imagesCache[imdbId]!;
      }
    }

    final urls = await _fetchAllImageUrls(imdbId, kind);
    if (urls == null) return _imagesCache[imdbId] ?? [];

    final capped = urls.take(8).toList();
    _imagesCache[imdbId] = capped;
    _imagesFetchedAt[imdbId] = DateTime.now();
    unawaited(_persistImages());
    return capped;
  }

  /// Returns every image URL for [imdbId], uncached — used by the admin
  /// gallery, where the admin picks a handful to keep. The API returns all
  /// images in one response (no pagination), unlike the old source.
  Future<List<String>> fetchAllImages(String imdbId, ImdbKind kind) async {
    final urls = await _fetchAllImageUrls(imdbId, kind);
    return urls ?? [];
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

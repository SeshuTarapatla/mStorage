import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/theme/tab_colors.dart';
import 'imdb_service.dart';
import 'models/imdb_data.dart';
import 'models/series_entry.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

sealed class SeriesCatalogState {}

class SeriesCatalogIdle extends SeriesCatalogState {}

class SeriesCatalogLoading extends SeriesCatalogState {}

class SeriesCatalogLoaded extends SeriesCatalogState {
  final List<SeriesEntry> series;
  SeriesCatalogLoaded(this.series);
}

class SeriesCatalogError extends SeriesCatalogState {
  final String message;
  SeriesCatalogError(this.message);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final seriesProvider =
    StateNotifierProvider<SeriesNotifier, SeriesCatalogState>(
        (_) => SeriesNotifier());

/// Overrides the catalog tab palette when the Series sub-tab is active.
/// Null = use the default catalog (amber) palette.
final catalogSubPaletteProvider = StateProvider<TabPalette?>((ref) => null);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class SeriesNotifier extends StateNotifier<SeriesCatalogState> {
  SeriesNotifier() : super(SeriesCatalogIdle());

  static const _kCsvCacheTtl = Duration(hours: 1);
  String? _cacheDir;

  static String? _extractSheetId(String url) {
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  static String _seriesCsvUrl(String sheetId) =>
      'https://docs.google.com/spreadsheets/d/$sheetId'
      '/gviz/tq?tqx=out:csv&sheet=Series';

  static String _episodesCsvUrl(String sheetId) =>
      'https://docs.google.com/spreadsheets/d/$sheetId'
      '/gviz/tq?tqx=out:csv&sheet=Episodes';

  static String _validBody(http.Response resp) {
    if (resp.statusCode != 200 || resp.body.trimLeft().startsWith('<')) return '';
    return resp.body;
  }

  // ── Cache helpers ──────────────────────────────────────────────────────────

  Future<String> _ensureCacheDir() async {
    _cacheDir ??= (await getApplicationSupportDirectory()).path;
    return _cacheDir!;
  }

  Future<({String series, String episodes, DateTime fetchedAt})?> _loadCache(
      String sheetId) async {
    try {
      final dir  = await _ensureCacheDir();
      final file = File(p.join(dir, 'catalog_csv_series_$sheetId.json'));
      if (!file.existsSync()) return null;
      final map  = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final at   = DateTime.tryParse(map['fetchedAt'] as String? ?? '');
      if (at == null) return null;
      return (
        series:   map['series']   as String? ?? '',
        episodes: map['episodes'] as String? ?? '',
        fetchedAt: at,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(
      String sheetId, String seriesBody, String episodesBody) async {
    try {
      final dir = await _ensureCacheDir();
      await File(p.join(dir, 'catalog_csv_series_$sheetId.json'))
          .writeAsString(jsonEncode({
        'fetchedAt': DateTime.now().toIso8601String(),
        'series':   seriesBody,
        'episodes': episodesBody,
      }));
    } catch (_) {}
  }

  Future<void> _clearCache(String sheetId) async {
    try {
      final dir  = await _ensureCacheDir();
      final file = File(p.join(dir, 'catalog_csv_series_$sheetId.json'));
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

  Future<List<SeriesEntry>> _buildEntries(
      String seriesCsv, String episodesCsv) async {

    // ── Parse Series tab ────────────────────────────────────────────────────
    final Map<String, _SeriesFields> seriesById = {};
    final List<String> seriesOrder = [];

    if (seriesCsv.isNotEmpty) {
      final norm = seriesCsv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final rows = const CsvToListConverter(eol: '\n').convert(norm);

      if (rows.length >= 2) {
        final sh = {
          for (var i = 0; i < rows[0].length; i++)
            _norm(rows[0][i].toString()): i,
        };

        String sc(List<dynamic> row, List<String> aliases) {
          for (final a in aliases) {
            final idx = sh[a];
            if (idx != null && idx < row.length) {
              final v = row[idx].toString().trim();
              if (v.isNotEmpty) return v;
            }
          }
          return '';
        }

        final visIdx = sh['show'] ?? sh['enabled'] ?? sh['visible'];

        for (final row in rows.skip(1)) {
          if (row.isEmpty) continue;
          if (visIdx != null && visIdx < row.length) {
            if (row[visIdx].toString().trim().toLowerCase() == 'false') continue;
          }

          final imdbId = sc(row, ['seriesimdbid', 'imdbid', 'imdb']);
          if (imdbId.isEmpty) continue;

          if (!seriesById.containsKey(imdbId)) {
            seriesById[imdbId] = _SeriesFields();
            seriesOrder.add(imdbId);
          }

          final meta = seriesById[imdbId]!;
          if (meta.title.isEmpty) {
            meta.title = sc(row, ['title', 'seriestitle', 'showtitle', 'name']);
          }
          if (meta.posterUrl.isEmpty) {
            meta.posterUrl = _toPosterUrl(
                sc(row, ['posterurl', 'poster', 'image', 'imageurl', 'cover']));
          }
          if (meta.plot.isEmpty) {
            meta.plot = sc(row, ['plot', 'description', 'desc', 'synopsis', 'summary']);
          }
          if (meta.genres.isEmpty) {
            final g = sc(row, ['genres', 'genre', 'category']);
            if (g.isNotEmpty) {
              meta.genres = g.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            }
          }
          if (meta.tags.isEmpty) {
            final t = sc(row, ['tags', 'tag']);
            if (t.isNotEmpty) {
              meta.tags = t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            }
          }
          meta.rating ??= double.tryParse(sc(row, ['rating']));
          if (meta.certificate == null) {
            final c = sc(row, ['certificate', 'cert', 'rated']);
            if (c.isNotEmpty) meta.certificate = c;
          }
          if (meta.stars.isEmpty) {
            final s = sc(row, ['stars', 'cast']);
            if (s.isNotEmpty) {
              meta.stars = s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
            }
          }
        }
      }
    }

    // ── Parse Episodes tab ──────────────────────────────────────────────────
    // Map: series_imdb_id → Map<season → List<EpisodeEntry>>
    final Map<String, Map<int, List<EpisodeEntry>>> episodeTree = {};

    if (episodesCsv.isNotEmpty) {
      final norm = episodesCsv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final rows = const CsvToListConverter(eol: '\n').convert(norm);

      if (rows.length >= 2) {
        final eh = {
          for (var i = 0; i < rows[0].length; i++)
            _norm(rows[0][i].toString()): i,
        };

        String ec(List<dynamic> row, List<String> aliases) {
          for (final a in aliases) {
            final idx = eh[a];
            if (idx != null && idx < row.length) {
              final v = row[idx].toString().trim();
              if (v.isNotEmpty) return v;
            }
          }
          return '';
        }

        final visIdx = eh['show'] ?? eh['enabled'] ?? eh['visible'];

        for (final row in rows.skip(1)) {
          if (row.isEmpty) continue;
          if (visIdx != null && visIdx < row.length) {
            if (row[visIdx].toString().trim().toLowerCase() == 'false') continue;
          }

          final seriesId = ec(row, ['seriesimdbid', 'seriesid']);
          if (seriesId.isEmpty) continue;

          final episodeImdbId = ec(row, ['episodeimdbid', 'episodeid', 'imdbid']);
          final season  = int.tryParse(ec(row, ['season', 's'])) ?? 1;
          final epNum   = int.tryParse(ec(row, ['episode', 'ep', 'e'])) ?? 1;
          final title   = ec(row, ['title', 'episodetitle', 'eptitle']);
          final airDate = DateTime.tryParse(ec(row, ['airdate', 'air_date', 'date', 'aired']));
          final thumb   = ec(row, ['thumbnailurl', 'thumbnail', 'posterurl', 'image']);
          final plot    = ec(row, ['plot', 'description']);
          final rating  = double.tryParse(ec(row, ['rating']));
          final runtimeMin = int.tryParse(ec(row, ['runtimemin', 'runtime', 'runtimeminutes']));
          final videoUrl = ec(row, ['videourl', 'url', 'googlephotosurl', 'albumurl', 'link']);
          final sizeMb  = int.tryParse(ec(row, ['sizemb', 'size', 'filesize']));
          final encoded = ec(row, ['encoded']).toLowerCase() == 'true';

          final ep = EpisodeEntry(
            episodeNumber: epNum,
            title: title,
            imdbId: episodeImdbId,
            airDate: airDate,
            videoUrl: videoUrl,
            sizeMb: sizeMb,
            encoded: encoded,
            plot: plot,
            posterUrl: thumb,
            imdbRating: rating,
            runtimeSeconds: runtimeMin != null ? runtimeMin * 60 : null,
          );

          episodeTree
              .putIfAbsent(seriesId, () => {})
              .putIfAbsent(season, () => [])
              .add(ep);
        }
      }
    }

    // ── Assemble SeriesEntry list ────────────────────────────────────────────
    final rawEntries = seriesOrder.map((imdbId) {
      final meta     = seriesById[imdbId]!;
      final seasonMap = episodeTree[imdbId] ?? {};
      final seasons  = (seasonMap.keys.toList()..sort())
          .map((n) {
            final eps = seasonMap[n]!
              ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
            return SeasonEntry(number: n, episodes: eps);
          })
          .toList();

      return SeriesEntry(
        title: meta.title,
        imdbId: imdbId,
        posterUrl: meta.posterUrl,
        plot: meta.plot,
        genres: meta.genres,
        tags: meta.tags,
        imdbRating: meta.rating,
        certificate: meta.certificate,
        stars: meta.stars,
        seasons: seasons,
      );
    }).toList();

    // ── Series-level IMDB enrichment ───────────────────────────────────────
    // Only rows still missing an IMDB-fillable field trigger a fetch — a
    // fully backfilled sheet row never touches the API.
    final seriesToFetch = rawEntries
        .where((e) => e.imdbId.isNotEmpty && e.needsImdbFetch)
        .map((e) => e.imdbId)
        .toList();

    final seriesImdbMap = seriesToFetch.isNotEmpty
        ? await ImdbService().resolve(seriesToFetch, ImdbKind.tv)
        : <String, ImdbData>{};

    final seriesEnriched = rawEntries.map((e) {
      final data = seriesImdbMap[e.imdbId];
      if (data == null) return e;
      return e.withImdb(
        posterUrl: data.posterUrl,
        plot: data.plot,
        genres: data.genres,
        rating: data.rating,
        certificate: data.certificate,
        stars: data.stars,
      );
    }).toList();

    // ── Episode-level IMDB enrichment ────────────────────────────────────────
    // The new API has no way to resolve an episode by its own ID — it's
    // reached via series ID + season + episode number, both already in the
    // Episodes sheet.
    final episodeRequests = <EpisodeRequest>[];
    for (final series in seriesEnriched) {
      if (series.imdbId.isEmpty) continue;
      for (final season in series.seasons) {
        for (final ep in season.episodes) {
          if (ep.imdbId.isNotEmpty && ep.needsImdbFetch) {
            episodeRequests.add((
              episodeImdbId: ep.imdbId,
              seriesId: series.imdbId,
              season: season.number,
              episode: ep.episodeNumber,
            ));
          }
        }
      }
    }

    if (episodeRequests.isEmpty) return seriesEnriched;

    final epImdbMap = await ImdbService().resolveEpisodes(episodeRequests);
    if (epImdbMap.isEmpty) return seriesEnriched;

    return seriesEnriched.map((series) {
      final enrichedSeasons = series.seasons.map((season) {
        final enrichedEps = season.episodes.map((ep) {
          final data = epImdbMap[ep.imdbId];
          if (data == null) return ep;
          return ep.withImdb(
            title: data.title,
            airDate: data.releaseDate,
            rating: data.rating,
            plot: data.plot,
            posterUrl: data.posterUrl,
            runtimeSeconds: data.runtimeSeconds,
          );
        }).toList();
        return SeasonEntry(number: season.number, episodes: enrichedEps);
      }).toList();
      return SeriesEntry(
        title: series.title,
        imdbId: series.imdbId,
        posterUrl: series.posterUrl,
        plot: series.plot,
        genres: series.genres,
        tags: series.tags,
        language: series.language,
        imdbRating: series.imdbRating,
        certificate: series.certificate,
        stars: series.stars,
        seasons: enrichedSeasons,
      );
    }).toList();
  }

  static String _toPosterUrl(String url) {
    final match = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (match != null) {
      return 'https://drive.google.com/thumbnail?id=${match.group(1)}&sz=w400';
    }
    return url;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load(String sheetUrl, {bool forceRefresh = false}) async {
    state = SeriesCatalogLoading();

    final sheetId = _extractSheetId(sheetUrl);
    if (sheetId == null) {
      state = SeriesCatalogError('Invalid Google Sheets URL.');
      return;
    }

    if (forceRefresh) {
      unawaited(_clearCache(sheetId));
    } else {
      final cached = await _loadCache(sheetId);
      if (cached != null) {
        final entries = await _buildEntries(cached.series, cached.episodes);
        if (mounted) state = SeriesCatalogLoaded(entries);

        final age = DateTime.now().difference(cached.fetchedAt);
        if (age < _kCsvCacheTtl) return;

        _silentRefresh(sheetId, cached.series, cached.episodes);
        return;
      }
    }

    try {
      final results = await Future.wait([
        http.get(Uri.parse(_seriesCsvUrl(sheetId))),
        http.get(Uri.parse(_episodesCsvUrl(sheetId))),
      ]);

      final seriesBody   = _validBody(results[0]);
      final episodesBody = _validBody(results[1]);

      unawaited(_saveCache(sheetId, seriesBody, episodesBody));
      final entries = await _buildEntries(seriesBody, episodesBody);
      if (mounted) state = SeriesCatalogLoaded(entries);
    } catch (e) {
      if (mounted) state = SeriesCatalogError('Failed to fetch series: $e');
    }
  }

  Future<void> _silentRefresh(
      String sheetId, String cachedSeries, String cachedEpisodes) async {
    try {
      final results = await Future.wait([
        http.get(Uri.parse(_seriesCsvUrl(sheetId))),
        http.get(Uri.parse(_episodesCsvUrl(sheetId))),
      ]);

      final seriesBody   = _validBody(results[0]);
      final episodesBody = _validBody(results[1]);

      if (seriesBody == cachedSeries && episodesBody == cachedEpisodes) {
        unawaited(_saveCache(sheetId, cachedSeries, cachedEpisodes));
        return;
      }

      unawaited(_saveCache(sheetId, seriesBody, episodesBody));
      final entries = await _buildEntries(seriesBody, episodesBody);
      if (mounted) state = SeriesCatalogLoaded(entries);
    } catch (_) {}
  }

  void reset() => state = SeriesCatalogIdle();
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _SeriesFields {
  String title    = '';
  String imdbId   = '';
  String posterUrl = '';
  String plot     = '';
  List<String> genres = [];
  List<String> tags   = [];
  String? language;
  double? rating;
  String? certificate;
  List<String> stars = [];
}

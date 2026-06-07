import 'imdb_data.dart';

class CatalogEntry {
  // ── Sheet-sourced (always present) ──────────────────────────────────────
  final String imdbId;
  final String videoUrl;
  final int? sizeMb;
  final bool encoded;

  // ── May come from sheet OR IMDB API ────────────────────────────────────
  final String title;
  final DateTime? date;
  final String plot;
  final String thumbnailUrl;

  // ── Genre-style tags (Action, Thriller) — sheet or IMDB API ─────────────
  final List<String> genres;

  // ── Franchise/platform tags (Marvel, Disney) — sheet only ───────────────
  final List<String> tags;

  // ── IMDB API only (null when no imdbId) ─────────────────────────────────
  final double? imdbRating;
  final int? voteCount;
  final int? runtimeSeconds;
  final List<String> stars;
  final String? certificate;

  // ── Sheet-sourced extras ─────────────────────────────────────────────────
  final String? language;

  /// Comma-separated image URLs from the `slide_images` sheet column.
  final List<String> slideImages;

  const CatalogEntry({
    required this.imdbId,
    required this.title,
    required this.date,
    required this.genres,
    required this.tags,
    required this.plot,
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.sizeMb,
    required this.encoded,
    this.imdbRating,
    this.voteCount,
    this.runtimeSeconds,
    this.stars = const [],
    this.certificate,
    this.language,
    this.slideImages = const [],
  });

  // ── Normalized header aliases ────────────────────────────────────────────
  // Headers are pre-normalized to lowercase+no-separators by the notifier.
  static const _hImdbId    = ['imdbid', 'imdb', 'titleid'];
  static const _hVideoUrl  = ['videourl', 'url', 'googlephotourl',
                               'googlephotosurl', 'albumurl', 'link',
                               'photosurl'];
  static const _hSizeMb    = ['sizemb', 'size', 'filesizeMb', 'filesize'];
  static const _hEncoded   = ['encoded', 'hidden', 'masked'];
  static const _hLanguage  = ['language', 'lang'];
  static const _hTitle     = ['title', 'name', 'movietitle', 'filmtitle'];
  static const _hDate      = ['date', 'releasedate', 'year', 'released'];
  static const _hGenres    = ['genres', 'genre', 'category'];
  static const _hTags      = ['tags', 'tag'];
  static const _hPlot      = ['plot', 'description', 'desc', 'synopsis',
                               'summary'];
  static const _hThumb     = ['posterurl', 'thumbnail', 'thumbnailurl',
                               'poster', 'image', 'imageurl', 'cover'];
  static const _hSlides    = ['slideimages', 'slides', 'extraimages',
                               'slideshow', 'galleryimages'];

  /// Parses a data row using the normalized header map produced by
  /// [CatalogNotifier] (keys are lowercase with separators stripped).
  factory CatalogEntry.fromRow(
      List<dynamic> row, Map<String, int> headers) {
    String get(List<String> aliases) {
      for (final alias in aliases) {
        final idx = headers[alias];
        if (idx != null && idx < row.length) {
          final v = row[idx].toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    final imdbId    = get(_hImdbId);
    final videoUrl  = get(_hVideoUrl);
    final sizeRaw   = get(_hSizeMb);
    final encoded   = get(_hEncoded).toLowerCase() == 'true';
    final language  = get(_hLanguage).let((v) => v.isEmpty ? null : v);
    final title     = get(_hTitle).let((v) => v.isEmpty ? imdbId : v);
    final dateRaw   = get(_hDate);
    final genresRaw = get(_hGenres);
    final tagsRaw   = get(_hTags);
    final plot      = get(_hPlot);
    final thumbRaw  = get(_hThumb);
    final slidesRaw = get(_hSlides);

    return CatalogEntry(
      imdbId:       imdbId,
      title:        title,
      date:         DateTime.tryParse(dateRaw),
      genres:       genresRaw.isEmpty
                      ? const []
                      : genresRaw.split(',').map((t) => t.trim()).toList(),
      tags:         tagsRaw.isEmpty
                      ? const []
                      : tagsRaw.split(',').map((t) => t.trim()).toList(),
      plot:         plot,
      thumbnailUrl: _toPosterUrl(thumbRaw),
      videoUrl:     videoUrl,
      sizeMb:       int.tryParse(sizeRaw),
      encoded:      encoded,
      language:     language,
      slideImages:  slidesRaw.isEmpty
                      ? const []
                      : slidesRaw.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList(),
    );
  }

  /// Returns a new entry with IMDB metadata merged in.
  /// Sheet values always win when present; API fills in only what the sheet left blank.
  CatalogEntry mergeImdb(ImdbData data) => CatalogEntry(
        imdbId:       imdbId,
        title:        title.isNotEmpty ? title : data.title,
        date:         date ?? data.releaseDate,
        genres:       genres.isNotEmpty ? genres : data.genres,
        tags:         tags,
        plot:         plot.isNotEmpty ? plot : data.plot,
        thumbnailUrl: thumbnailUrl.isNotEmpty ? thumbnailUrl : data.posterUrl,
        videoUrl:     videoUrl,
        sizeMb:       sizeMb,
        encoded:      encoded,
        imdbRating:   data.rating,
        voteCount:    data.voteCount,
        runtimeSeconds: data.runtimeSeconds,
        stars:        data.stars,
        certificate:  data.certificate,
        language:     language,
        slideImages:  slideImages,
      );

  static String _toPosterUrl(String url) {
    if (url.isEmpty) return url;
    final match = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (match != null) {
      return 'https://drive.google.com/thumbnail?id=${match.group(1)}&sz=w400';
    }
    return url;
  }

  /// "2h 18m" / "45m" from runtimeSeconds.
  String? get runtimeLabel {
    if (runtimeSeconds == null) return null;
    final h = runtimeSeconds! ~/ 3600;
    final m = (runtimeSeconds! % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

/// Which IMDB entity type a title resolved as.
/// Set whenever the kind was determined by the fetch (movie vs tv detail
/// endpoint that actually returned 200) rather than assumed by the caller.
enum ImdbKind { movie, tv }

class ImdbData {
  final String id;
  final ImdbKind? kind;
  final String title;
  final String plot;
  final List<String> genres;
  final DateTime? releaseDate;
  final String posterUrl;
  final double? rating;
  final int? voteCount;
  final int? runtimeSeconds;
  final List<String> stars;
  final String? certificate;
  // TV series fields — null for movies / episodes
  final int? endYear; // end year for a series (null if ongoing or not a series)
  // TV episode fields — null for movies / series
  final int? seasonNumber;
  final int? episodeNumber;
  final String? parentId; // parent series IMDB ID

  const ImdbData({
    required this.id,
    this.kind,
    required this.title,
    required this.plot,
    required this.genres,
    required this.releaseDate,
    required this.posterUrl,
    required this.rating,
    required this.voteCount,
    required this.runtimeSeconds,
    required this.stars,
    required this.certificate,
    this.endYear,
    this.seasonNumber,
    this.episodeNumber,
    this.parentId,
  });

  /// Parses a `GET /movie/{id}` response, optionally merging in cast names
  /// from a companion `GET /movie/{id}/credits` response.
  factory ImdbData.fromMovieApi(Map<String, dynamic> detail,
      [Map<String, dynamic>? credits]) {
    final cert = detail['certificate'] as Map<String, dynamic>?;
    // API runtime is in minutes; the app's internal field is seconds.
    final runtimeMin = (detail['runtime'] as num?)?.toInt();

    return ImdbData(
      id: detail['id'] as String? ?? '',
      kind: ImdbKind.movie,
      title: detail['title'] as String? ?? '',
      plot: detail['overview'] as String? ?? '',
      genres: _genreNames(detail['genres']),
      releaseDate: _parseDate(detail['release_date']),
      posterUrl: detail['poster_path'] as String? ?? '',
      rating: (detail['vote_average'] as num?)?.toDouble(),
      voteCount: (detail['vote_count'] as num?)?.toInt(),
      runtimeSeconds: runtimeMin != null ? runtimeMin * 60 : null,
      stars: _castNames(credits),
      certificate: cert?['rating'] as String?,
    );
  }

  /// Parses a `GET /tv/{id}` response, optionally merging in cast names
  /// from a companion `GET /tv/{id}/credits` response.
  factory ImdbData.fromTvApi(Map<String, dynamic> detail,
      [Map<String, dynamic>? credits]) {
    final cert = detail['certificate'] as Map<String, dynamic>?;
    final inProduction = detail['in_production'] as bool? ?? false;
    final lastAirDate = _parseDate(detail['last_air_date']);

    return ImdbData(
      id: detail['id'] as String? ?? '',
      kind: ImdbKind.tv,
      title: detail['name'] as String? ?? '',
      plot: detail['overview'] as String? ?? '',
      genres: _genreNames(detail['genres']),
      releaseDate: _parseDate(detail['first_air_date']),
      posterUrl: detail['poster_path'] as String? ?? '',
      rating: (detail['vote_average'] as num?)?.toDouble(),
      voteCount: (detail['vote_count'] as num?)?.toInt(),
      runtimeSeconds: null, // a series has no single runtime value
      stars: _castNames(credits),
      certificate: cert?['rating'] as String?,
      endYear: inProduction ? null : lastAirDate?.year,
    );
  }

  /// Parses a `GET /tv/{seriesId}/season/{s}/episode/{e}` response.
  /// [parentId] is the series ID used to make the request — the response
  /// itself doesn't echo it back.
  factory ImdbData.fromEpisodeApi(Map<String, dynamic> json,
      {required String parentId}) {
    return ImdbData(
      id: json['id'] as String? ?? '',
      kind: ImdbKind.tv,
      title: json['name'] as String? ?? '',
      plot: json['overview'] as String? ?? '',
      genres: const [],
      releaseDate: _parseDate(json['air_date']),
      posterUrl: json['still_path'] as String? ?? '',
      rating: (json['vote_average'] as num?)?.toDouble(),
      voteCount: (json['vote_count'] as num?)?.toInt(),
      // Episode runtime from this endpoint is already in seconds.
      runtimeSeconds: (json['runtime'] as num?)?.toInt(),
      stars: const [],
      certificate: null,
      seasonNumber: (json['season_number'] as num?)?.toInt(),
      episodeNumber: (json['episode_number'] as num?)?.toInt(),
      parentId: parentId,
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static List<String> _genreNames(dynamic raw) {
    final list = raw as List<dynamic>? ?? const [];
    return list
        .map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<String> _castNames(Map<String, dynamic>? credits) {
    if (credits == null) return const [];
    final cast = credits['cast'] as List<dynamic>? ?? const [];
    return cast
        .take(3)
        .map((c) => (c as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Parse from the on-disk cache.
  factory ImdbData.fromJson(Map<String, dynamic> j) => ImdbData(
        id: j['id'] as String? ?? '',
        kind: switch (j['kind'] as String?) {
          'movie' => ImdbKind.movie,
          'tv' => ImdbKind.tv,
          _ => null,
        },
        title: j['title'] as String? ?? '',
        plot: j['plot'] as String? ?? '',
        genres: (j['genres'] as List<dynamic>? ?? []).map((g) => '$g').toList(),
        releaseDate: j['releaseDate'] != null
            ? DateTime.tryParse(j['releaseDate'] as String)
            : null,
        posterUrl: j['posterUrl'] as String? ?? '',
        rating: (j['rating'] as num?)?.toDouble(),
        voteCount: j['voteCount'] as int?,
        runtimeSeconds: j['runtimeSeconds'] as int?,
        stars: (j['stars'] as List<dynamic>? ?? []).map((s) => '$s').toList(),
        certificate: j['certificate'] as String?,
        endYear: j['endYear'] as int?,
        seasonNumber: j['seasonNumber'] as int?,
        episodeNumber: j['episodeNumber'] as int?,
        parentId: j['parentId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (kind != null) 'kind': kind == ImdbKind.movie ? 'movie' : 'tv',
        'title': title,
        'plot': plot,
        'genres': genres,
        'releaseDate': releaseDate?.toIso8601String(),
        'posterUrl': posterUrl,
        'rating': rating,
        'voteCount': voteCount,
        'runtimeSeconds': runtimeSeconds,
        'stars': stars,
        'certificate': certificate,
        if (endYear != null) 'endYear': endYear,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        if (parentId != null) 'parentId': parentId,
      };
}

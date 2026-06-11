class ImdbData {
  final String id;
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
  final int? endYear; // end year for tvSeries (null if ongoing or not a series)
  // TV episode fields — null for movies / series
  final int? seasonNumber;
  final int? episodeNumber;
  final String? parentId; // parent series IMDB ID

  const ImdbData({
    required this.id,
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

  /// Parse from the live API response.
  factory ImdbData.fromApi(Map<String, dynamic> json) {
    final img = json['primaryImage'] as Map<String, dynamic>?;
    final posterUrl = img?['url'] as String? ?? '';

    final genres = (json['genres'] as List<dynamic>? ?? [])
        .map((g) => g.toString())
        .toList();

    // API uses either a releaseDate object or a bare startYear integer.
    DateTime? releaseDate;
    final rd = json['releaseDate'] as Map<String, dynamic>?;
    if (rd != null) {
      final y = rd['year'] as int?;
      if (y != null) {
        releaseDate = DateTime(y, rd['month'] as int? ?? 1, rd['day'] as int? ?? 1);
      }
    } else {
      final y = json['startYear'] as int?;
      if (y != null) releaseDate = DateTime(y);
    }

    final ratingObj = json['rating'] as Map<String, dynamic>?;
    final rating = (ratingObj?['aggregateRating'] as num?)?.toDouble();
    final voteCount = ratingObj?['voteCount'] as int?;

    final stars = (json['stars'] as List<dynamic>? ?? [])
        .take(3)
        .map((s) => (s as Map<String, dynamic>)['displayName']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final certs = json['certificates'] as List<dynamic>? ?? [];
    String? certificate;
    for (final c in certs) {
      final cm = c as Map<String, dynamic>;
      if (cm['country'] == 'US') {
        certificate = cm['rating']?.toString();
        break;
      }
    }
    certificate ??= certs.isNotEmpty
        ? (certs.first as Map<String, dynamic>)['rating']?.toString()
        : null;

    final endYear = json['endYear'] as int?;

    // TV episode: season / episode number and parent series ID.
    // API may return these flat or nested under an "episode" object.
    final epObj = json['episode'] as Map<String, dynamic>?;
    final seasonNumber = (json['seasonNumber'] as num?)?.toInt()
        ?? (epObj?['seasonNumber'] as num?)?.toInt();
    final episodeNumber = (json['episodeNumber'] as num?)?.toInt()
        ?? (epObj?['episodeNumber'] as num?)?.toInt();
    // Parent series ID: try several common field names.
    final seriesObj = json['series'] as Map<String, dynamic>?;
    final parentId = json['seriesId'] as String?
        ?? json['parentId'] as String?
        ?? seriesObj?['id'] as String?;

    return ImdbData(
      id: json['id'] as String? ?? '',
      // API field is primaryTitle, not title
      title: json['primaryTitle'] as String? ?? json['title'] as String? ?? '',
      plot: json['plot'] as String? ?? '',
      genres: genres,
      releaseDate: releaseDate,
      posterUrl: posterUrl,
      rating: rating,
      voteCount: voteCount,
      runtimeSeconds: json['runtimeSeconds'] as int?,
      stars: stars,
      certificate: certificate,
      endYear: endYear,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      parentId: parentId?.isNotEmpty == true ? parentId : null,
    );
  }

  /// Parse from the on-disk cache.
  factory ImdbData.fromJson(Map<String, dynamic> j) => ImdbData(
        id: j['id'] as String? ?? '',
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

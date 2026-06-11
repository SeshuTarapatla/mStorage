class SeriesEntry {
  final String title;
  final String imdbId;
  final String posterUrl;
  final String plot;
  final List<String> genres;
  final List<String> tags;
  final String? language;
  final double? imdbRating;
  final List<SeasonEntry> seasons;

  const SeriesEntry({
    required this.title,
    required this.imdbId,
    required this.posterUrl,
    required this.plot,
    required this.genres,
    required this.tags,
    this.language,
    this.imdbRating,
    required this.seasons,
  });

  int get totalEpisodes => seasons.fold(0, (s, e) => s + e.episodes.length);

  SeriesEntry withImdb({
    required String posterUrl,
    required String plot,
    required List<String> genres,
    required double? rating,
  }) =>
      SeriesEntry(
        title: title,
        imdbId: imdbId,
        posterUrl: this.posterUrl.isNotEmpty ? this.posterUrl : posterUrl,
        plot: this.plot.isNotEmpty ? this.plot : plot,
        genres: this.genres.isNotEmpty ? this.genres : genres,
        tags: tags,
        language: language,
        imdbRating: rating,
        seasons: seasons,
      );
}

class SeasonEntry {
  final int number;
  final List<EpisodeEntry> episodes;

  const SeasonEntry({required this.number, required this.episodes});
}

class EpisodeEntry {
  final int episodeNumber;
  final String title;
  final String imdbId;
  final DateTime? airDate;
  final String videoUrl;
  final int? sizeMb;
  final bool encoded;
  final double? imdbRating;
  final String plot;
  final String posterUrl;
  final int? runtimeSeconds;

  const EpisodeEntry({
    required this.episodeNumber,
    required this.title,
    this.imdbId = '',
    this.airDate,
    required this.videoUrl,
    this.sizeMb,
    required this.encoded,
    this.imdbRating,
    this.plot = '',
    this.posterUrl = '',
    this.runtimeSeconds,
  });

  String get displayTitle =>
      title.isNotEmpty ? title : 'Episode $episodeNumber';

  String get runtimeLabel {
    if (runtimeSeconds == null) return '';
    final m = runtimeSeconds! ~/ 60;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
  }

  EpisodeEntry withImdb(
      {required String title,
      required DateTime? airDate,
      required double? rating,
      required String plot,
      required String posterUrl,
      required int? runtimeSeconds}) =>
      EpisodeEntry(
        episodeNumber: episodeNumber,
        title: this.title.isNotEmpty ? this.title : title,
        imdbId: imdbId,
        airDate: this.airDate ?? airDate,
        videoUrl: videoUrl,
        sizeMb: sizeMb,
        encoded: encoded,
        imdbRating: rating,
        plot: plot,
        posterUrl: posterUrl,
        runtimeSeconds: runtimeSeconds,
      );
}

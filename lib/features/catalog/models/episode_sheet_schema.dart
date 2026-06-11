/// Canonical column order for the Episodes tab in the Google Sheet.
/// One row per episode; episode_imdb_id is the primary key,
/// series_imdb_id is the foreign key → Series tab.
class EpisodeSheetSchema {
  EpisodeSheetSchema._();

  static const List<String> columns = [
    'episode_imdb_id',  // 0 — primary key
    'series_imdb_id',   // 1 — FK → Series.series_imdb_id
    'season',           // 2
    'episode',          // 3
    'title',            // 4
    'air_date',         // 5 — YYYY-MM-DD
    'thumbnail_url',    // 6 — wide episode still
    'plot',             // 7 — episode-specific plot
    'rating',           // 8
    'video_url',        // 9
    'size_mb',          // 10
    'language',         // 11
    'encoded',          // 12 — TRUE / FALSE
    'show',             // 13 — TRUE / FALSE
  ];

  static const int iEpisodeImdbId = 0;
  static const int iSeriesImdbId  = 1;
  static const int iSeason        = 2;
  static const int iEpisode       = 3;
  static const int iTitle         = 4;
  static const int iAirDate       = 5;
  static const int iThumbnailUrl  = 6;
  static const int iPlot          = 7;
  static const int iRating        = 8;
  static const int iVideoUrl      = 9;
  static const int iSizeMb        = 10;
  static const int iLanguage      = 11;
  static const int iEncoded       = 12;
  static const int iShow          = 13;

  static const int columnCount = 14;

  static String get headerTsv => columns.join('\t');

  static List<String> parseTsv(String tsv) {
    final parts = tsv.split('\t').map((s) => s.trim()).toList();
    while (parts.length < columnCount) { parts.add(''); }
    return parts;
  }

  static String buildTsv(List<String> values) => values.join('\t');
}

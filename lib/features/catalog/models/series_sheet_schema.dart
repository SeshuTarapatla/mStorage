/// Canonical column order for the Series tab in the Google Sheet.
/// One row per TV show; series_imdb_id is the primary key.
class SeriesSheetSchema {
  SeriesSheetSchema._();

  static const List<String> columns = [
    'series_imdb_id',  // 0 — primary key
    'title',           // 1
    'start_year',      // 2
    'end_year',        // 3
    'poster_url',      // 4
    'plot',            // 5
    'rating',          // 6
    'genres',          // 7 — comma-separated
    'tags',            // 8 — comma-separated
    'show',            // 9 — TRUE / FALSE
  ];

  static const int iSeriesImdbId = 0;
  static const int iTitle        = 1;
  static const int iStartYear    = 2;
  static const int iEndYear      = 3;
  static const int iPosterUrl    = 4;
  static const int iPlot         = 5;
  static const int iRating       = 6;
  static const int iGenres       = 7;
  static const int iTags         = 8;
  static const int iShow         = 9;

  static const int columnCount = 10;

  static String get headerTsv => columns.join('\t');

  static List<String> parseTsv(String tsv) {
    final parts = tsv.split('\t').map((s) => s.trim()).toList();
    while (parts.length < columnCount) { parts.add(''); }
    return parts;
  }

  static String buildTsv(List<String> values) => values.join('\t');
}

/// Canonical column order for the Google Sheet.
/// All admin output and clipboard paste/copy use these indices.
/// To change the schema, update this class only — everything else follows.
class SheetSchema {
  SheetSchema._();

  static const List<String> columns = [
    'title',
    'imdb_id',
    'date',
    'video_url',
    'poster_url',
    'size_mb',
    'language',
    'plot',
    'genres',
    'tags',
    'encoded',
    'show',
    'slide_images',
  ];

  static const int iTitle       = 0;
  static const int iImdbId      = 1;
  static const int iDate        = 2;
  static const int iVideoUrl    = 3;
  static const int iPosterUrl   = 4;
  static const int iSizeMb      = 5;
  static const int iLanguage    = 6;
  static const int iPlot        = 7;
  static const int iGenres      = 8;
  static const int iTags        = 9;
  static const int iEncoded     = 10;
  static const int iShow        = 11;
  static const int iSlideImages = 12;

  static const int columnCount = 13;

  /// Tab-separated header row, ready to paste as the first row of a sheet.
  static String get headerTsv => columns.join('\t');

  /// Splits a tab-separated clipboard row into a fixed-length list.
  /// Pads with empty strings if the pasted row has fewer columns.
  static List<String> parseTsv(String tsv) {
    final parts = tsv.split('\t').map((s) => s.trim()).toList();
    while (parts.length < columnCount) { parts.add(''); }
    return parts;
  }

  /// Builds a tab-separated row from a list of values in column order.
  static String buildTsv(List<String> values) => values.join('\t');
}

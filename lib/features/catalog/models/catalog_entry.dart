class CatalogEntry {
  final String title;
  final DateTime? date;
  final List<String> tags;
  final String description;
  final String thumbnailUrl;
  final String photosUrl;
  final int? sizeMb;
  final bool encoded;

  const CatalogEntry({
    required this.title,
    required this.date,
    required this.tags,
    required this.description,
    required this.thumbnailUrl,
    required this.photosUrl,
    required this.sizeMb,
    required this.encoded,
  });

  factory CatalogEntry.fromRow(List<dynamic> row) {
    String cell(int i) => i < row.length ? row[i].toString().trim() : '';

    return CatalogEntry(
      title: cell(0),
      date: DateTime.tryParse(cell(1)),
      tags: cell(2).isEmpty ? [] : cell(2).split(',').map((t) => t.trim()).toList(),
      description: cell(3),
      thumbnailUrl: _toThumbnailUrl(cell(4)),
      photosUrl: cell(5),
      sizeMb: int.tryParse(cell(6)),
      encoded: cell(7).toLowerCase() == 'true',
    );
  }

  // Accept either a proper thumbnail URL or a Drive view/share URL and
  // normalise it to the direct thumbnail endpoint.
  static String _toThumbnailUrl(String url) {
    if (url.isEmpty) return url;
    final match = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (match != null) {
      return 'https://drive.google.com/thumbnail?id=${match.group(1)}&sz=w400';
    }
    return url;
  }
}

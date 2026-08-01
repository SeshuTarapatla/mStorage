final _invalidFilenameChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final _trailingDotsOrSpaces = RegExp(r'[. ]+$');
final _repeatedSpaces = RegExp(r' {2,}');

/// Makes [name] safe to use as a Windows file or directory name.
///
/// Movie/episode titles routinely contain characters Windows forbids in
/// paths (e.g. the colon in "Avengers: Endgame"), which throws a
/// [FileSystemException] on `Directory.create`/`File` calls. Invalid
/// characters are replaced with a space rather than dropped outright, so
/// "Avengers: Endgame" reads as "Avengers Endgame" instead of the more
/// jarring "AvengersEndgame".
String sanitizeFilename(String name) {
  final sanitized = name
      .replaceAll(_invalidFilenameChars, ' ')
      .replaceAll(_repeatedSpaces, ' ')
      .trim()
      .replaceAll(_trailingDotsOrSpaces, '');
  return sanitized.isEmpty ? 'untitled' : sanitized;
}

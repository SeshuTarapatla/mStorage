class EncodeConfig {
  final String videoPath;
  final String title;
  final String date;
  final String time;
  final String? posterPath;
  final String? srtPath;
  final String outputDirectory;
  final String password;

  const EncodeConfig({
    required this.videoPath,
    required this.title,
    required this.date,
    required this.time,
    this.posterPath,
    this.srtPath,
    required this.outputDirectory,
    this.password = '',
  });
}

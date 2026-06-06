class DecodeConfig {
  final String videoPath;
  final String outputDirectory;
  final String password;

  const DecodeConfig({
    required this.videoPath,
    required this.outputDirectory,
    this.password = '',
  });
}

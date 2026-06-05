class AppSettings {
  final String password;
  final String outputDirectory;
  final bool preserveAspectRatio;
  final int maskDurationSeconds;

  const AppSettings({
    this.password = '',
    this.outputDirectory = '',
    this.preserveAspectRatio = true,
    this.maskDurationSeconds = 5,
  });

  AppSettings copyWith({
    String? password,
    String? outputDirectory,
    bool? preserveAspectRatio,
    int? maskDurationSeconds,
  }) {
    return AppSettings(
      password: password ?? this.password,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      preserveAspectRatio: preserveAspectRatio ?? this.preserveAspectRatio,
      maskDurationSeconds: maskDurationSeconds ?? this.maskDurationSeconds,
    );
  }
}

class AppSettings {
  final String password;
  final String encodeOutputDirectory;
  final String decodeOutputDirectory;
  final bool preserveAspectRatio;
  final int maskDurationSeconds;

  const AppSettings({
    this.password = '',
    this.encodeOutputDirectory = '',
    this.decodeOutputDirectory = '',
    this.preserveAspectRatio = true,
    this.maskDurationSeconds = 5,
  });

  AppSettings copyWith({
    String? password,
    String? encodeOutputDirectory,
    String? decodeOutputDirectory,
    bool? preserveAspectRatio,
    int? maskDurationSeconds,
  }) {
    return AppSettings(
      password: password ?? this.password,
      encodeOutputDirectory:
          encodeOutputDirectory ?? this.encodeOutputDirectory,
      decodeOutputDirectory:
          decodeOutputDirectory ?? this.decodeOutputDirectory,
      preserveAspectRatio: preserveAspectRatio ?? this.preserveAspectRatio,
      maskDurationSeconds: maskDurationSeconds ?? this.maskDurationSeconds,
    );
  }
}

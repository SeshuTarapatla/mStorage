class AppSettings {
  final String password;
  final String encodeOutputDirectory;
  final String decodeOutputDirectory;
  final bool preserveAspectRatio;
  final int maskDurationSeconds;
  final int syncplayPort;
  final String syncplayUsername;
  final String syncplayRoom;
  final int startupTab;

  const AppSettings({
    this.password = '',
    this.encodeOutputDirectory = '',
    this.decodeOutputDirectory = '',
    this.preserveAspectRatio = true,
    this.maskDurationSeconds = 5,
    this.syncplayPort = 8999,
    this.syncplayUsername = '',
    this.syncplayRoom = '',
    this.startupTab = 0,
  });

  AppSettings copyWith({
    String? password,
    String? encodeOutputDirectory,
    String? decodeOutputDirectory,
    bool? preserveAspectRatio,
    int? maskDurationSeconds,
    int? syncplayPort,
    String? syncplayUsername,
    String? syncplayRoom,
    int? startupTab,
  }) {
    return AppSettings(
      password: password ?? this.password,
      encodeOutputDirectory:
          encodeOutputDirectory ?? this.encodeOutputDirectory,
      decodeOutputDirectory:
          decodeOutputDirectory ?? this.decodeOutputDirectory,
      preserveAspectRatio: preserveAspectRatio ?? this.preserveAspectRatio,
      maskDurationSeconds: maskDurationSeconds ?? this.maskDurationSeconds,
      syncplayPort: syncplayPort ?? this.syncplayPort,
      syncplayUsername: syncplayUsername ?? this.syncplayUsername,
      syncplayRoom: syncplayRoom ?? this.syncplayRoom,
      startupTab: startupTab ?? this.startupTab,
    );
  }
}

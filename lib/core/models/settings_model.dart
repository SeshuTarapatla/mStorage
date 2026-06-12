class AppSettings {
  final String password;
  final String encodeOutputDirectory;
  final String decodeOutputDirectory;
  final String catalogDownloadDirectory;
  final bool preserveAspectRatio;
  final int maskDurationSeconds;
  final int syncplayPort;
  final String syncplayUsername;
  final String syncplayRoom;
  final String lastVideoPath;
  final List<int>? tabOrder;
  final bool deleteAfterDecode;
  final double playerVolume;

  const AppSettings({
    this.password = '',
    this.encodeOutputDirectory = '',
    this.decodeOutputDirectory = '',
    this.catalogDownloadDirectory = '',
    this.preserveAspectRatio = true,
    this.maskDurationSeconds = 5,
    this.syncplayPort = 8999,
    this.syncplayUsername = '',
    this.syncplayRoom = '',
    this.lastVideoPath = '',
    this.tabOrder,
    this.deleteAfterDecode = false,
    this.playerVolume = 100.0,
  });

  AppSettings copyWith({
    String? password,
    String? encodeOutputDirectory,
    String? decodeOutputDirectory,
    String? catalogDownloadDirectory,
    bool? preserveAspectRatio,
    int? maskDurationSeconds,
    int? syncplayPort,
    String? syncplayUsername,
    String? syncplayRoom,
    String? lastVideoPath,
    List<int>? tabOrder,
    bool? deleteAfterDecode,
    double? playerVolume,
  }) {
    return AppSettings(
      password: password ?? this.password,
      encodeOutputDirectory:
          encodeOutputDirectory ?? this.encodeOutputDirectory,
      decodeOutputDirectory:
          decodeOutputDirectory ?? this.decodeOutputDirectory,
      catalogDownloadDirectory:
          catalogDownloadDirectory ?? this.catalogDownloadDirectory,
      preserveAspectRatio: preserveAspectRatio ?? this.preserveAspectRatio,
      maskDurationSeconds: maskDurationSeconds ?? this.maskDurationSeconds,
      syncplayPort: syncplayPort ?? this.syncplayPort,
      syncplayUsername: syncplayUsername ?? this.syncplayUsername,
      syncplayRoom: syncplayRoom ?? this.syncplayRoom,
      lastVideoPath: lastVideoPath ?? this.lastVideoPath,
      tabOrder: tabOrder ?? this.tabOrder,
      deleteAfterDecode: deleteAfterDecode ?? this.deleteAfterDecode,
      playerVolume: playerVolume ?? this.playerVolume,
    );
  }
}

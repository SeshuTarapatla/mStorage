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
  final int startupTab;
  final String lastVideoPath;
  final List<int>? tabOrder;
  final bool deleteAfterDecode;
  final double playerVolume;
  final double windowX;
  final double windowY;
  final double windowWidth;
  final double windowHeight;
  final bool windowMaximized;

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
    this.startupTab = 0,
    this.lastVideoPath = '',
    this.tabOrder,
    this.deleteAfterDecode = false,
    this.playerVolume = 100.0,
    this.windowX = -1,
    this.windowY = -1,
    this.windowWidth = -1,
    this.windowHeight = -1,
    this.windowMaximized = false,
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
    int? startupTab,
    String? lastVideoPath,
    List<int>? tabOrder,
    bool? deleteAfterDecode,
    double? playerVolume,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
    bool? windowMaximized,
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
      startupTab: startupTab ?? this.startupTab,
      lastVideoPath: lastVideoPath ?? this.lastVideoPath,
      tabOrder: tabOrder ?? this.tabOrder,
      deleteAfterDecode: deleteAfterDecode ?? this.deleteAfterDecode,
      playerVolume: playerVolume ?? this.playerVolume,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      windowMaximized: windowMaximized ?? this.windowMaximized,
    );
  }
}

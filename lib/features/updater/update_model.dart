enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String assetUrl;
  final String assetName;
  final String? installerPath;

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.assetUrl,
    required this.assetName,
    this.installerPath,
  });

  UpdateInfo withInstallerPath(String path) => UpdateInfo(
        version: version,
        releaseNotes: releaseNotes,
        assetUrl: assetUrl,
        assetName: assetName,
        installerPath: path,
      );
}

class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double downloadProgress;
  final String? errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.downloadProgress = 0.0,
    this.errorMessage,
  });
}

import 'dart:async' show unawaited;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'update_model.dart';
import 'update_service.dart';

const _kDismissedDateKey = 'update_dismissed_date';

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

class UpdateNotifier extends Notifier<UpdateState> {
  final _service = UpdateService();

  @override
  UpdateState build() => const UpdateState();

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<bool> _isDismissedToday() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kDismissedDateKey) ?? '') == _today();
  }

  Future<void> dismissForToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedDateKey, _today());
    state = UpdateState(
      status: state.status,
      info: state.info,
      dismissedToday: true,
    );
  }

  Future<void> checkForUpdate() async {
    if (state.status == UpdateStatus.checking) return;
    state = const UpdateState(status: UpdateStatus.checking);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final info = await _service.checkForUpdate(packageInfo.version);
      if (info == null) {
        state = const UpdateState(status: UpdateStatus.upToDate);
      } else if (UpdateService.isNewer(info.version, packageInfo.version)) {
        if (info.assetUrl.isEmpty) throw Exception('No .exe asset found in release');
        final dismissed = await _isDismissedToday();
        state = UpdateState(
          status: UpdateStatus.available,
          info: info,
          dismissedToday: dismissed,
        );
      } else {
        // Same or older — store info so release notes are available in the UI.
        state = UpdateState(status: UpdateStatus.upToDate, info: info);
      }
    } catch (e) {
      state = UpdateState(
        status: UpdateStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> downloadUpdate() async {
    final info = state.info;
    if (info == null) return;
    state = UpdateState(status: UpdateStatus.downloading, info: info);

    try {
      final path = await _service.downloadUpdate(info, (progress) {
        state = UpdateState(
          status: UpdateStatus.downloading,
          info: info,
          downloadProgress: progress,
        );
      });
      state = UpdateState(
        status: UpdateStatus.readyToInstall,
        info: info.withInstallerPath(path),
      );
    } catch (e) {
      state = UpdateState(
        status: UpdateStatus.error,
        info: info,
        errorMessage: 'Download failed: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> launchInstaller() async {
    final path = state.info?.installerPath;
    if (path == null) return;
    await _service.launchInstaller(path);
    // Exit so the installer can overwrite the running executable.
    unawaited(windowManager.close());
  }

  void dismiss() => state = const UpdateState();
}

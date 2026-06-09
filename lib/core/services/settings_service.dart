import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';

String _mStorageBase() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  return p.join(home, 'Videos', 'mStorage');
}

class AppDirectories {
  static String get encoded => p.join(_mStorageBase(), 'Encoded');
  static String get decoded => p.join(_mStorageBase(), 'Decoded');
  static String get downloaded => p.join(_mStorageBase(), 'Downloaded');
}

const _kPassword = 'setting_password';
const _kEncodeOutputDir = 'setting_encode_output_dir';
const _kDecodeOutputDir = 'setting_decode_output_dir';
const _kCatalogDownloadDir = 'setting_catalog_download_dir';
const _kAspectRatio = 'setting_aspect_ratio';
const _kMaskDuration = 'setting_mask_duration';
const _kSyncplayPort = 'syncplay_port';
const _kSyncplayUsername = 'syncplay_username';
const _kSyncplayRoom = 'syncplay_room';
const _kStartupTab = 'startup_tab';
const _kLastVideoPath = 'last_video_path';
const _kTabOrder = 'tab_order';

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _prefs;

  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      password: _prefs.getString(_kPassword) ?? '',
      encodeOutputDirectory: _prefs.getString(_kEncodeOutputDir) ?? '',
      decodeOutputDirectory: _prefs.getString(_kDecodeOutputDir) ?? '',
      catalogDownloadDirectory: _prefs.getString(_kCatalogDownloadDir) ?? '',
      preserveAspectRatio: _prefs.getBool(_kAspectRatio) ?? true,
      maskDurationSeconds: _prefs.getInt(_kMaskDuration) ?? 5,
      syncplayPort: _prefs.getInt(_kSyncplayPort) ?? 8999,
      syncplayUsername: _prefs.getString(_kSyncplayUsername) ?? '',
      syncplayRoom: _prefs.getString(_kSyncplayRoom) ?? '',
      startupTab: _prefs.getInt(_kStartupTab) ?? 0,
      lastVideoPath: _prefs.getString(_kLastVideoPath) ?? '',
      tabOrder: _prefs.getString(_kTabOrder)
          ?.split(',')
          .map(int.parse)
          .toList(),
    );
  }

  Future<void> setPassword(String value) async {
    state = state.copyWith(password: value);
    await _prefs.setString(_kPassword, value);
  }

  Future<void> setEncodeOutputDirectory(String value) async {
    state = state.copyWith(encodeOutputDirectory: value);
    await _prefs.setString(_kEncodeOutputDir, value);
  }

  Future<void> setDecodeOutputDirectory(String value) async {
    state = state.copyWith(decodeOutputDirectory: value);
    await _prefs.setString(_kDecodeOutputDir, value);
  }

  Future<void> setCatalogDownloadDirectory(String value) async {
    state = state.copyWith(catalogDownloadDirectory: value);
    await _prefs.setString(_kCatalogDownloadDir, value);
  }

  Future<void> setPreserveAspectRatio(bool value) async {
    state = state.copyWith(preserveAspectRatio: value);
    await _prefs.setBool(_kAspectRatio, value);
  }

  Future<void> setMaskDuration(int value) async {
    state = state.copyWith(maskDurationSeconds: value);
    await _prefs.setInt(_kMaskDuration, value);
  }

  Future<void> setSyncplayPort(int value) async {
    state = state.copyWith(syncplayPort: value);
    await _prefs.setInt(_kSyncplayPort, value);
  }

  Future<void> setSyncplayUsername(String value) async {
    state = state.copyWith(syncplayUsername: value);
    await _prefs.setString(_kSyncplayUsername, value);
  }

  Future<void> setSyncplayRoom(String value) async {
    state = state.copyWith(syncplayRoom: value);
    await _prefs.setString(_kSyncplayRoom, value);
  }

  Future<void> setLastVideoPath(String value) async {
    state = state.copyWith(lastVideoPath: value);
    await _prefs.setString(_kLastVideoPath, value);
  }

  Future<void> setStartupTab(int value) async {
    state = state.copyWith(startupTab: value);
    await _prefs.setInt(_kStartupTab, value);
  }

  Future<void> setTabOrder(List<int> value) async {
    state = state.copyWith(tabOrder: value);
    await _prefs.setString(_kTabOrder, value.join(','));
  }

  Future<void> resetTabOrder() async {
    await _prefs.remove(_kTabOrder);
    state = AppSettings(
      password: state.password,
      encodeOutputDirectory: state.encodeOutputDirectory,
      decodeOutputDirectory: state.decodeOutputDirectory,
      catalogDownloadDirectory: state.catalogDownloadDirectory,
      preserveAspectRatio: state.preserveAspectRatio,
      maskDurationSeconds: state.maskDurationSeconds,
      syncplayPort: state.syncplayPort,
      syncplayUsername: state.syncplayUsername,
      syncplayRoom: state.syncplayRoom,
      startupTab: state.startupTab,
      lastVideoPath: state.lastVideoPath,
      tabOrder: null,
    );
  }

  Future<void> resetAll() async {
    await _prefs.clear();
    state = const AppSettings();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

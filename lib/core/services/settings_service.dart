import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';

const _kPassword = 'setting_password';
const _kOutputDir = 'setting_output_dir';
const _kAspectRatio = 'setting_aspect_ratio';
const _kMaskDuration = 'setting_mask_duration';

class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _prefs;

  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      password: _prefs.getString(_kPassword) ?? '',
      outputDirectory: _prefs.getString(_kOutputDir) ?? '',
      preserveAspectRatio: _prefs.getBool(_kAspectRatio) ?? true,
      maskDurationSeconds: _prefs.getInt(_kMaskDuration) ?? 5,
    );
  }

  Future<void> setPassword(String value) async {
    state = state.copyWith(password: value);
    await _prefs.setString(_kPassword, value);
  }

  Future<void> setOutputDirectory(String value) async {
    state = state.copyWith(outputDirectory: value);
    await _prefs.setString(_kOutputDir, value);
  }

  Future<void> setPreserveAspectRatio(bool value) async {
    state = state.copyWith(preserveAspectRatio: value);
    await _prefs.setBool(_kAspectRatio, value);
  }

  Future<void> setMaskDuration(int value) async {
    state = state.copyWith(maskDurationSeconds: value);
    await _prefs.setInt(_kMaskDuration, value);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

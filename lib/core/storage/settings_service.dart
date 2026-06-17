import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';

/// Persistent settings stored via SharedPreferences.
///
/// Ports the settings persistence from electron/services/settings.js
/// which managed a .env file. In Flutter, we use SharedPreferences
/// and sync with the AppConfig runtime values.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

class SettingsService {
  static const _keys = <String>[
    'ZJU_USERNAME',
    'ZJU_PASSWORD',
    'DEEPSEEK_API_KEY',
    'DEEPSEEK_MODEL',
    'DEEPSEEK_THINKING',
    'PTA_SESSION',
    'DINGTALK_WEBHOOK',
    'MATERIAL_DOWNLOAD_PATH',
    'VIDEO_OPENER',
    'STUDENT_GRADE',
    'STUDENT_MAJOR',
    'STUDENT_MINOR',
    'PERSONAL_TRAINING_PLAN_OCR',
    'OTHER_TRAINING_PLAN_OCR',
    'AUTO_REFRESH_ENABLED',
    'AUTO_REFRESH_INTERVAL',
    'MEMORY_RIGOR',
    'DEEPSEEK_OCR_API_KEY',
  ];

  /// Load all settings from SharedPreferences and sync to AppConfig.
  Future<Map<String, String?>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String?>{};
    for (final key in _keys) {
      final value = prefs.getString(key);
      result[key] = value;
      // Sync to runtime config
      AppConfig.set(key, value);
    }
    return result;
  }

  /// Save a single setting.
  Future<void> save(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    // Sync to runtime config
    AppConfig.set(key, value);
  }

  /// Save all settings at once. Writes to SharedPreferences AND .env file.
  Future<void> saveAll(Map<String, String> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, String?>{};
    for (final entry in settings.entries) {
      if (_keys.contains(entry.key)) {
        await prefs.setString(entry.key, entry.value);
        AppConfig.set(entry.key, entry.value);
        values[entry.key] = entry.value;
      }
    }
    // .env file is optional — fails silently on Android (read-only filesystem)
    try {
      await AppConfig.saveToEnvFile(values);
    } catch (_) {}
  }

  /// Clear all settings.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keys) {
      await prefs.remove(key);
      AppConfig.set(key, null);
    }
  }
}

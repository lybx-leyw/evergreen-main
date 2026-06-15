import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Application configuration loaded from environment, .env file, and settings.
///
/// Priority (highest to lowest):
/// 1. Platform environment variables (process env)
/// 2. .env file in working directory (writable by settings screen)
/// 3. SharedPreferences (set by settings screen)
///
/// The .env file enables direct editing and portability.
/// The Settings screen writes to both SharedPreferences and .env file.
class AppConfig {
  static String? _zjuUsername;
  static String? _zjuPassword;
  static String? _deepseekApiKey;
  static String? _deepseekModel;
  static String? _deepseekThinking;
  static String? _ptaSession;
  static String? _dingtalkWebhook;
  static String? _downloadPath;
  static String? _videoPlayerPath;
  static String? _chalaoshiScriptPath;

  static String? get zjuUsername => _zjuUsername;
  static String? get zjuPassword => _zjuPassword;
  static String? get deepseekApiKey => _deepseekApiKey;
  static String? get deepseekModel => _deepseekModel ?? 'deepseek-v4-flash';
  static String? get deepseekThinking => _deepseekThinking ?? 'enabled';
  static String? get ptaSession => _ptaSession;
  static String? get dingtalkWebhook => _dingtalkWebhook;
  static String? get downloadPath => _downloadPath;
  static String? get videoPlayerPath => _videoPlayerPath;
  static String? get chalaoshiScriptPath => _chalaoshiScriptPath;
  static String? _deepseekOcrApiKey;
  static String? get deepseekOcrApiKey => _deepseekOcrApiKey;

  static bool get hasZjuCredentials =>
      _zjuUsername != null &&
      _zjuUsername!.isNotEmpty &&
      _zjuPassword != null &&
      _zjuPassword!.isNotEmpty;

  static bool get hasDeepSeekApiKey =>
      _deepseekApiKey != null && _deepseekApiKey!.isNotEmpty;

  /// Path to .env file in the application directory.
  static String get _envFilePath {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      return p.join(exeDir, '.env');
    } catch (_) {
      return p.join(Directory.current.path, '.env');
    }
  }

  /// Initialize config: env vars → .env file → SharedPreferences.
  static Future<void> initialize() async {
    _loadFromEnv();
    await _loadFromEnvFile();
    await _loadFromPrefs();
  }

  static void _loadFromEnv() {
    try {
      _zjuUsername ??= Platform.environment['ZJU_USERNAME'];
      _zjuPassword ??= Platform.environment['ZJU_PASSWORD'];
      _deepseekApiKey ??= Platform.environment['DEEPSEEK_API_KEY'];
      _deepseekModel ??= Platform.environment['DEEPSEEK_MODEL'];
      _deepseekThinking ??= Platform.environment['DEEPSEEK_THINKING'];
      _ptaSession ??= Platform.environment['PTA_SESSION'];
      _ptaSession ??= Platform.environment['PTA_SESSION'];
      _dingtalkWebhook ??= Platform.environment['DINGTALK_WEBHOOK'];
      _downloadPath ??= Platform.environment['MATERIAL_DOWNLOAD_PATH'];
      _videoPlayerPath ??= Platform.environment['VIDEO_OPENER'];
    } catch (_) {}
  }

  static Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _zjuUsername ??= prefs.getString('ZJU_USERNAME');
      _zjuPassword ??= prefs.getString('ZJU_PASSWORD');
      _deepseekApiKey ??= prefs.getString('DEEPSEEK_API_KEY');
      _deepseekModel ??= prefs.getString('DEEPSEEK_MODEL');
      _deepseekThinking ??= prefs.getString('DEEPSEEK_THINKING');
      _ptaSession ??= prefs.getString('PTA_SESSION');
      _ptaSession ??= prefs.getString('PTA_SESSION');
      _dingtalkWebhook ??= prefs.getString('DINGTALK_WEBHOOK');
      _downloadPath ??= prefs.getString('MATERIAL_DOWNLOAD_PATH');
      _videoPlayerPath ??= prefs.getString('VIDEO_OPENER');
      _chalaoshiScriptPath ??= prefs.getString('CHALAOSHI_SCRIPT');
    } catch (_) {}
  }

  static Future<void> _loadFromEnvFile() async {
    try {
      final file = File(_envFilePath);
      if (!await file.exists()) return;

      final lines = await file.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final eqIndex = trimmed.indexOf('=');
        if (eqIndex <= 0) continue;

        final key = trimmed.substring(0, eqIndex).trim();
        String value = trimmed.substring(eqIndex + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }

        set(key, value);
      }
    } catch (_) {}
  }

  static Future<void> saveToEnvFile(Map<String, String?> values) async {
    try {
      final buf = StringBuffer();
      buf.writeln('# ZJU live better and better — 环境变量配置');
      buf.writeln('# 此文件由设置界面自动管理，也可手动编辑');
      buf.writeln('');

      _writeLine(buf, 'ZJU_USERNAME', values['ZJU_USERNAME'] ?? _zjuUsername);
      _writeLine(buf, 'ZJU_PASSWORD', values['ZJU_PASSWORD'] ?? _zjuPassword);
      buf.writeln();
      _writeLine(buf, 'DEEPSEEK_API_KEY', values['DEEPSEEK_API_KEY'] ?? _deepseekApiKey);
      _writeLine(buf, 'DEEPSEEK_MODEL', values['DEEPSEEK_MODEL'] ?? _deepseekModel);
      _writeLine(buf, 'DEEPSEEK_THINKING', values['DEEPSEEK_THINKING'] ?? _deepseekThinking);
      buf.writeln();
      _writeLine(buf, 'PTA_SESSION', values['PTA_SESSION'] ?? _ptaSession);
      _writeLine(buf, 'PTA_SESSION', values['PTA_SESSION'] ?? _ptaSession);
      buf.writeln();
      _writeLine(buf, 'DINGTALK_WEBHOOK', values['DINGTALK_WEBHOOK'] ?? _dingtalkWebhook);
      buf.writeln();
      _writeLine(buf, 'MATERIAL_DOWNLOAD_PATH', values['MATERIAL_DOWNLOAD_PATH'] ?? _downloadPath);
      _writeLine(buf, 'VIDEO_OPENER', values['VIDEO_OPENER'] ?? _videoPlayerPath);

      final file = File(_envFilePath);
      await file.writeAsString(buf.toString());
    } catch (_) {}
  }

  static void _writeLine(StringBuffer buf, String key, String? value) {
    if (value != null && value.isNotEmpty) {
      buf.writeln('$key=$value');
    } else {
      buf.writeln('# $key=');
    }
  }

  static void set(String key, String? value) {
    switch (key) {
      case 'ZJU_USERNAME':
        _zjuUsername = value ?? _zjuUsername;
      case 'ZJU_PASSWORD':
        _zjuPassword = value ?? _zjuPassword;
      case 'DEEPSEEK_API_KEY':
        _deepseekApiKey = value ?? _deepseekApiKey;
      case 'DEEPSEEK_MODEL':
        _deepseekModel = value ?? _deepseekModel;
      case 'DEEPSEEK_THINKING':
        _deepseekThinking = value ?? _deepseekThinking;
      case 'PTA_SESSION':
        _ptaSession = value ?? _ptaSession;
      case 'DINGTALK_WEBHOOK':
        _dingtalkWebhook = value ?? _dingtalkWebhook;
      case 'MATERIAL_DOWNLOAD_PATH':
        _downloadPath = value ?? _downloadPath;
      case 'VIDEO_OPENER':
        _videoPlayerPath = value ?? _videoPlayerPath;
      case 'DEEPSEEK_OCR_API_KEY':
        _deepseekOcrApiKey = value ?? _deepseekOcrApiKey;
    }
  }

  static String getDownloadDirectory() {
    if (_downloadPath != null && _downloadPath!.isNotEmpty) {
      return _downloadPath!;
    }
    try {
      if (Platform.isWindows) {
        return p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads');
      } else if (Platform.isMacOS) {
        return p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
      } else {
        return p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
      }
    } catch (_) {
      return '.';
    }
  }
}

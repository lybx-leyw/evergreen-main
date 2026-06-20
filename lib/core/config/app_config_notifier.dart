import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/log.dart';
import 'app_config_model.dart';
import 'app_config.dart' as legacy;

/// 管理 [AppConfigData] 生命周期的 Riverpod StateNotifier。
///
/// 优先级（高→低）：env vars → .env 文件 → SharedPreferences。
class AppConfigNotifier extends StateNotifier<AppConfigData> {
  final SharedPreferences _prefs;

  AppConfigNotifier(this._prefs) : super(const AppConfigData());

  /// 初始化：env → .env 文件 → SharedPreferences → 合并为 [AppConfigData]。
  ///
  /// 同步更新旧的 [AppConfig] 静态类，确保未迁移的消费者继续工作。
  Future<void> initialize() async {
    final values = <String, String>{};

    // 1. 系统环境变量（最高优先级）
    _loadFromEnv(values);

    // 2. .env 文件（填补环境变量空白）
    await _loadFromEnvFile(values);

    // 3. SharedPreferences（最低优先级）
    await _loadFromPrefs(values);

    state = AppConfigData(
      zjuUsername: values['ZJU_USERNAME'],
      zjuPassword: values['ZJU_PASSWORD'],
      deepseekApiKey: values['DEEPSEEK_API_KEY'],
      deepseekModel: values['DEEPSEEK_MODEL'] ?? 'deepseek-v4-flash',
      deepseekThinking: values['DEEPSEEK_THINKING'] != 'disabled',
      ptaSession: values['PTA_SESSION'],
      dingtalkWebhook: values['DINGTALK_WEBHOOK'],
      downloadPath: values['MATERIAL_DOWNLOAD_PATH'],
      videoPlayerPath: values['VIDEO_OPENER'],
      translateLangOut: values['TRANSLATE_LANG_OUT'] ?? 'zh',
      translateLangIn: values['TRANSLATE_LANG_IN'] ?? 'en',
      pythonExe: values['PYTHON_EXE'],
    );

    // 同步旧版静态类——兼容未迁移的消费者
    _syncToLegacy(values);

    Log().info('AppConfig initialized', data: {'state': state.toString()});
  }

  /// 批量更新配置（从设置界面调用）。
  Future<void> saveAll(Map<String, String?> updates) async {
    state = _applyUpdates(state, updates);

    // 持久化
    await _persistToPrefs(updates);
    await _persistToEnvFile(state);

    // 同步旧版
    _syncToLegacy(_configToMap(state));

    Log().info('AppConfig saved', data: {'state': state.toString()});
  }

  /// 单项更新。
  void set(String key, String? value) {
    state = _applyUpdates(state, {key: value});
    _persistToPrefs({key: value});
    _syncToLegacy(_configToMap(state));
  }

  // ── 私有：数据加载 ──────────────────────────────────────────

  void _loadFromEnv(Map<String, String> out) {
    try {
      _pickEnv(out, 'ZJU_USERNAME');
      _pickEnv(out, 'ZJU_PASSWORD');
      _pickEnv(out, 'DEEPSEEK_API_KEY');
      _pickEnv(out, 'DEEPSEEK_MODEL');
      _pickEnv(out, 'DEEPSEEK_THINKING');
      _pickEnv(out, 'PTA_SESSION');
      _pickEnv(out, 'PTA_SESSION');
      _pickEnv(out, 'DINGTALK_WEBHOOK');
      _pickEnv(out, 'MATERIAL_DOWNLOAD_PATH');
      _pickEnv(out, 'VIDEO_OPENER');
      _pickEnv(out, 'TRANSLATE_LANG_OUT');
      _pickEnv(out, 'TRANSLATE_LANG_IN');
      _pickEnv(out, 'PYTHON_EXE');
    } catch (_) {}
  }

  void _pickEnv(Map<String, String> out, String key) {
    final v = Platform.environment[key];
    if (v != null) out[key] = v;
  }

  Future<void> _loadFromEnvFile(Map<String, String> out) async {
    try {
      final file = File(await _envFilePath);
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

        out.putIfAbsent(key, () => value);
      }
    } catch (_) {}
  }

  Future<void> _loadFromPrefs(Map<String, String> out) async {
    try {
      _pickPref(out, 'ZJU_USERNAME');
      _pickPref(out, 'ZJU_PASSWORD');
      _pickPref(out, 'DEEPSEEK_API_KEY');
      _pickPref(out, 'DEEPSEEK_MODEL');
      _pickPref(out, 'DEEPSEEK_THINKING');
      _pickPref(out, 'PTA_SESSION');
      _pickPref(out, 'PTA_SESSION');
      _pickPref(out, 'DINGTALK_WEBHOOK');
      _pickPref(out, 'MATERIAL_DOWNLOAD_PATH');
      _pickPref(out, 'VIDEO_OPENER');
      _pickPref(out, 'TRANSLATE_LANG_OUT');
      _pickPref(out, 'TRANSLATE_LANG_IN');
      _pickPref(out, 'PYTHON_EXE');
    } catch (_) {}
  }

  void _pickPref(Map<String, String> out, String key) {
    final v = _prefs.getString(key);
    if (v != null) out.putIfAbsent(key, () => v);
  }

  // ── 私有：持久化 ──────────────────────────────────────────

  Future<void> _persistToPrefs(Map<String, String?> updates) async {
    for (final entry in updates.entries) {
      if (entry.value == null) {
        await _prefs.remove(entry.key);
      } else {
        await _prefs.setString(entry.key, entry.value!);
      }
    }
  }

  Future<void> _persistToEnvFile(AppConfigData config) async {
    try {
      final buf = StringBuffer();
      buf.writeln('# ZJU live better and better — 环境变量配置');
      buf.writeln('# 此文件由设置界面自动管理，也可手动编辑');
      buf.writeln('');

      _w(buf, 'ZJU_USERNAME', config.zjuUsername);
      _w(buf, 'ZJU_PASSWORD', config.zjuPassword);
      buf.writeln();
      _w(buf, 'DEEPSEEK_API_KEY', config.deepseekApiKey);
      _w(buf, 'DEEPSEEK_MODEL', config.deepseekModel);
      _w(buf, 'DEEPSEEK_THINKING',
          config.deepseekThinking ? 'enabled' : 'disabled');
      buf.writeln();
      _w(buf, 'PTA_SESSION', config.ptaSession);
      buf.writeln();
      _w(buf, 'DINGTALK_WEBHOOK', config.dingtalkWebhook);
      buf.writeln();
      _w(buf, 'MATERIAL_DOWNLOAD_PATH', config.downloadPath);
      _w(buf, 'VIDEO_OPENER', config.videoPlayerPath);
      buf.writeln();
      _w(buf, 'TRANSLATE_LANG_OUT', config.translateLangOut);
      _w(buf, 'TRANSLATE_LANG_IN', config.translateLangIn);
      _w(buf, 'PYTHON_EXE', config.pythonExe);

      final file = File(await _envFilePath);
      await file.writeAsString(buf.toString());
    } catch (_) {}
  }

  void _w(StringBuffer buf, String key, String? value) {
    if (value != null && value.isNotEmpty) {
      buf.writeln('$key=$value');
    } else {
      buf.writeln('# $key=');
    }
  }

  /// 稳定的 .env 文件路径——使用应用支持目录。
  Future<String> get _envFilePath async {
    try {
      final appDir = await getApplicationSupportDirectory();
      return p.join(appDir.path, '.env');
    } catch (_) {
      return p.join(Directory.current.path, '.env');
    }
  }

  // ── 私有：同步旧版 ──────────────────────────────────────────

  void _syncToLegacy(Map<String, String> values) {
    for (final entry in values.entries) {
      legacy.AppConfig.set(entry.key, entry.value);
    }
  }

  Map<String, String> _configToMap(AppConfigData c) => {
        'ZJU_USERNAME': c.zjuUsername ?? '',
        'ZJU_PASSWORD': c.zjuPassword ?? '',
        'DEEPSEEK_API_KEY': c.deepseekApiKey ?? '',
        'DEEPSEEK_MODEL': c.deepseekModel,
        'DEEPSEEK_THINKING': c.deepseekThinking ? 'enabled' : 'disabled',
        'PTA_SESSION': c.ptaSession ?? '',
        'DINGTALK_WEBHOOK': c.dingtalkWebhook ?? '',
        'MATERIAL_DOWNLOAD_PATH': c.downloadPath ?? '',
        'VIDEO_OPENER': c.videoPlayerPath ?? '',
        'TRANSLATE_LANG_OUT': c.translateLangOut,
        'TRANSLATE_LANG_IN': c.translateLangIn,
        'PYTHON_EXE': c.pythonExe ?? '',
      };

  AppConfigData _applyUpdates(
      AppConfigData current, Map<String, String?> updates) {
    return AppConfigData(
      zjuUsername:
          updates.containsKey('ZJU_USERNAME') ? updates['ZJU_USERNAME'] : current.zjuUsername,
      zjuPassword:
          updates.containsKey('ZJU_PASSWORD') ? updates['ZJU_PASSWORD'] : current.zjuPassword,
      deepseekApiKey: updates.containsKey('DEEPSEEK_API_KEY')
          ? updates['DEEPSEEK_API_KEY']
          : current.deepseekApiKey,
      deepseekModel: updates.containsKey('DEEPSEEK_MODEL')
          ? (updates['DEEPSEEK_MODEL'] ?? current.deepseekModel)
          : current.deepseekModel,
      deepseekThinking: updates.containsKey('DEEPSEEK_THINKING')
          ? updates['DEEPSEEK_THINKING'] != 'disabled'
          : current.deepseekThinking,
      ptaSession: updates.containsKey('PTA_SESSION')
          ? updates['PTA_SESSION']
          : current.ptaSession,
      dingtalkWebhook: updates.containsKey('DINGTALK_WEBHOOK')
          ? updates['DINGTALK_WEBHOOK']
          : current.dingtalkWebhook,
      downloadPath: updates.containsKey('MATERIAL_DOWNLOAD_PATH')
          ? updates['MATERIAL_DOWNLOAD_PATH']
          : current.downloadPath,
      videoPlayerPath: updates.containsKey('VIDEO_OPENER')
          ? updates['VIDEO_OPENER']
          : current.videoPlayerPath,
      translateLangOut: updates.containsKey('TRANSLATE_LANG_OUT')
          ? (updates['TRANSLATE_LANG_OUT'] ?? current.translateLangOut)
          : current.translateLangOut,
      translateLangIn: updates.containsKey('TRANSLATE_LANG_IN')
          ? (updates['TRANSLATE_LANG_IN'] ?? current.translateLangIn)
          : current.translateLangIn,
      pythonExe: updates.containsKey('PYTHON_EXE')
          ? updates['PYTHON_EXE']
          : current.pythonExe,
    );
  }
}

/// 全局 [AppConfigData] Provider。
///
/// 由 `main()` 通过 `ProviderScope.overrides` 注入预初始化的 notifier。
final appConfigProvider =
    StateNotifierProvider<AppConfigNotifier, AppConfigData>((ref) {
  throw UnimplementedError(
      'Use ProviderScope overrides in main() to inject AppConfigNotifier');
});

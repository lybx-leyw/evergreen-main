/// 配置运行期热注册 —— 复用启动扫描 `_loadPlugins` 同一份 config.json 契约。
///
/// 设计器/爬虫生成 config/config.json 后，需要把配置项立即注册进
/// [ConfigHttpServer]，否则设置面板看不到、凭证不会自动写入 SharedPreferences。
///
/// 本文件把"读取 config/config.json → registerSetting + 写入默认值"抽成可复用函数：
/// - [registerConfigFromManifest]：运行期定向热注册用（插件目录级别）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_http_server.dart';

/// 注册结果摘要。
class ConfigRegisterSummary {
  final List<String> registered;
  final List<String> savedDefaults;

  const ConfigRegisterSummary({
    required this.registered,
    required this.savedDefaults,
  });

  int get count => registered.length;
}

/// 从某个插件的 `config/config.json` 注册其声明的全部设置项。
///
/// [configServer] ConfigHttpServer 实例（用于 registerSetting）。
/// [pluginDir] 插件根目录（含 `config/config.json`）。
/// [saveDefaults] 是否将 `default` 值写入 SharedPreferences（仅未设置过的 key）。
///
/// 返回注册摘要（manifest 缺失/非法则空列表，绝不抛）。
ConfigRegisterSummary registerConfigFromManifest({
  required ConfigHttpServer configServer,
  required String pluginDir,
}) {
  final configFile = File(p.join(pluginDir, 'config', 'config.json'));
  if (!configFile.existsSync()) return ConfigRegisterSummary(registered: [], savedDefaults: []);

  final registered = <String>[];
  final savedDefaults = <String>[];

  try {
    final json = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final settingsList = (json['settings'] as List<dynamic>?) ?? [];

    for (final item in settingsList) {
      if (item is! Map<String, dynamic>) continue;
      final key = item['key'] as String?;
      final label = item['label'] as String?;
      if (key == null || key.isEmpty) continue;

      // ① 注册到 ConfigHttpServer（动态设置表）
      configServer.registerSetting(
        key,
        label ?? key, // fallback to key as label
      );
      registered.add(key);

      // ② 若有 defaultValue，标记可自动保存（由调用方通过 SharedPreferences 写入）
      final defaultValue = item['default'] as String?;
      if (defaultValue != null && defaultValue.isNotEmpty) {
        savedDefaults.add(key);
      }
    }

    stderr.writeln('[registerConfig] ✅ ${p.basename(pluginDir)}: '
        'registered ${registered.length} settings, '
        '${savedDefaults.length} with defaults');
  } catch (e) {
    stderr.writeln('[registerConfig] ❌ ${p.basename(pluginDir)}: $e');
  }

  return ConfigRegisterSummary(
    registered: registered,
    savedDefaults: savedDefaults,
  );
}

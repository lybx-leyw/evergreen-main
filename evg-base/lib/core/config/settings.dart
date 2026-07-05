/// 设置模块——声明、读写、持久化。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `SettingType` | 设置项类型（string / bool_ / path / option） |
/// | `SettingOption` | 下拉选项 |
/// | `SettingDecl` | 设置项声明 |
/// | `initSettings(prefs, {pluginDirs})` | 扫描插件目录，将默认值写入 SP |
/// | `getSetting(prefs, key)` | 读值，回退声明默认值 |
/// | `setSetting(prefs, key, value)` | 写值到 SP |
/// | `getAllSettings(prefs)` | 返回全部 (SettingDecl, 当前值) |
/// | `exportConfig(prefs, {extraKeys})` | 导出 .evgconfig 格式 |
/// | `importConfig(prefs, config)` | 导入 .evgconfig 格式 |
library settings;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'exceptions.dart';
import 'permissions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 值类型
// ═══════════════════════════════════════════════════════════════════════════

/// 设置项类型。
enum SettingType { string, bool_, path, option }

/// 下拉选项。
class SettingOption {
  final String value;
  final String label;
  const SettingOption({required this.value, required this.label});
}

/// 一项设置声明。
class SettingDecl {
  final String key;
  final String label;
  final SettingType type;
  final String? defaultValue;
  final bool isSecure;
  final List<SettingOption>? options;
  final String? hint;

  const SettingDecl({
    required this.key,
    required this.label,
    this.type = SettingType.string,
    this.defaultValue,
    this.isSecure = false,
    this.options,
    this.hint,
  });

  const SettingDecl.string({
    required this.key,
    required this.label,
    this.defaultValue,
    this.isSecure = false,
    this.hint,
  })  : type = SettingType.string,
        options = null;

  const SettingDecl.bool_({
    required this.key,
    required this.label,
    this.defaultValue = 'false',
    this.hint,
  })  : type = SettingType.bool_,
        isSecure = false,
        options = null;

  const SettingDecl.path({
    required this.key,
    required this.label,
    this.defaultValue,
    this.hint,
  })  : type = SettingType.path,
        isSecure = false,
        options = null;

  const SettingDecl.option({
    required this.key,
    required this.label,
    required List<SettingOption> options,
    this.defaultValue,
    this.hint,
  })  : type = SettingType.option,
        isSecure = false,
        options = options;
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部——解析 & 声明加载
// ═══════════════════════════════════════════════════════════════════════════

Map<String, SettingDecl> _decls = {};

SettingDecl _parseSetting(Map<String, dynamic> m) {
  final key = m['key'] as String;
  final label = m['label'] as String;
  final type = m['type'] as String? ?? 'string';
  final isSecure = m['isSecure'] as bool? ?? false;
  final defaultValue = m['default'] as String?;
  final hint = m['hint'] as String?;

  switch (type) {
    case 'bool':
      return SettingDecl.bool_(
        key: key, label: label, defaultValue: defaultValue ?? 'false', hint: hint,
      );
    case 'path':
      return SettingDecl.path(
        key: key, label: label, defaultValue: defaultValue, hint: hint,
      );
    case 'option':
      final optionsRaw = m['options'] as List<dynamic>? ?? [];
      final options = optionsRaw.map((o) {
        final om = o as Map<String, dynamic>;
        return SettingOption(value: om['value'] as String, label: om['label'] as String);
      }).toList();
      return SettingDecl.option(
        key: key, label: label, options: options, defaultValue: defaultValue, hint: hint,
      );
    default:
      return SettingDecl.string(
        key: key, label: label, defaultValue: defaultValue, isSecure: isSecure, hint: hint,
      );
  }
}

Map<String, SettingDecl> _loadPlugins(List<String> dirs) {
  final decls = <String, SettingDecl>{};
  for (final dir in dirs) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    // 目录本身可能就是一个插件（config.json 直接在目录下）
    _tryLoad(d, decls);
    // 子目录各是一个插件
    for (final entity in d.listSync()) {
      if (entity is Directory) _tryLoad(entity, decls);
    }
  }
  return decls;
}

void _tryLoad(Directory dir, Map<String, SettingDecl> decls) {
  // 1) 尝试 config.json（根目录旧格式，兼容）
  var configFile = File('${dir.path}${Platform.pathSeparator}config.json');
  // 2) 尝试 config/config.json（插件规范格式）
  if (!configFile.existsSync()) {
    configFile = File('${dir.path}${Platform.pathSeparator}config${Platform.pathSeparator}config.json');
  }
  if (!configFile.existsSync()) return;
  try {
    final json = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final settingsList = json['settings'] as List<dynamic>? ?? [];
    for (final item in settingsList) {
      final sd = _parseSetting(item as Map<String, dynamic>);
      decls[sd.key] = sd;
    }

    // 自动解析 permissions 字段并注册
    final permissionsList = json['permissions'] as List<dynamic>?;
    if (permissionsList != null && permissionsList.isNotEmpty) {
      final pluginId = json['id'] as String? ?? dir.path.split(Platform.pathSeparator).last;
      final perms = <PermissionDecl>[];
      for (final p in permissionsList) {
        final pm = p as Map<String, dynamic>;
        perms.add(PermissionDecl(
          key: pm['key'] as String,
          label: pm['label'] as String? ?? (pm['key'] as String),
          description: pm['description'] as String? ?? '',
          defaultGranted: pm['default'] as bool? ?? true,
        ));
      }
      registerPermissions(pluginId, perms);
    }
  } catch (e) {
    stderr.writeln('[Config] ⚠ 解析失败: ${configFile.path} — $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 公开 API
// ═══════════════════════════════════════════════════════════════════════════

/// 初始化设置——扫描插件目录，将默认值写入 SharedPreferences。
///
/// 应在 `main()` 中调用一次。
Future<void> initSettings(
  SharedPreferences prefs, {
  List<String> pluginDirs = const [],
}) async {
  _decls = {};
  for (final dir in pluginDirs) {
    _decls.addAll(_loadPlugins([dir]));
  }
  for (final d in _decls.values) {
    if (d.defaultValue != null && d.defaultValue!.isNotEmpty) {
      if (!prefs.containsKey(d.key)) {
        await prefs.setString(d.key, d.defaultValue!);
      }
    }
  }
}

/// 读设置值——回退声明默认值。
String getSetting(SharedPreferences prefs, String key) {
  final v = prefs.getString(key);
  if (v != null && v.isNotEmpty) return v;
  return _decls[key]?.defaultValue ?? '';
}

/// 写设置值到 SharedPreferences。
///
/// 写入前校验值类型：bool_ 必须是 "true"/"false"，option 必须在选项列表中。
Future<void> setSetting(SharedPreferences prefs, String key, String value) async {
  final decl = _decls[key];
  if (decl != null && value.isNotEmpty) {
    switch (decl.type) {
      case SettingType.bool_:
        if (value != 'true' && value != 'false') {
          throw ConfigValidationException(
            key: key, value: value, reason: 'bool_ 类型必须是 "true" 或 "false"',
          );
        }
      case SettingType.option:
        if (decl.options != null && !decl.options!.any((o) => o.value == value)) {
          throw ConfigValidationException(
            key: key, value: value, reason: '值不在选项列表 [${decl.options!.map((o) => o.value).join(', ')}] 中',
          );
        }
      case SettingType.string:
      case SettingType.path:
        break; // 无额外校验
    }
  }

  if (value.isEmpty) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, value);
  }
}

/// 全部设置信息——声明 + 当前值，供设置界面渲染。
List<({SettingDecl decl, String value})> getAllSettings(SharedPreferences prefs) {
  return _decls.values.map((d) {
    final v = prefs.getString(d.key) ?? d.defaultValue ?? '';
    return (decl: d, value: v);
  }).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
// 导出 / 导入
// ═══════════════════════════════════════════════════════════════════════════

/// 导出全部配置为 `.evgconfig` 格式。
///
/// 返回的 Map 可直接 `jsonEncode` 写入 `.evgconfig` 文件。
/// [aiMemory] 可选，用于导出 AI 记忆数据（由 Agent 模块提供）。
/// [extraKeys] 可选，用于导出 `perm.*` 等非设置项 SP 键。
Future<Map<String, dynamic>> exportConfig(
  SharedPreferences prefs, {
  Map<String, dynamic>? aiMemory,
  List<String> extraKeys = const [],
}) async {
  final result = <String, dynamic>{
    'format': 'evgconfig',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'settings': <String, dynamic>{},
  };

  // 全部已知设置项
  for (final d in _decls.values) {
    final v = prefs.getString(d.key) ?? d.defaultValue ?? '';
    if (v.isNotEmpty) {
      result['settings'][d.key] = v;
    }
  }

  // 插件源
  const sourcesKey = '_plugin_sources';
  final sourcesRaw = prefs.getString(sourcesKey);
  if (sourcesRaw != null && sourcesRaw.isNotEmpty) {
    try {
      result['sources'] = jsonDecode(sourcesRaw);
    } catch (e) {
      stderr.writeln('[Config] ⚠ 导出源数据解析失败: $e');
    }
  }

  // AI 记忆（专用参数）
  if (aiMemory != null && aiMemory.isNotEmpty) {
    result['aiMemory'] = aiMemory;
  }

  // 额外 key（perm.* 等）
  if (extraKeys.isNotEmpty) {
    final extra = <String, dynamic>{};
    for (final k in extraKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) extra[k] = v;
    }
    if (extra.isNotEmpty) result['extra'] = extra;
  }

  return result;
}

/// 从 `.evgconfig` 格式导入配置。
///
/// 仅导入 settings 中已声明的键（安全过滤），不会覆盖无关 SP 数据。
/// 返回 `aiMemory` 数据供 Agent 模块自行导入（Config 不直接操作 MemoryStore）。
Future<Map<String, dynamic>?> importConfig(
  SharedPreferences prefs,
  Map<String, dynamic> config,
) async {
  final settings = config['settings'] as Map<String, dynamic>?;
  if (settings != null) {
    for (final entry in settings.entries) {
      // 仅导入已声明的设置项，忽略未知 key
      if (!_decls.containsKey(entry.key)) continue;
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }
  }

  // 插件源
  final sources = config['sources'];
  if (sources != null) {
    await prefs.setString('_plugin_sources', jsonEncode(sources));
  }

  // 额外数据（权限等）
  final extra = config['extra'] as Map<String, dynamic>?;
  if (extra != null) {
    for (final entry in extra.entries) {
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        await prefs.setString(entry.key, entry.value as String);
      }
    }
  }

  // 返回 AI 记忆数据供调用方自行导入
  return config['aiMemory'] as Map<String, dynamic>?;
}


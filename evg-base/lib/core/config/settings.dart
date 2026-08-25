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
/// | `getSettingSources()` | 返回全部已声明设置项的来源插件 id（按插件分组用） |
/// | `exportConfig(prefs, {aiMemory, extraKeys, dynamicKeys, includePermissions, appPrefs, includeSecure})` | 导出 .evgconfig v2 格式 |
/// | `importConfig(prefs, config, {allowedDynamicKeys, allowedAppPrefs, overwrite, allowSecure, onChanged})` | 导入 .evgconfig v2（含 v1 兼容） |
library settings;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'exceptions.dart';
import 'permissions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// .evgconfig 格式版本
// ═══════════════════════════════════════════════════════════════════════════

/// 当前 .evgconfig 导出格式版本。
///
/// v1：`{format, version:1, exportedAt, settings, sources?, aiMemory?, extra?}`
/// v2：v1 + 三个**可选新增段** `dynamicSettings` / `permissions` / `appPrefs`，
///     以及 isSecure 默认跳过、导入端 version 校验与白名单过滤。
///     旧导入器可忽略新段（向后兼容）；v1 文件可被 v2 导入器直接读取。
const int kEvgConfigVersion = 2;

/// 支持的导入最低版本（v1 向后兼容）。
const int kEvgConfigMinVersion = 1;

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

  /// 可选建议值（string/path 类型的快捷填充项，如常用模型 id）。
  /// 仅作为 UI 提示，不参与 [setSetting] 的写入校验——保证可自由填写任意值。
  final List<SettingOption>? suggestions;

  const SettingDecl({
    required this.key,
    required this.label,
    this.type = SettingType.string,
    this.defaultValue,
    this.isSecure = false,
    this.options,
    this.hint,
    this.suggestions,
  });

  const SettingDecl.string({
    required this.key,
    required this.label,
    this.defaultValue,
    this.isSecure = false,
    this.hint,
    this.suggestions,
  })  : type = SettingType.string,
        options = null;

  const SettingDecl.bool_({
    required this.key,
    required this.label,
    this.defaultValue = 'false',
    this.hint,
  })  : type = SettingType.bool_,
        isSecure = false,
        options = null,
        suggestions = null;

  const SettingDecl.path({
    required this.key,
    required this.label,
    this.defaultValue,
    this.hint,
  })  : type = SettingType.path,
        isSecure = false,
        options = null,
        suggestions = null;

  const SettingDecl.option({
    required this.key,
    required this.label,
    required List<SettingOption> options,
    this.defaultValue,
    this.hint,
  })  : type = SettingType.option,
        isSecure = false,
        options = options,
        suggestions = null;
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部——解析 & 声明加载
// ═══════════════════════════════════════════════════════════════════════════

Map<String, SettingDecl> _decls = {};

/// 已声明设置项的来源映射：key → 来源插件 id（`builtins` / 插件目录名 / config.json `id` 字段）。
///
/// 供导出按插件分组、同步中心「配置子集按插件勾选」与 UI 分组展示使用。
final Map<String, String> _declSources = {};

/// 解析建议值列表：兼容两种写法——
/// 1) 纯字符串 `["deepseek-chat", "gpt-4o"]`
/// 2) 对象 `[{"value": "...", "label": "..."}]`
List<SettingOption>? _parseSuggestions(Map<String, dynamic> m) {
  final raw = m['suggestions'] as List<dynamic>?;
  if (raw == null || raw.isEmpty) return null;
  final out = <SettingOption>[];
  for (final item in raw) {
    if (item is String) {
      out.add(SettingOption(value: item, label: item));
    } else if (item is Map<String, dynamic>) {
      out.add(SettingOption(
        value: item['value'] as String,
        label: item['label'] as String? ?? item['value'] as String,
      ));
    }
  }
  return out.isEmpty ? null : out;
}

SettingDecl _parseSetting(Map<String, dynamic> m) {
  final key = m['key'] as String;
  final label = m['label'] as String;
  final type = m['type'] as String? ?? 'string';
  final isSecure = m['isSecure'] as bool? ?? false;
  final defaultValue = m['default'] as String?;
  final hint = m['hint'] as String?;
  final suggestions = _parseSuggestions(m);

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
        suggestions: suggestions,
      );
  }
}

Map<String, SettingDecl> _loadPlugins(List<String> dirs) {
  final decls = <String, SettingDecl>{};
  stderr.writeln('[Config] _loadPlugins 开始，扫描根目录: $dirs');
  for (final dir in dirs) {
    final d = Directory(dir);
    stderr.writeln('[Config]   扫描根: ${d.path} (exists=${d.existsSync()})');
    if (!d.existsSync()) continue;
    // 目录本身可能就是一个插件（config.json 直接在目录下）
    _tryLoad(d, decls);
    // 子目录各是一个插件
    final children = d.listSync();
    stderr.writeln('[Config]   子目录数: ${children.length}');
    for (final entity in children) {
      if (entity is Directory) {
        final hasZju = entity.path.contains('zdbk');
        if (hasZju) {
          stderr.writeln('[Config-ZJU] 🔍 发现 zdbk 目录: ${entity.path}');
        }
        _tryLoad(entity, decls);
      }
    }
  }
  stderr.writeln('[Config] _loadPlugins 完成，共注册 ${decls.length} 个设置项: ${decls.keys.toList()}');
  // 专项检查 ZJU key
  stderr.writeln('[Config-ZJU] ZJU_USERNAME 已注册? ${decls.containsKey("ZJU_USERNAME")}');
  stderr.writeln('[Config-ZJU] ZJU_PASSWORD 已注册? ${decls.containsKey("ZJU_PASSWORD")}');
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
    final pluginId = json['id'] as String? ?? dir.path.split(Platform.pathSeparator).last;
    final keys = <String>[];
    for (final item in settingsList) {
      final sd = _parseSetting(item as Map<String, dynamic>);
      decls[sd.key] = sd;
      _declSources[sd.key] = pluginId;
      keys.add(sd.key);
    }
    // 诊断日志：帮助追踪 Android 上 config.json 扫描是否完整
    stderr.writeln('[Config] ✓ ${configFile.path} → ${keys.length} 设置项: $keys');

    // 自动解析 permissions 字段并注册
    final permissionsList = json['permissions'] as List<dynamic>?;
    if (permissionsList != null && permissionsList.isNotEmpty) {
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
  _declSources.clear();
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

/// 全部已声明设置项的来源插件 id（key → `builtins` / 插件目录名 / config.json `id`）。
///
/// 供同步中心「配置子集按插件勾选」、设置界面分组展示与导出分组使用。
/// 动态注册项（ConfigHttpServer）不在其中，请用 `ConfigHttpServer.dynamicSettingKeys`。
Map<String, String> getSettingSources() => Map.unmodifiable(_declSources);

// ═══════════════════════════════════════════════════════════════════════════
// 导出 / 导入
// ═══════════════════════════════════════════════════════════════════════════

/// 导出配置为 `.evgconfig` v2 格式。
///
/// 返回的 Map 可直接 `jsonEncode` 写入 `.evgconfig` 文件。
///
/// v2 相对 v1 的扩展（全部可选段，旧导入器可忽略）：
/// - [dynamicKeys]：动态注册设置项 key 列表（来源 `ConfigHttpServer.dynamicSettingKeys`），
///   导出为 `dynamicSettings` 段——修复 O1「动态项 _dynamicSettings 私有无法导出」。
/// - [includePermissions]：导出 `permissions` 段（`perm.*` 按 **bool** 正确类型读写），
///   修复 O1「权限导出类型错误（getString 读 bool 键）」。
/// - [appPrefs]：未声明应用偏好白名单（key → 忽略值，仅 key 有意义），导出为 `appPrefs` 段。
/// - [includeSecure]：默认 `false` 跳过 `isSecure` 声明项的明文值（防 API Key 泄漏）；
///   显式 `true` 才包含明文。
///
/// [aiMemory] 可选，用于导出 AI 记忆数据（由 Agent 模块提供）。
/// [extraKeys] 保留 v1 兼容（非设置项 SP 键；`perm.*` 请改用 [includePermissions]）。
Future<Map<String, dynamic>> exportConfig(
  SharedPreferences prefs, {
  Map<String, dynamic>? aiMemory,
  List<String> extraKeys = const [],
  List<String> dynamicKeys = const [],
  bool includePermissions = false,
  Map<String, String>? appPrefs,
  bool includeSecure = false,
}) async {
  final result = <String, dynamic>{
    'format': 'evgconfig',
    'version': kEvgConfigVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'settings': <String, dynamic>{},
  };

  // 全部已知设置项（isSecure 默认跳过，防明文泄漏）
  for (final d in _decls.values) {
    if (d.isSecure && !includeSecure) continue;
    final v = prefs.getString(d.key) ?? d.defaultValue ?? '';
    if (v.isNotEmpty) {
      result['settings'][d.key] = v;
    }
  }

  // 动态注册设置项（v2 新增段）
  if (dynamicKeys.isNotEmpty) {
    final dyn = <String, dynamic>{};
    for (final k in dynamicKeys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) dyn[k] = v;
    }
    if (dyn.isNotEmpty) result['dynamicSettings'] = dyn;
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

  // 权限（v2 新增段，bool 正确类型）
  if (includePermissions) {
    final perms = getAllPermissions(prefs);
    if (perms.isNotEmpty) result['permissions'] = perms;
  }

  // 未声明应用偏好（v2 新增段，调用方白名单）
  if (appPrefs != null && appPrefs.isNotEmpty) {
    final app = <String, dynamic>{};
    for (final k in appPrefs.keys) {
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) app[k] = v;
    }
    if (app.isNotEmpty) result['appPrefs'] = app;
  }

  // AI 记忆（专用参数）
  if (aiMemory != null && aiMemory.isNotEmpty) {
    result['aiMemory'] = aiMemory;
  }

  // 额外 key（v1 兼容；perm.* 请用 permissions 段）
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

/// 从 `.evgconfig` 格式导入配置（v2，兼容 v1）。
///
/// 安全模型（修复 O1 三缺陷 + 加固）：
/// - **version 校验**：format 必须为 `evgconfig`（或缺失），version 必须在
///   [kEvgConfigMinVersion..kEvgConfigVersion]；更高版本拒绝导入（提示升级应用）。
/// - **settings 白名单**：仅写入已声明的键，且按声明做类型语义校验
///   （bool_ 必须 "true"/"false"，option 必须在选项列表），非法值跳过。
/// - **dynamicSettings 白名单**：仅写入 [allowedDynamicKeys]（调用方=ConfigHttpServer
///   枚举）中的键——修复 O1「动态项无法导入」且不引入任意 key 写入风险。
/// - **permissions 正确类型**：经 `importPermissions` 以 bool 读写并仅接受已注册
///   插件的已声明权限键（走 `setPermission` 语义，非裸 SP 写）。
/// - **appPrefs 白名单**：仅写入 [allowedAppPrefs] 中的键。
/// - **extra（v1 兼容）**：白名单 = 已声明设置 ∪ [allowedDynamicKeys] ∪ [allowedAppPrefs]；
///   `perm.*` 键跳过并提示改用 permissions 段——修复 O1「extra 无过滤」。
/// - **isSecure**：默认不导入已声明 isSecure 键（防覆盖现有密钥），[allowSecure] 可放行。
/// - **非空值保护（可选）**：[overwrite] 默认 `true`（保持 v1 导入语义：写入即覆盖）；
///   同步中心做合并导入时传 `overwrite: false` 启用非空值保护
///   （已有非空值不被导入值覆盖，沿用 `.greenix/config.json` 同步的保护哲学）。
/// - **导入后回调**：[onChanged] 在发生任何实际写入后触发（如
///   `configServer.syncConfigToGreenix`）——修复 O1「导入后不触发 greenix 同步」。
///
/// 返回 `aiMemory` 数据供 Agent 模块自行导入（Config 不直接操作 MemoryStore）。
Future<Map<String, dynamic>?> importConfig(
  SharedPreferences prefs,
  Map<String, dynamic> config, {
  List<String> allowedDynamicKeys = const [],
  Map<String, String>? allowedAppPrefs,
  bool overwrite = true,
  bool allowSecure = false,
  void Function()? onChanged,
}) async {
  // ── format / version 校验 ──
  final format = config['format'];
  if (format != null && format != 'evgconfig') {
    throw ConfigValidationException(
      key: 'format', value: '$format', reason: '仅支持 evgconfig 格式的配置导出文件',
    );
  }
  final version = config['version'];
  if (version is int && (version < kEvgConfigMinVersion || version > kEvgConfigVersion)) {
    throw ConfigValidationException(
      key: 'version',
      value: '$version',
      reason: '导出版本 $version 超出支持范围 [$kEvgConfigMinVersion..$kEvgConfigVersion]，请升级应用后导入',
    );
  }

  var changed = false;

  // ── settings（仅已声明键 + 类型语义校验）──
  final settings = config['settings'] as Map<String, dynamic>?;
  if (settings != null) {
    for (final entry in settings.entries) {
      if (!_decls.containsKey(entry.key)) continue;
      final decl = _decls[entry.key]!;
      if (decl.isSecure && !allowSecure) continue; // isSecure 默认不导入
      final raw = entry.value;
      if (raw is! String || raw.isEmpty) continue;
      if (decl.type == SettingType.bool_ && raw != 'true' && raw != 'false') {
        stderr.writeln('[Config] ⚠ 导入跳过非法 bool 值: ${entry.key}="$raw"');
        continue;
      }
      if (decl.type == SettingType.option &&
          decl.options != null &&
          !decl.options!.any((o) => o.value == raw)) {
        stderr.writeln('[Config] ⚠ 导入跳过非法 option 值: ${entry.key}="$raw"');
        continue;
      }
      if (await _writeIfAllowed(prefs, entry.key, raw, overwrite)) changed = true;
    }
  }

  // ── dynamicSettings（白名单 key）──
  final dynamicSettings = config['dynamicSettings'] as Map<String, dynamic>?;
  if (dynamicSettings != null) {
    for (final entry in dynamicSettings.entries) {
      if (!allowedDynamicKeys.contains(entry.key)) continue; // 白名单过滤
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        if (await _writeIfAllowed(prefs, entry.key, entry.value as String, overwrite)) {
          changed = true;
        }
      }
    }
  }

  // ── sources ──
  final sources = config['sources'];
  if (sources != null) {
    await prefs.setString('_plugin_sources', jsonEncode(sources));
    changed = true;
  }

  // ── permissions（v2 段，bool 正确类型 + 声明校验）──
  final permissions = config['permissions'] as Map<String, dynamic>?;
  if (permissions != null) {
    final written = await importPermissions(prefs, permissions, overwrite: overwrite);
    if (written > 0) changed = true;
  }

  // ── appPrefs（白名单）──
  final appPrefs = config['appPrefs'] as Map<String, dynamic>?;
  if (appPrefs != null) {
    for (final entry in appPrefs.entries) {
      if (!(allowedAppPrefs?.containsKey(entry.key) ?? false)) continue; // 白名单
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        if (await _writeIfAllowed(prefs, entry.key, entry.value as String, overwrite)) {
          changed = true;
        }
      }
    }
  }

  // ── extra（v1 兼容；白名单过滤；perm.* 走 permissions 段）──
  final extra = config['extra'] as Map<String, dynamic>?;
  if (extra != null) {
    for (final entry in extra.entries) {
      final k = entry.key;
      if (k.startsWith('perm.')) {
        stderr.writeln('[Config] ⚠ extra 中的 perm.* 键请改用 permissions 段（跳过: $k）');
        continue;
      }
      final isDeclared = _decls.containsKey(k);
      final isAllowedDynamic = allowedDynamicKeys.contains(k);
      final isAllowedAppPref = allowedAppPrefs?.containsKey(k) ?? false;
      if (!isDeclared && !isAllowedDynamic && !isAllowedAppPref) continue; // 白名单
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        if (await _writeIfAllowed(prefs, k, entry.value as String, overwrite)) changed = true;
      }
    }
  }

  // 导入后回调（如 syncConfigToGreenix）——仅在发生实际写入时触发
  if (changed && onChanged != null) onChanged();

  // 返回 AI 记忆数据供调用方自行导入
  return config['aiMemory'] as Map<String, dynamic>?;
}

/// 写入单个 String 值；非覆盖模式下已有非空值保留（非空值保护）。
Future<bool> _writeIfAllowed(
  SharedPreferences prefs,
  String key,
  String value,
  bool overwrite,
) async {
  if (!overwrite) {
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return false;
  }
  await prefs.setString(key, value);
  return true;
}


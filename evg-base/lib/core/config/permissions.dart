/// 插件权限管理——注册、读写、检查、即时生效。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `PermissionDecl` | 一项权限声明（key / label / description） |
/// | `registerPermissions(pluginId, perms)` | 注册插件权限声明 |
/// | `getPermissions(prefs, pluginId)` | 读全部权限状态 |
/// | `setPermission(prefs, pluginId, permKey, granted)` | 设置单个权限 |
/// | `checkPermission(prefs, pluginId, permKey)` | 检查权限，拒绝时抛异常 |
/// | `describePermission(perm)` | 生成通俗语言描述 |
/// | `getPermissionDecls(pluginId)` | 查询插件的权限声明列表 |
library permissions;

import 'package:shared_preferences/shared_preferences.dart';

import 'exceptions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 一项权限声明。
///
/// 权限列表在插件安装时由 Core 提取自 agent/manifest.json，
/// 通过 [registerPermissions] 注册到 Config 模块。
class PermissionDecl {
  /// 权限键，如 `"web_search"`、`"read_file"`。
  final String key;

  /// UI 标签，如 `"联网搜索"`。
  final String label;

  /// 自然语言描述，说明该权限的用途与风险。
  final String description;

  /// 默认授权状态。未显式设置时使用此值。
  final bool defaultGranted;

  const PermissionDecl({
    required this.key,
    required this.label,
    required this.description,
    this.defaultGranted = true,
  });

  @override
  String toString() => 'PermissionDecl($key: $label)';
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部——声明存储
// ═══════════════════════════════════════════════════════════════════════════

/// pluginId → List<PermissionDecl>
final Map<String, List<PermissionDecl>> _permDecls = {};

/// SharedPreferences key 前缀。
const _permPrefix = 'perm.';

/// 构造 SP 存储键。
String _permKey(String pluginId, String permKey) =>
    '$_permPrefix$pluginId.$permKey';

// ═══════════════════════════════════════════════════════════════════════════
// 公开 API
// ═══════════════════════════════════════════════════════════════════════════

/// 注册插件的权限声明。
///
/// 在插件安装流程中由 Core 调用。每个插件只应注册一次；
/// 重复注册会覆盖之前的声明。
/// 默认授权状态由 [PermissionDecl.defaultGranted] 指定。
void registerPermissions(String pluginId, List<PermissionDecl> perms) {
  _permDecls[pluginId] = List.unmodifiable(perms);
}

/// 读取插件全部权限状态（接口 I16）。
///
/// 返回 `权限键 → 是否已授权` 的映射。
/// 未显式设置的权限回退 [PermissionDecl.defaultGranted]。
Map<String, bool> getPermissions(SharedPreferences prefs, String pluginId) {
  final decls = _permDecls[pluginId];
  if (decls == null) return {};

  final result = <String, bool>{};
  for (final d in decls) {
    final spKey = _permKey(pluginId, d.key);
    result[d.key] = prefs.getBool(spKey) ?? d.defaultGranted;
  }
  return result;
}

/// 设置单个权限状态，即时生效（≤1s）。
///
/// 写入 SharedPreferences 后立即生效，后续 [checkPermission] 使用最新值。
/// 变更后写入 [perm_update] 变更日志 key，供 ConfigHttpServer 轮询/推送使用。
Future<void> setPermission(
  SharedPreferences prefs,
  String pluginId,
  String permKey,
  bool granted,
) async {
  final spKey = _permKey(pluginId, permKey);
  await prefs.setBool(spKey, granted);
}

/// 检查权限——拒绝时抛出 [PermissionDeniedException]。
///
/// 使用方式：插件 .exe 或 Agent 在调用敏感操作前调用此方法。
///
/// ```dart
/// checkPermission(prefs, 'my_plugin', 'web_search');
/// ```
void checkPermission(SharedPreferences prefs, String pluginId, String permKey) {
  final perms = getPermissions(prefs, pluginId);
  final granted = perms[permKey] ?? true;
  if (!granted) {
    throw PermissionDeniedException(pluginId, permKey);
  }
}

/// 生成通俗语言描述，用于安装时授权弹窗 UI。
///
/// 返回的字符串包含权限标签和详细说明，可直接在弹窗中展示。
String describePermission(PermissionDecl perm) {
  return '【${perm.label}】${perm.description}';
}

/// 查询插件的权限声明列表。
///
/// 返回 `null` 表示该插件未注册任何权限。
List<PermissionDecl>? getPermissionDecls(String pluginId) {
  return _permDecls[pluginId];
}

/// 侧边栏导航过滤——按插件状态（enabled / sidebarVisible）过滤。
///
/// 背景（/marketplace 反馈「隐藏侧栏、是否启用根本没效果」）：
/// `ModuleRegistry` 在启动时 seal，侧边栏 `navGroups`/`navFlat` 直接读它，
/// 而 marketplace 的启用/隐藏开关只把状态写进 `plugins/.plugin_states.json`，
/// 从未被侧边栏消费——所以开关对全局导航毫无影响。
///
/// 修复：侧边栏在渲染前用本文件的函数过滤导航条目，使开关即时生效。
library;
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/sidebar_section.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';

/// 按插件状态过滤导航分组。
///
/// 规则：
/// - `state == null`（不在 plugins/ 或无状态记录，如内置模块）→ 保留（默认启用且侧栏可见）
/// - `enabled == false`（已停用）→ 隐藏
/// - `sidebarVisible == false`（已隐藏侧栏）→ 隐藏
/// 过滤后若某 section 已无条目则整体移除，避免空分组标题。
List<(SidebarSection, List<NavEntry>)> filterNavByPluginState(
  List<(SidebarSection, List<NavEntry>)> groups,
  Map<String, PluginStateRecord> states,
) {
  final out = <(SidebarSection, List<NavEntry>)>[];
  for (final (section, entries) in groups) {
    final kept = entries.where((e) {
      final st = states[e.moduleId];
      return st == null || (st.enabled && st.sidebarVisible);
    }).toList();
    if (kept.isNotEmpty) {
      out.add((section, kept));
    }
  }
  return out;
}

/// 按插件状态过滤扁平导航（collapsed 侧边栏 / 移动端底部导航用）。
List<NavEntry> filterNavFlatByPluginState(
  List<NavEntry> flat,
  Map<String, PluginStateRecord> states,
) =>
    flat.where((e) {
      final st = states[e.moduleId];
      return st == null || (st.enabled && st.sidebarVisible);
    }).toList();

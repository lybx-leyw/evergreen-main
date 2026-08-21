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

/// 按用户布局配置重排侧边栏导航分组。
///
/// 用户在插件中心拖拽调整的「分组顺序 / 组内插件顺序」最终要反映到侧边栏：
/// - 分组间顺序：优先用 `config.groups[label].order`（用户拖拽值），
///   未自定义的分组回退到 manifest `sectionOrder + 1000`（排在用户调过序的分组之后，
///   保持相互间的 manifest 相对顺序）；
/// - 组内条目顺序：优先用 `states[moduleId].sortOrder`（用户拖拽值），
///   未自定义的条目回退到 manifest `order + 1000`（同上）。
///
/// 纯函数：不改动入参，返回新列表。
List<(SidebarSection, List<NavEntry>)> applyUserNavLayout(
  List<(SidebarSection, List<NavEntry>)> groups,
  PluginCenterConfig config,
  Map<String, PluginStateRecord> states,
) {
  final out = <(SidebarSection, List<NavEntry>)>[];
  for (final (section, entries) in groups) {
    final userOrdered = List<NavEntry>.from(entries)
      ..sort((a, b) {
        final oa = states[a.moduleId]?.sortOrder ?? a.order + 1000;
        final ob = states[b.moduleId]?.sortOrder ?? b.order + 1000;
        final c = oa.compareTo(ob);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    out.add((section, userOrdered));
  }
  out.sort((a, b) {
    final oa = config.groups[a.$1.label]?.order ?? a.$1.order + 1000;
    final ob = config.groups[b.$1.label]?.order ?? b.$1.order + 1000;
    final c = oa.compareTo(ob);
    return c != 0 ? c : a.$1.order.compareTo(b.$1.order);
  });
  return out;
}

/// 扁平导航的用户布局版本（collapsed 侧边栏 / 移动端底部导航用）。
///
/// 扁平列表不携带分组信息，因此先按分组重排、再展开，保证与分组视图一致。
List<NavEntry> applyUserNavLayoutFlat(
  List<(SidebarSection, List<NavEntry>)> groups,
  PluginCenterConfig config,
  Map<String, PluginStateRecord> states,
) =>
    applyUserNavLayout(groups, config, states).expand((g) => g.$2).toList();

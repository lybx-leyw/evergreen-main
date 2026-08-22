/// 全局插件状态（enabled / sidebarVisible / 布局配置）Provider。
///
/// 单一真相来源：从 `pluginsDirProvider` 指向的插件目录读取
/// `plugins/.plugin_states.json`。marketplace、app 侧边栏、路由重定向都 watch
/// 本 Provider，因此 marketplace 中切换「启用 / 隐藏侧栏 / 拖拽排序 / 组名显示」
/// 会即时反映到侧边栏导航。
///
/// 之前 marketplace 各自 new 一个 `PluginStateService` 实例、开关只写文件，
/// 侧边栏从不读取——开关对全局导航无效。统一走本 Provider 后，
/// 任一处 toggle 都会 `state =` 重新赋值并通知所有监听者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';

/// 插件中心状态快照：插件记录 + 布局配置。
///
/// 两者同源（同一个 `.plugin_states.json`），打包成一个不可变对象，
/// 保证侧边栏（组名/顺序）与 marketplace（排序/拖拽）对同一份配置保持响应式一致。
class PluginCenterState {
  const PluginCenterState({required this.records, required this.config});

  final Map<String, PluginStateRecord> records;
  final PluginCenterConfig config;
}

final pluginStateProvider =
    NotifierProvider<PluginStateNotifier, PluginCenterState>(
  PluginStateNotifier.new,
);

class PluginStateNotifier extends Notifier<PluginCenterState> {
  late final PluginStateService _service;

  @override
  PluginCenterState build() {
    final dir = p.normalize(ref.watch(pluginsDirProvider));
    _service = PluginStateService(dir);
    return _load();
  }

  PluginCenterState _load() => PluginCenterState(
        records: _service.loadAll(),
        config: _service.loadConfig(),
      );

  void _reload() => state = _load();

  void setEnabled(String id, bool enabled) {
    _service.setEnabled(id, enabled);
    _reload();
  }

  void setSidebarVisible(String id, bool visible) {
    _service.setSidebarVisible(id, visible);
    _reload();
  }

  void remove(String id) {
    _service.remove(id);
    _reload();
  }

  void registerInstalled(String id) {
    _service.registerInstalled(id);
    _reload();
  }

  void touch(String id) {
    _service.touch(id);
    _reload();
  }

  // ═══════ 布局配置 ═══════

  /// 设置排序策略（'group' / 'name' / 'recent'）。
  void setSortMode(String mode) {
    _service.setSortMode(mode);
    _reload();
  }

  /// 按序落盘分组拖拽顺序（0..n-1）。
  void setGroupOrderAll(List<String> orderedLabels) {
    _service.setGroupOrderAll(orderedLabels);
    _reload();
  }

  /// 设置分组「侧边栏是否显示组名」。
  void setGroupShowNameInSidebar(String label, bool show) {
    _service.setGroupShowNameInSidebar(label, show);
    _reload();
  }

  /// 设置分组折叠状态（插件中心展示用）。
  void setGroupCollapsed(String label, bool collapsed) {
    _service.setGroupCollapsed(label, collapsed);
    _reload();
  }

  /// 按序落盘某个分组内插件的拖拽顺序（0..n-1）。
  void setPluginSortOrderAll(String groupLabel, List<String> orderedIds) {
    _service.setPluginSortOrderAll(groupLabel, orderedIds);
    _reload();
  }
}

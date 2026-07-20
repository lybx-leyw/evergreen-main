/// 全局插件状态（enabled / sidebarVisible 等）Provider。
///
/// 单一真相来源：从 `pluginsDirProvider` 指向的插件目录读取
/// `plugins/.plugin_states.json`。marketplace 与 app 侧边栏都 watch 本 Provider，
/// 因此 marketplace 中切换「启用 / 隐藏侧栏」会即时反映到侧边栏导航。
///
/// 之前 marketplace 各自 new 一个 `PluginStateService` 实例、开关只写文件，
/// 侧边栏从不读取——开关对全局导航无效。统一走本 Provider 后，
/// 任一处 toggle 都会 `state =` 重新赋值并通知所有监听者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';

final pluginStateProvider =
    NotifierProvider<PluginStateNotifier, Map<String, PluginStateRecord>>(
  PluginStateNotifier.new,
);

class PluginStateNotifier extends Notifier<Map<String, PluginStateRecord>> {
  late final PluginStateService _service;

  @override
  Map<String, PluginStateRecord> build() {
    final dir = p.normalize(ref.watch(pluginsDirProvider));
    _service = PluginStateService(dir);
    return _service.loadAll();
  }

  void setEnabled(String id, bool enabled) {
    _service.setEnabled(id, enabled);
    state = _service.loadAll();
  }

  void setSidebarVisible(String id, bool visible) {
    _service.setSidebarVisible(id, visible);
    state = _service.loadAll();
  }

  void remove(String id) {
    _service.remove(id);
    state = _service.loadAll();
  }

  void registerInstalled(String id) {
    _service.registerInstalled(id);
    state = _service.loadAll();
  }

  void touch(String id) {
    _service.touch(id);
    state = _service.loadAll();
  }
}

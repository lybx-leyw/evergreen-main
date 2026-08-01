// marketplace 侧边栏过滤回归测试（纯 Dart，不挂载 widget / 不碰 Provider，绝不挂死）。
//
// 背景（/marketplace 反馈「隐藏侧栏、是否启用根本没效果」）：
// ModuleRegistry 启动时 seal，侧边栏 navGroups/navFlat 直接读它；而 marketplace 的
// 启用/隐藏开关只把状态写进 plugins/.plugin_states.json，侧边栏从不消费 → 开关无效。
// 修复：侧边栏渲染前用 filterNavByPluginState / filterNavFlatByPluginState 过滤。
//
// 本测试锁定契约：
// 1. state == null（内置模块/无记录）→ 保留
// 2. enabled == false → 隐藏
// 3. sidebarVisible == false → 隐藏
// 4. 过滤后空 section 整体移除
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/sidebar_section.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/nav_filter.dart';
import 'package:flutter_test/flutter_test.dart';

NavEntry _entry(String id) => NavEntry(
      icon: 0xe000,
      label: id,
      routePath: '/$id',
      moduleId: id,
    );

PluginStateRecord _rec({
  required String id,
  bool enabled = true,
  bool sidebarVisible = true,
}) =>
    PluginStateRecord(
      pluginId: id,
      enabled: enabled,
      sidebarVisible: sidebarVisible,
      installedAt: DateTime(2026, 1, 1),
      lastUsedAt: DateTime(2026, 1, 1),
    );

void main() {
  const secA = SidebarSection('A', order: 1);
  const secB = SidebarSection('B', order: 2);

  group('filterNavByPluginState', () {
    test('state==null 保留；enabled=false 与 sidebarVisible=false 隐藏', () {
      final groups = <(SidebarSection, List<NavEntry>)>[
        (
          secA,
          [_entry('alpha'), _entry('beta'), _entry('gamma')]
        ),
      ];
      final states = {
        'alpha': _rec(id: 'alpha', enabled: false), // 停用 → 隐藏
        'beta': _rec(id: 'beta', sidebarVisible: false), // 隐藏侧栏 → 隐藏
        // gamma 无记录 → 保留
      };

      final out = filterNavByPluginState(groups, states);
      final kept = out.expand((g) => g.$2).map((e) => e.moduleId).toList();
      expect(kept, ['gamma']);
    });

    test('全部隐藏后 section 整体移除', () {
      final groups = <(SidebarSection, List<NavEntry>)>[
        (secA, [_entry('a'), _entry('b')]),
        (secB, [_entry('c')]),
      ];
      final states = {
        'a': _rec(id: 'a', enabled: false),
        'b': _rec(id: 'b', sidebarVisible: false),
        'c': _rec(id: 'c', enabled: false),
      };

      final out = filterNavByPluginState(groups, states);
      expect(out, isEmpty);
    });

    test('全启用时原样保留', () {
      final groups = <(SidebarSection, List<NavEntry>)>[
        (secA, [_entry('a'), _entry('b')]),
      ];
      final out = filterNavByPluginState(groups, {});
      expect(out.length, 1);
      expect(out.first.$2.length, 2);
    });
  });

  group('filterNavFlatByPluginState', () {
    test('按 enabled / sidebarVisible 过滤扁平列表', () {
      final flat = [_entry('a'), _entry('b'), _entry('c')];
      final states = {
        'a': _rec(id: 'a', enabled: false),
        'c': _rec(id: 'c', sidebarVisible: false),
      };
      final out = filterNavFlatByPluginState(flat, states);
      expect(out.map((e) => e.moduleId).toList(), ['b']);
    });
  });
}

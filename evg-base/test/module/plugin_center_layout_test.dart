/// 插件中心布局功能回归测试：
/// 1. PluginStateService 布局配置持久化（分组顺序 / 组内拖拽顺序 / 组名开关 / 折叠 / 排序策略）；
/// 2. touch() 真实使用记录（补建默认记录 + 更新 lastUsedAt）；
/// 3. applyUserNavLayout 侧边栏重排（分组顺序 + 组内顺序，用户配置优先、manifest 回退）；
/// 4. scanPluginManifests 分组信息推导（nav.sidebar.section / order / sectionOrder）。
///
/// 纯 Dart：不挂载 widget、不碰 Riverpod，绝不挂死。
library;
import 'dart:io';

import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/sidebar_section.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/marketplace_scan.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/nav_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

NavEntry _entry(String id, {int order = 50}) => NavEntry(
      icon: 0xe000,
      label: id,
      routePath: '/$id',
      moduleId: id,
      order: order,
    );

PluginStateRecord _rec({
  required String id,
  bool enabled = true,
  bool sidebarVisible = true,
  int? sortOrder,
  DateTime? lastUsedAt,
}) =>
    PluginStateRecord(
      pluginId: id,
      enabled: enabled,
      sidebarVisible: sidebarVisible,
      installedAt: DateTime(2026, 1, 1),
      lastUsedAt: lastUsedAt ?? DateTime(2026, 1, 1),
      sortOrder: sortOrder,
    );

void main() {
  group('PluginStateService 布局配置', () {
    late String tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('evg_layout_').path;
    });

    tearDown(() {
      Directory(tmpDir).deleteSync(recursive: true);
    });

    test('loadAll 跳过 _config；save/setGroupOrderAll 后配置与记录共存', () {
      final svc = PluginStateService(tmpDir);
      svc.save(_rec(id: 'a'));
      svc.setGroupOrderAll(['甲', '乙']);

      // 记录：只有 a，不含 _config
      final states = svc.loadAll();
      expect(states.keys, ['a']);
      // 配置：分组顺序按拖拽结果落盘
      final config = svc.loadConfig();
      expect(config.groups['甲']!.order, 0);
      expect(config.groups['乙']!.order, 1);
    });

    test('setSortMode / setGroupShowNameInSidebar / setGroupCollapsed 持久化', () {
      final svc = PluginStateService(tmpDir);
      svc.setSortMode('recent');
      svc.setGroupShowNameInSidebar('base主功能', false);
      svc.setGroupCollapsed('base主功能', true);

      final config = svc.loadConfig();
      expect(config.sortMode, 'recent');
      expect(config.groups['base主功能']!.showNameInSidebar, isFalse);
      expect(config.groups['base主功能']!.collapsed, isTrue);
    });

    test('save 保留既有 _config（互不覆盖）', () {
      final svc = PluginStateService(tmpDir);
      svc.setSortMode('name');
      svc.save(_rec(id: 'a'));
      svc.save(_rec(id: 'b'));

      expect(svc.loadConfig().sortMode, 'name');
      expect(svc.loadAll().keys, ['a', 'b']);
    });

    test('remove 保留 _config', () {
      final svc = PluginStateService(tmpDir);
      svc.save(_rec(id: 'a'));
      svc.setGroupOrderAll(['甲']);
      svc.remove('a');

      expect(svc.loadAll(), isEmpty);
      expect(svc.loadConfig().groups['甲']!.order, 0);
    });

    test('setPluginSortOrderAll 单次写盘；已有字段保留、缺失记录补建默认', () {
      final svc = PluginStateService(tmpDir);
      svc.save(_rec(id: 'a', enabled: false, sidebarVisible: false));
      svc.setPluginSortOrderAll('组A', ['b', 'a', 'c']);

      final states = svc.loadAll();
      // 已有记录：sortOrder 更新，其余字段保留
      expect(states['a']!.sortOrder, 1);
      expect(states['a']!.enabled, isFalse);
      expect(states['a']!.sidebarVisible, isFalse);
      // 缺失记录：补建默认（启用 + 侧栏可见）
      expect(states['b']!.sortOrder, 0);
      expect(states['b']!.enabled, isTrue);
      expect(states['c']!.sortOrder, 2);
    });

    test('PluginStateRecord.sortOrder JSON 往返', () {
      final svc = PluginStateService(tmpDir);
      svc.save(_rec(id: 'a', sortOrder: 3));
      expect(svc.load('a')!.sortOrder, 3);
      svc.save(_rec(id: 'b'));
      expect(svc.load('b')!.sortOrder, isNull);
    });

    test('touch 更新 lastUsedAt；无记录时补建默认记录', () {
      final svc = PluginStateService(tmpDir);
      final t0 = DateTime(2026, 1, 1);
      svc.save(_rec(id: 'a', lastUsedAt: t0));
      svc.touch('a');
      expect(svc.load('a')!.lastUsedAt.isAfter(t0), isTrue);

      // 无记录插件（如内置模块）→ 补建默认记录
      expect(svc.load('builtin-x'), isNull);
      svc.touch('builtin-x');
      final rec = svc.load('builtin-x')!;
      expect(rec.enabled, isTrue);
      expect(rec.sidebarVisible, isTrue);
    });
  });

  group('applyUserNavLayout 侧边栏重排', () {
    const secA = SidebarSection('A', order: 1);
    const secB = SidebarSection('B', order: 2);
    const secC = SidebarSection('C', order: 3);

    List<(SidebarSection, List<NavEntry>)> groups() => [
          (secA, [_entry('x', order: 10), _entry('y', order: 20)]),
          (secB, [_entry('z', order: 30)]),
          (secC, [_entry('w', order: 40)]),
        ];

    test('未配置时保持 manifest 顺序', () {
      final out = applyUserNavLayout(groups(), const PluginCenterConfig(), {});
      expect(out.map((g) => g.$1.label).toList(), ['A', 'B', 'C']);
      expect(out.first.$2.map((e) => e.moduleId).toList(), ['x', 'y']);
    });

    test('分组顺序：用户配置优先，未配置回退 manifest（排在其后）', () {
      final config = const PluginCenterConfig(
        groups: {'B': PluginGroupConfig(label: 'B', order: 0)},
      );
      final out = applyUserNavLayout(groups(), config, {});
      // B(0) 最前；A/C 未配置 → manifest order + 1000 保持相对顺序
      expect(out.map((g) => g.$1.label).toList(), ['B', 'A', 'C']);
    });

    test('组内顺序：sortOrder 优先，未配置回退 manifest order', () {
      final states = {
        'x': _rec(id: 'x', sortOrder: 1),
        'y': _rec(id: 'y', sortOrder: 0),
      };
      final out = applyUserNavLayout(groups(), const PluginCenterConfig(), states);
      // A 组内：y(0) 在 x(1) 前；B/C 未配置保持 manifest 顺序
      expect(out.first.$2.map((e) => e.moduleId).toList(), ['y', 'x']);
      expect(out[1].$2.map((e) => e.moduleId).toList(), ['z']);
      expect(out[2].$2.map((e) => e.moduleId).toList(), ['w']);
    });

    test('applyUserNavLayoutFlat 与分组视图顺序一致', () {
      final config = const PluginCenterConfig(
        groups: {'B': PluginGroupConfig(label: 'B', order: 0)},
      );
      final states = {
        'x': _rec(id: 'x', sortOrder: 1),
        'y': _rec(id: 'y', sortOrder: 0),
      };
      final flat = applyUserNavLayoutFlat(groups(), config, states);
      expect(flat.map((e) => e.moduleId).toList(), ['z', 'y', 'x', 'w']);
    });
  });

  group('scanPluginManifests 分组信息推导', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('evg_scan_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    void writeModule(String folder, String json) {
      final dir = Directory(p.join(tmp.path, folder))..createSync();
      Directory(p.join(dir.path, 'module')).createSync();
      File(p.join(dir.path, 'module', 'manifest.json')).writeAsStringSync(json);
    }

    test('module 带 nav.sidebar → section/sectionOrder/order 来自 manifest', () {
      writeModule('with-sidebar', '''
{
  "type": "module",
  "id": "with-sidebar",
  "name": "有侧栏",
  "route": "/with-sidebar",
  "nav": { "sidebar": { "section": "base主功能", "sectionOrder": 10, "order": 5 } }
}
''');
      final (descriptors, _) = scanPluginManifests(tmp.path);
      final info = descriptors.single;
      expect(info.section, 'base主功能');
      expect(info.sectionOrder, 10);
      expect(info.order, 5);
    });

    test('module 无 nav.sidebar → 回退「未分组」默认值', () {
      writeModule('no-sidebar', '''
{
  "type": "module",
  "id": "no-sidebar",
  "name": "无侧栏"
}
''');
      final (descriptors, _) = scanPluginManifests(tmp.path);
      final info = descriptors.single;
      expect(info.section, '未分组');
      expect(info.sectionOrder, 50);
      expect(info.order, 50);
    });
  });
}

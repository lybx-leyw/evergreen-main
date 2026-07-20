/// P2 插件编排器 Widget 测试 — v3 按钮式重构。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart' hide LayoutPreset;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/component_picker.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/property_panel.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/page_sorter.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('P2 ComponentPicker', () {
    testWidgets('渲染全部组件组', (tester) async {
      await tester.pumpWidget(_wrap(const ComponentPicker()));
      await tester.pumpAndSettle();

      expect(find.text('对话与交互'), findsOneWidget);
      expect(find.text('数据展示'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      expect(find.text('控件'), findsOneWidget);
    });

    testWidgets('搜索过滤', (tester) async {
      await tester.pumpWidget(_wrap(const ComponentPicker()));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '图表');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InkWell, '图表'), findsOneWidget);
      expect(find.text('数据表格'), findsNothing);
    });

    testWidgets('点击组件触发回调', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(ComponentPicker(
        onComponentSelected: (t) => selected = t,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('对话与交互'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI 助手'));
      await tester.pumpAndSettle();

      expect(selected, 'ai-assistant');
    });
  });

  // v3: CanvasArea/SlotPainter 测试已移除（画布拖拽功能已删除）。

  group('P2 PropertyPanel (v3 按钮式，无 rect 编辑)', () {
    testWidgets('无选中时显示空态', (tester) async {
      await tester.pumpWidget(_wrap(const PropertyPanel()));
      await tester.pumpAndSettle();
      expect(find.textContaining('选择一个 Slot'), findsOneWidget);
    });

    testWidgets('选中 Slot 时显示属性编辑器', (tester) async {
      final slot = DesignSlot(
        id: 'slot_0',
        label: '我的Slot',
        region: SlotRegion.center,
        component: DesignComponent(type: 'chart', config: {'title': 'Test'}),
      );

      await tester.pumpWidget(_wrap(PropertyPanel(selectedSlot: slot)));
      await tester.pumpAndSettle();

      expect(find.text('Slot 属性'), findsOneWidget);
      // v3：不再显示"位置与大小"
      expect(find.text('位置与大小'), findsNothing);
      expect(find.text('绑定组件'), findsOneWidget);

      final labelField = find.widgetWithText(TextField, '我的Slot');
      expect(labelField, findsOneWidget);
    });

    testWidgets('编辑属性触发回调（v3 无 rect）', (tester) async {
      String? changedLabel;
      final slot = DesignSlot(id: 'slot_0', label: '');

      await tester.pumpWidget(_wrap(PropertyPanel(
        selectedSlot: slot,
        onSlotPropChanged: ({label, region, rect}) {
          changedLabel = label;
        },
      )));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '新标签');
      await tester.pumpAndSettle();

      expect(changedLabel, '新标签');
    });

    testWidgets('选中 Slot 时显示删除按钮并触发回调', (tester) async {
      bool deleted = false;
      final slot = DesignSlot(
        id: 'slot_0',
        label: '我的Slot',
        region: SlotRegion.center,
        component: DesignComponent(type: 'chart', config: {'title': 'Test'}),
      );
      await tester.pumpWidget(_wrap(PropertyPanel(
        selectedSlot: slot,
        onSlotDeleted: () => deleted = true,
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('未提供回调时不显示删除按钮', (tester) async {
      final slot = DesignSlot(id: 'slot_0', label: '');
      await tester.pumpWidget(_wrap(PropertyPanel(selectedSlot: slot)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('P2 PageSorter', () {
    testWidgets('渲染页面标签', (tester) async {
      final pages = [
        DesignPage(id: 'page_0', label: '首页'),
        DesignPage(id: 'page_1', label: '第二页'),
      ];

      await tester.pumpWidget(_wrap(PageSorter(pages: pages)));
      await tester.pumpAndSettle();

      expect(find.text('首页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('渲染 ReorderableListView 与拖拽手柄', (tester) async {
      final pages = [
        DesignPage(id: 'p0', label: '首页'),
        DesignPage(id: 'p1', label: '第二页'),
        DesignPage(id: 'p2', label: '第三页'),
      ];
      await tester.pumpWidget(_wrap(PageSorter(pages: pages)));
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
      expect(find.text('首页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('第三页'), findsOneWidget);
    });
  });

  group('P2 DesignDocument 编排操作', () {
    test('创建文档并添加页面和 Slot（v3 无 rect）', () {
      final doc = DesignDocument(pluginId: 'test', pluginName: '测试');

      doc.addPage(DesignPage(id: 'page_0', label: '首页'));
      expect(doc.pages.length, 1);
      expect(doc.pageCount, 1);

      doc.pages.first.addSlot(DesignSlot(
        id: 'slot_0',
        label: '图表',
        region: SlotRegion.center,
      ));
      expect(doc.slotCount, 1);

      doc.pages.first.slots.first.component = DesignComponent(
        type: 'chart',
        config: {'title': '销售数据'},
      );
      expect(doc.pages.first.slots.first.component?.type, 'chart');
    });

    test('touch 更新 updatedAt', () {
      final doc = DesignDocument(pluginId: 'test', pluginName: '测试');
      final before = doc.updatedAt;
      doc.touch();
      expect(doc.updatedAt.millisecondsSinceEpoch >= before.millisecondsSinceEpoch, isTrue);
    });

    test('布局预设切换', () {
      final page = DesignPage(id: 'p0', label: '首页');
      expect(page.layoutPreset, DesignPageLayout.grid);

      page.layoutPreset = DesignPageLayout.fullscreen;
      expect(page.layoutPreset, DesignPageLayout.fullscreen);

      page.layoutPreset = DesignPageLayout.dock;
      expect(page.layoutPreset, DesignPageLayout.dock);
    });
  });

  group('P2 DesignToManifest 编译器', () {
    DesignDocument _buildDoc(DesignPageLayout layout) {
      final doc = DesignDocument(
        pluginId: 'demo',
        pluginName: '演示',
        icon: 'auto_awesome',
        description: 'desc',
        route: '/demo',
        version: '1.2.3',
        dependencies: const ['base', 'core'],
        nav: const DesignNav(
          section: '展示',
          sectionOrder: 100,
          order: 3,
          badge: true,
        ),
        process: const [
          DesignProcess(exe: 'module/demo.exe', protocol: 'http'),
        ],
      );
      final page = DesignPage(
        id: 'page_0',
        label: '首页',
        layoutPreset: layout,
        isDefault: true,
        hideTab: true,
      );
      page.addSlot(DesignSlot(
        id: 'slot_0',
        region: SlotRegion.center,
        component: DesignComponent(type: 'chart', config: {'title': 'T'}),
      ));
      doc.addPage(page);
      return doc;
    }

    test('dock/grid/flex 布局均输出完整 manifest V2 字段', () {
      for (final layout in [
        DesignPageLayout.dock,
        DesignPageLayout.grid,
        DesignPageLayout.flex,
      ]) {
        final json = DesignToManifest.compile(_buildDoc(layout));
        expect(json['schemaVersion'], '2.0');
        expect(json['renderMode'], 'dart');
        expect(json['type'], 'module');
        expect(json['id'], 'demo');
        expect(json['name'], '演示');
        expect(json['ui'], 'composite');
        expect(json['version'], '1.2.3');
        expect(json['dependencies'], containsAll(['base', 'core']));
        expect(json['nav']['sidebar']['section'], '展示');
        expect(json['nav']['sidebar']['sectionOrder'], 100);
        expect(json['nav']['sidebar']['order'], 3);
        expect(json['nav']['sidebar']['badge'], isTrue);
        expect(json['process'], isA<List>());
        expect(json['process'][0]['exe'], 'module/demo.exe');
        expect(json['process'][0]['protocol'], 'http');
        expect(json['pages'], isA<List>());
        final page = (json['pages'] as List).first;
        expect(page['default'], isTrue);
        expect(page['hideTab'], isTrue);
        expect(
          page['layout']['slots']['slot_0']['component']['type'],
          'chart',
        );
      }
    });

    test('compile 输出可被 ModuleDescriptor.fromJson 解析', () {
      final doc = _buildDoc(DesignPageLayout.grid);
      final json = DesignToManifest.compile(doc);
      final descriptor = ModuleDescriptor.fromJson(json);
      expect(descriptor.id, 'demo');
      expect(descriptor.name, '演示');
      expect(descriptor.version, '1.2.3');
      expect(descriptor.nav.sidebar?.section, '展示');
      expect(descriptor.process.first.exe, 'module/demo.exe');
      expect(descriptor.pages.first.isDefault, isTrue);
      expect(descriptor.pages.first.hideTab, isTrue);
      expect(descriptor.pages.first.componentTypes, contains('chart'));
    });
  });

  group('P2 ComponentRegistry 全量组件', () {
    test('权威清单含 50 具名 + 20 预留 = 70 种', () {
      expect(ComponentRegistry.knownTypes.length, 70);
      for (final c in allDesignerComponents) {
        expect(ComponentRegistry.isKnownType(c.type), isTrue, reason: c.type);
      }
      expect(ComponentRegistry.isKnownType('placeholder-20'), isTrue);
      expect(ComponentRegistry.isKnownType('unknown-xxx'), isFalse);
    });

    testWidgets('面板渲染预留扩展分组与 placeholder', (tester) async {
      await tester.pumpWidget(_wrap(const ComponentPicker()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('预留扩展'));
      await tester.pumpAndSettle();
      expect(find.text('预留-01'), findsOneWidget);
      expect(find.text('预留-20'), findsOneWidget);

      final search = find.byType(TextField);
      await tester.enterText(search, 'chart');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InkWell, '图表'), findsOneWidget);
    });
  });

  group('P2 DesignComponent sizeHint', () {
    test('sizeHint 解析与 copyWith（不进 manifest）', () {
      final c = DesignComponent(
        type: 'chart',
        config: {'a': 1},
        sizeHint: const Size(200, 150),
      );
      expect(c.sizeHint, const Size(200, 150));
      final j = c.toJson();
      expect(j.containsKey('sizeHint'), isFalse);
      expect(j['type'], 'chart');

      final parsed = DesignComponent.fromJson(
        {'type': 'x', 'sizeHint': {'w': 300, 'h': 100}},
      );
      expect(parsed.sizeHint, const Size(300, 100));

      final copied = c.copyWith(sizeHint: const Size(10, 10));
      expect(copied.sizeHint, const Size(10, 10));
    });
  });
}

/// P2 插件编排器 Widget 测试 — 验证交互组件渲染。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/view/canvas_area.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/view/component_picker.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/view/property_panel.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/view/slot_painter.dart';
import 'package:evergreen_base/renderer/components/document/plugin-designer/view/page_sorter.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('P2 ComponentPicker', () {
    testWidgets('渲染全部组件组', (tester) async {
      await tester.pumpWidget(_wrap(const ComponentPicker()));
      await tester.pumpAndSettle();

      // 应有分组标题
      expect(find.text('对话与交互'), findsOneWidget);
      expect(find.text('数据展示'), findsOneWidget);
      expect(find.text('工具'), findsOneWidget);
      expect(find.text('控件'), findsOneWidget);
    });

    testWidgets('搜索过滤', (tester) async {
      await tester.pumpWidget(_wrap(const ComponentPicker()));
      await tester.pumpAndSettle();

      // 输入搜索文本
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, '图表');
      await tester.pumpAndSettle();

      // 应只显示匹配项（排除搜索框中的文本）
      expect(find.widgetWithText(InkWell, '图表'), findsOneWidget);
      expect(find.text('数据表格'), findsNothing);
    });

    testWidgets('点击组件触发回调', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(ComponentPicker(
        onComponentSelected: (t) => selected = t,
      )));
      await tester.pumpAndSettle();

      // 展开"对话与交互"分组
      await tester.tap(find.text('对话与交互'));
      await tester.pumpAndSettle();

      // 点击"AI 助手"
      await tester.tap(find.text('AI 助手'));
      await tester.pumpAndSettle();

      expect(selected, 'ai-assistant');
    });
  });

  group('P2 CanvasArea', () {
    testWidgets('渲染画布网格', (tester) async {
      await tester.pumpWidget(_wrap(CanvasArea(
        slots: const [],
        canvasWidth: 400,
        canvasHeight: 300,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasArea), findsOneWidget);
    });

    testWidgets('渲染已有 Slot', (tester) async {
      final slots = [
        DesignSlot(
          id: 'slot_0',
          rect: [20, 20, 200, 150],
          label: '测试Slot',
          component: DesignComponent(type: 'chart', config: {}),
        ),
      ];

      await tester.pumpWidget(_wrap(CanvasArea(
        slots: slots,
        canvasWidth: 400,
        canvasHeight: 300,
      )));
      await tester.pumpAndSettle();

      // 画布应成功渲染（不崩溃）
      expect(find.byType(CanvasArea), findsOneWidget);
    });

    testWidgets('框选创建 Slot 触发回调', (tester) async {
      double? createdX, createdY, createdW, createdH;
      await tester.pumpWidget(_wrap(CanvasArea(
        slots: const [],
        canvasWidth: 400,
        canvasHeight: 300,
        onSlotCreated: (x, y, w, h) {
          createdX = x; createdY = y; createdW = w; createdH = h;
        },
      )));
      await tester.pumpAndSettle();

      // 模拟框选：pan start → pan update → pan end
      final canvas = find.byType(CanvasArea);
      final center = tester.getCenter(canvas);

      await tester.timedDragFrom(
        center,
        const Offset(100, 80),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      expect(createdX, isNotNull);
      expect(createdY, isNotNull);
      expect(createdW, isNotNull);
      expect(createdH, isNotNull);
      expect(createdW! > 20, isTrue);
      expect(createdH! > 20, isTrue);
    });
  });

  group('P2 SlotPainter', () {
    test('drawInfos 正确映射 Slot', () {
      final slot = DesignSlot(id: 's0', rect: [0, 0, 100, 80]);
      final info = SlotDrawInfo(slot: slot, rect: const Rect.fromLTWH(0, 0, 100, 80));
      expect(info.isSelected, false);
      expect(info.isHovered, false);
      expect(info.rect.width, 100);
    });
  });

  group('P2 PropertyPanel', () {
    testWidgets('无选中时显示空态', (tester) async {
      await tester.pumpWidget(_wrap(const PropertyPanel()));
      await tester.pumpAndSettle();
      expect(find.textContaining('在画布上选择一个 Slot'), findsOneWidget);
    });

    testWidgets('选中 Slot 时显示属性编辑器', (tester) async {
      final slot = DesignSlot(
        id: 'slot_0',
        rect: [10, 10, 300, 200],
        label: '我的Slot',
        component: DesignComponent(type: 'chart', config: {'title': 'Test'}),
      );

      await tester.pumpWidget(_wrap(PropertyPanel(selectedSlot: slot)));
      await tester.pumpAndSettle();

      expect(find.text('Slot 属性'), findsOneWidget);
      expect(find.text('位置与大小'), findsOneWidget);
      expect(find.text('绑定组件'), findsOneWidget);

      // 验证标签字段已填充
      final labelField = find.widgetWithText(TextField, '我的Slot');
      expect(labelField, findsOneWidget);
    });

    testWidgets('编辑属性触发回调', (tester) async {
      String? changedLabel;
      final slot = DesignSlot(id: 'slot_0', rect: [0, 0, 200, 100]);

      await tester.pumpWidget(_wrap(PropertyPanel(
        selectedSlot: slot,
        onSlotPropChanged: ({label, region, rect}) {
          changedLabel = label;
        },
      )));
      await tester.pumpAndSettle();

      // 修改标签
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '新标签');
      await tester.pumpAndSettle();

      expect(changedLabel, '新标签');
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
  });

  group('P2 DesignDocument 编排操作', () {
    test('创建文档并添加页面和 Slot', () {
      final doc = DesignDocument(pluginId: 'test', pluginName: '测试');

      // 添加页面
      doc.addPage(DesignPage(id: 'page_0', label: '首页'));
      expect(doc.pages.length, 1);
      expect(doc.pageCount, 1);

      // 添加 Slot
      doc.pages.first.addSlot(DesignSlot(
        id: 'slot_0',
        rect: [20, 20, 300, 200],
        label: '图表',
      ));
      expect(doc.slotCount, 1);

      // 绑定组件
      doc.pages.first.slots.first.component = DesignComponent(
        type: 'chart',
        config: {'title': '销售数据'},
      );
      expect(doc.pages.first.slots.first.component?.type, 'chart');
    });

    test('touch 更新 updatedAt', () {
      final doc = DesignDocument(pluginId: 'test', pluginName: '测试');
      final before = doc.updatedAt;
      // 确保时间推进（毫秒级差异）
      doc.touch();
      expect(doc.updatedAt.millisecondsSinceEpoch >= before.millisecondsSinceEpoch, isTrue);
    });

    test('布局预设切换', () {
      final page = DesignPage(id: 'p0', label: '首页');
      expect(page.layoutPreset, LayoutPreset.grid); // 默认

      page.layoutPreset = LayoutPreset.fullscreen;
      expect(page.layoutPreset, LayoutPreset.fullscreen);

      page.layoutPreset = LayoutPreset.dock;
      expect(page.layoutPreset, LayoutPreset.dock);
    });
  });
}

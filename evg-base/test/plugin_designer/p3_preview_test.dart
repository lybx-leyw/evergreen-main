/// P3 热加载实时预览测试 — PreviewPanel + AutoCompileService。
///
/// A-P3 升级：PreviewPanel 接入真实 [CompositeView] 渲染，故预览相关测试
/// 需在 [ProviderScope] 内运行，并断言"真实渲染管线"行为（页面 Tab、无崩溃），
/// 不再断言 mock 卡片文本。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/auto_compile_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/view/preview_panel.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/widgets/composite_preview_frame.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        // 真实渲染管线（LayerThemeScope）读取 dataOrchestratorProvider，
        // 测试环境需注入一个空实例（与 m2_module_binding_test 同模式）。
        dataOrchestratorProvider.overrideWith((ref) => DataOrchestrator()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  // ═══════════════════════════════════════════════════════════
  // AutoCompileService 单元测试
  // ═══════════════════════════════════════════════════════════
  group('P3 AutoCompileService', () {
    test('初始状态为 idle', () {
      final service = AutoCompileService('test_plugins/');
      expect(service.status, CompileStatus.idle);
      service.dispose();
    });

    test('compileScript 触发 debounce 和状态变化', () async {
      final service = AutoCompileService('test_plugins/');
      final events = <CompileEvent>[];

      final sub = service.onEvent.listen(events.add);

      // 编译不存在的脚本（预期失败）
      final result = await service.compileNow('test-plugin', 'nonexistent.py');
      expect(result.status, CompileStatus.failed);
      expect(result.error, isNotNull);
      expect(result.error, contains('不存在'));

      // compileNow 直接执行，应至少有一个失败事件
      expect(events.isNotEmpty, isTrue);

      await sub.cancel();
      service.dispose();
    });

    test('onEvent stream 正确广播', () async {
      final service = AutoCompileService('test_plugins/');
      final events = <CompileEvent>[];

      final sub = service.onEvent.listen(events.add);
      final result = await service.compileNow('p3-test', 'nonexistent.py');
      expect(result.status, CompileStatus.failed);

      // stream 应收到事件
      expect(events.isNotEmpty, isTrue);

      await sub.cancel();
      service.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════
  // PreviewPanel Widget 测试
  // ═══════════════════════════════════════════════════════════
  group('P3 PreviewPanel', () {
    testWidgets('空文档显示空态提示', (tester) async {
      await tester.pumpWidget(_wrap(const PreviewPanel()));
      await tester.pumpAndSettle();

      expect(find.text('请先创建或加载设计文档'), findsOneWidget);
    });

    testWidgets('无页面文档显示空态提示', (tester) async {
      final doc = DesignDocument(pluginId: 'empty');
      await tester.pumpWidget(_wrap(PreviewPanel(document: doc)));
      await tester.pumpAndSettle();

      expect(find.text('暂无页面，请在画布中添加页面'), findsOneWidget);
    });

    testWidgets('单页面单 Slot 真实渲染（WYSIWYG）', (tester) async {
      final doc = DesignDocument(
        pluginId: 'preview-test',
        pluginName: '测试插件',
        pages: [
          DesignPage(
            id: 'page_0',
            label: '首页',
            layoutPreset: LayoutPreset.grid,
            slots: [
              DesignSlot(
                id: 'slot_0',
                region: SlotRegion.center,
                label: '图表区',
                component: DesignComponent(
                  type: 'chart',
                  config: {'title': '销售数据'},
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(PreviewPanel(document: doc)));
      await tester.pumpAndSettle();

      // 预览头部（真实渲染入口已接入）
      expect(find.text('实时预览'), findsOneWidget);
      // 页面 Tab 由真实 CompositeView 渲染
      expect(find.text('首页'), findsWidgets);
      // 真实渲染管线未崩溃（无 ErrorWidget）
      expect(find.byType(CompositePreviewFrame), findsOneWidget);
    });

    testWidgets('多 Slot 真实渲染不崩溃', (tester) async {
      final doc = DesignDocument(
        pluginId: 'multi-slot',
        pages: [
          DesignPage(
            id: 'page_0',
            label: '多Slot页',
            slots: [
              DesignSlot(
                id: 'bottom_slot',
                region: SlotRegion.bottom,
                label: '底部',
                component: DesignComponent(type: 'button'),
              ),
              DesignSlot(
                id: 'top_slot',
                region: SlotRegion.top,
                label: '顶部',
                component: DesignComponent(type: 'card-list'),
              ),
              DesignSlot(
                id: 'center_slot',
                region: SlotRegion.center,
                label: '中心',
                component: DesignComponent(type: 'chart'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(PreviewPanel(document: doc)));
      await tester.pumpAndSettle();

      // 页面 Tab 由真实 CompositeView 渲染
      expect(find.text('多Slot页'), findsWidgets);
      // 真实渲染管线未崩溃
      expect(find.byType(CompositePreviewFrame), findsOneWidget);
    });

    testWidgets('多页面支持真实 Tab 切换', (tester) async {
      final doc = DesignDocument(
        pluginId: 'multi-page',
        pages: [
          DesignPage(id: 'page_0', label: '第1页', slots: [
            DesignSlot(id: 's0', region: SlotRegion.center,
                component: DesignComponent(type: 'chart')),
          ]),
          DesignPage(id: 'page_1', label: '第2页', slots: [
            DesignSlot(id: 's1', region: SlotRegion.center,
                component: DesignComponent(type: 'data-table')),
          ]),
        ],
      );

      await tester.pumpWidget(_wrap(PreviewPanel(document: doc)));
      await tester.pumpAndSettle();

      // 两页 Tab 均由真实 CompositeView 渲染
      expect(find.text('第1页'), findsWidgets);
      expect(find.text('第2页'), findsWidgets);

      // 点击第2页 Tab（真实 TabBar）
      await tester.tap(find.text('第2页'));
      await tester.pumpAndSettle();

      // 切换后真实渲染第2页，未崩溃
      expect(find.byType(CompositePreviewFrame), findsOneWidget);
    });

    testWidgets('空 Slot 被净化过滤，页面仍可渲染', (tester) async {
      final doc = DesignDocument(
        pluginId: 'empty-slot',
        pages: [
          DesignPage(id: 'page_0', label: '空Slot页', slots: [
            DesignSlot(id: 's0', region: SlotRegion.center),
          ]),
        ],
      );

      await tester.pumpWidget(_wrap(PreviewPanel(document: doc)));
      await tester.pumpAndSettle();

      // 空 Slot 被过滤，页面正常渲染（不崩溃）
      expect(find.text('空Slot页'), findsWidgets);
      expect(find.byType(CompositePreviewFrame), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // DesignToManifest 编译器扩展测试（P3 相关的编译正确性）
  // ═══════════════════════════════════════════════════════════
  group('P3 DesignToManifest 编译完整性', () {
    test('含 config 的组件正确编译', () {
      final doc = DesignDocument(
        pluginId: 'cfg-test',
        pluginName: '配置测试',
        icon: 'bar_chart',
        description: '测试描述',
        route: '/test',
        pages: [
          DesignPage(
            id: 'p0',
            label: '配置页',
            slots: [
              DesignSlot(
                id: 's0',
                region: SlotRegion.center,
                label: '图表区',
                component: DesignComponent(
                  type: 'chart',
                  config: {'title': '测试', 'type': 'bar', 'dataSource': 'test-api'},
                ),
              ),
            ],
          ),
        ],
      );

      final manifest = DesignToManifest.compile(doc);

      expect(manifest['schemaVersion'], '2.0');
      expect(manifest['id'], 'cfg-test');
      expect(manifest['icon'], 'bar_chart');
      expect(manifest['description'], '测试描述');
      expect(manifest['route'], '/test');

      final pages = manifest['pages'] as List;
      expect(pages.length, 1);
      final page = pages[0] as Map<String, dynamic>;
      final slots = page['layout']['slots'] as Map<String, dynamic>;
      final comp = slots['s0']['component'] as Map<String, dynamic>;

      expect(comp['type'], 'chart');
      expect(comp['config']['title'], '测试');
      expect(comp['config']['type'], 'bar');
    });

    test('多页面多 Slot 编译结构正确', () {
      final doc = DesignDocument(
        pluginId: 'multi-test',
        pages: [
          DesignPage(id: 'p0', label: '首页', slots: [
            DesignSlot(id: 's0', region: SlotRegion.top,
                component: DesignComponent(type: 'card-list')),
            DesignSlot(id: 's1', region: SlotRegion.center,
                component: DesignComponent(type: 'chart')),
          ]),
          DesignPage(id: 'p1', label: '详情', slots: [
            DesignSlot(id: 's2', region: SlotRegion.center,
                component: DesignComponent(type: 'data-table')),
          ]),
        ],
      );

      final manifest = DesignToManifest.compile(doc);
      final pages = manifest['pages'] as List;

      expect(pages.length, 2);

      // 首页有2个Slot
      final page0Slots = (pages[0] as Map)['layout']['slots'] as Map;
      expect(page0Slots.length, 2);
      expect(page0Slots.containsKey('s0'), isTrue);
      expect(page0Slots.containsKey('s1'), isTrue);

      // 详情页有1个Slot
      final page1Slots = (pages[1] as Map)['layout']['slots'] as Map;
      expect(page1Slots.length, 1);
      expect(page1Slots.containsKey('s2'), isTrue);
    });
  });
}

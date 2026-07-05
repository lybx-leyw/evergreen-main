/// LayoutEngine 单元测试——mode/grid/zoom/panels 组合。
///
/// Sprint 3 最低覆盖要求：LayoutEngine mode/grid/zoom/panels 组合。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/shared/layout_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造最小 LayoutDescriptor。
LayoutDescriptor _layout({
  String mode = 'scroll',
  GridOptions? grid,
  bool zoomEnabled = false,
  List<String> drawers = const [],
  SearchDescriptor? search,
  List<PanelDescriptor> panels = const [],
}) {
  return LayoutDescriptor(
    mode: mode,
    grid: grid,
    zoom: ZoomDescriptor(enabled: zoomEnabled),
    drawers: drawers,
    search: search,
    panels: panels,
  );
}

/// 包裹 [LayoutEngine] 的标准测试脚手架。
///
/// [Scaffold] 提供 [Material] 祖先节点，从而满足 [TabBar] 等
/// Material 组件的要求（[PanelLayout] 内部使用了 [TabBar]）。
Widget _wrap(LayoutDescriptor layout, Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: LayoutEngine(layout: layout, child: child),
    ),
  );
}

/// 测试用最小子组件。
class _TestChild extends StatelessWidget {
  const _TestChild();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 100, height: 100);
  }
}

void main() {
  group('LayoutEngine — mode（scroll/fit/unknown）', () {
    testWidgets('mode="scroll" → SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap(_layout(mode: 'scroll'), const _TestChild()));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('mode="fit" → FittedBox', (tester) async {
      await tester.pumpWidget(_wrap(_layout(mode: 'fit'), const _TestChild()));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('mode="" → 静默忽略', (tester) async {
      await tester.pumpWidget(_wrap(_layout(mode: ''), const _TestChild()));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('mode="unknown" → 静默忽略', (tester) async {
      await tester.pumpWidget(_wrap(_layout(mode: 'unknown'), const _TestChild()));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — grid（网格布局）', () {
    testWidgets('grid.columns=2', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(grid: const GridOptions(columns: 2)), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('grid.columns=4', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(grid: const GridOptions(columns: 4)), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('grid=null → 无 GridLayout', (tester) async {
      await tester.pumpWidget(_wrap(_layout(grid: null), const _TestChild()));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — zoom（缩放）', () {
    testWidgets('zoom.enabled=true', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(zoomEnabled: true), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('zoom.enabled=false', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(zoomEnabled: false), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — panels（多面板）', () {
    testWidgets('panels 非空 → PanelLayout', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(panels: const [
          PanelDescriptor(id: 'tab1', label: 'Tab 1', path: '/tab1'),
          PanelDescriptor(id: 'tab2', label: 'Tab 2', path: '/tab2'),
        ]),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('panels 为空 → 无 PanelLayout', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(panels: const []), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — 组合', () {
    testWidgets('全组合：scroll+grid+zoom+panels', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(
          mode: 'scroll',
          grid: const GridOptions(columns: 3),
          zoomEnabled: true,
          panels: const [
            PanelDescriptor(id: 'main', label: 'Main', path: '/main'),
          ],
        ),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('fit+grid+search 组合', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(
          mode: 'fit',
          grid: const GridOptions(columns: 2),
          search: const SearchDescriptor(enabled: true, placeholder: '搜索...'),
        ),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });
}

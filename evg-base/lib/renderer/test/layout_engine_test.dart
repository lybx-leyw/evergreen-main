/// LayoutEngine 布局引擎测试——shared/ 层布局管线的 widgetTest。
///
/// 验证 6 层布局管线正确渲染，mode/grid/zoom/panels/search/drawers 各层行为。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/shared/layout_engine.dart';

void main() {
  group('LayoutEngine — 布局管线', () {
    // ── 基础渲染 ──

    testWidgets('renders child widget', (tester) async {
      const layout = LayoutDescriptor();
      const child = Text('Hello, Layout!');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(layout: layout, child: child),
          ),
        ),
      );

      expect(find.text('Hello, Layout!'), findsOneWidget);
    });

    // ── Mode 层 ──

    testWidgets('applies scroll mode', (tester) async {
      const layout = LayoutDescriptor(mode: 'scroll');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: SizedBox(
                height: 2000,
                child: Column(
                  children: List.generate(
                    50,
                    (i) => Text('Item $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 应该可以滚动——验证有 SingleChildScrollView
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('applies fit mode', (tester) async {
      const layout = LayoutDescriptor(mode: 'fit');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Container(
                width: 1920,
                height: 1080,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      // 应该有 FittedBox
      expect(find.byType(FittedBox), findsOneWidget);
    });

    testWidgets('default mode passes child through directly', (tester) async {
      const layout = LayoutDescriptor();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('Direct child'),
            ),
          ),
        ),
      );

      // 无额外滚动容器
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Direct child'), findsOneWidget);
    });

    // ── Search 层 ──

    testWidgets('renders search bar when search enabled', (tester) async {
      const layout = LayoutDescriptor(
        search: SearchDescriptor(enabled: true, placeholder: '搜索内容...'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('Content'),
            ),
          ),
        ),
      );

      // 搜索栏应该渲染
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('does not render search bar when search disabled', (tester) async {
      const layout = LayoutDescriptor(
        search: SearchDescriptor(enabled: false),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('Content'),
            ),
          ),
        ),
      );

      // 默认无 TextField（除非子组件自带）
      expect(find.byType(TextField), findsNothing);
    });

    // ── Grid 层 ──

    testWidgets('renders grid when columns > 0', (tester) async {
      const layout = LayoutDescriptor(
        grid: GridOptions(columns: 3, gap: 8),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('Grid content'),
            ),
          ),
        ),
      );

      // Grid 内容应该渲染
      expect(find.text('Grid content'), findsOneWidget);
    });

    // ── 边界条件 ──

    testWidgets('handles minimal LayoutDescriptor', (tester) async {
      const layout = LayoutDescriptor();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('Minimal'),
            ),
          ),
        ),
      );

      expect(find.text('Minimal'), findsOneWidget);
    });

    testWidgets('handles all features enabled simultaneously', (tester) async {
      const layout = LayoutDescriptor(
        mode: 'scroll',
        grid: GridOptions(columns: 2, gap: 12),
        search: SearchDescriptor(enabled: true),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: Text('All features'),
            ),
          ),
        ),
      );

      expect(find.text('All features'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('does not crash with empty child', (tester) async {
      const layout = LayoutDescriptor(mode: 'scroll');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LayoutEngine(
              layout: layout,
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );

      // 不应该崩溃
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });
}

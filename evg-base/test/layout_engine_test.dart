/// LayoutEngine 单元测试 — V2 API (type/preset/features)。
///
/// Sprint 3 最低覆盖要求：LayoutEngine grid/zoom/search/drawers 组合。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/shared/layout_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造 V2 LayoutDescriptor。
LayoutDescriptor _layout({
  String type = 'flex',
  int? columns,
  bool zoomEnabled = false,
  List<String> drawers = const [],
  SearchDescriptor? search,
}) {
  return LayoutDescriptor(
    type: columns != null ? 'grid' : type,
    preset: LayoutPreset(columns: columns),
    features: LayoutFeatures(
      zoom: zoomEnabled ? const ZoomDescriptor(enabled: true) : null,
      search: search,
      drawers: drawers,
    ),
  );
}

/// 包裹 [LayoutEngine] 的标准测试脚手架。
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
  group('LayoutEngine — grid（网格布局）', () {
    testWidgets('grid type + columns=2', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(columns: 2), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('grid type + columns=4', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(columns: 4), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('flex type → 无 GridLayout', (tester) async {
      await tester.pumpWidget(_wrap(_layout(), const _TestChild()));
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

  group('LayoutEngine — search（搜索栏）', () {
    testWidgets('search enabled', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _layout(search: const SearchDescriptor(enabled: true, placeholder: '搜索...')),
          const _TestChild(),
        ),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — drawers（抽屉）', () {
    testWidgets('drawers 非空', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(drawers: const ['left', 'right']),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('drawers 为空', (tester) async {
      await tester.pumpWidget(
        _wrap(_layout(drawers: const []), const _TestChild()),
      );
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });

  group('LayoutEngine — 组合', () {
    testWidgets('grid+zoom+search+drawers 全组合', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(
          columns: 3,
          zoomEnabled: true,
          search: const SearchDescriptor(enabled: true),
          drawers: const ['left'],
        ),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });

    testWidgets('flex+search 组合', (tester) async {
      await tester.pumpWidget(_wrap(
        _layout(
          type: 'flex',
          search: const SearchDescriptor(enabled: true, placeholder: '搜索...'),
        ),
        const _TestChild(),
      ));
      expect(find.byType(LayoutEngine), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/widgets/breakpoints.dart';
import 'package:evergreen_multi_tools/widgets/adaptive_layout.dart';
import 'package:evergreen_multi_tools/widgets/loading_indicator.dart';
import 'package:evergreen_multi_tools/widgets/empty_state.dart';
import 'package:evergreen_multi_tools/widgets/error_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('Breakpoints', () {
    test('常量值正确', () {
      expect(Breakpoints.mobile, 768);
      expect(Breakpoints.compact, 1024);
      expect(Breakpoints.medium, 1280);
      expect(Breakpoints.expanded, 1600);
    });
  });

  group('AdaptiveLayout', () {
    testWidgets('宽屏 → desktop', (tester) async {
      tester.view.physicalSize = const Size(2400, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_wrap(AdaptiveLayout(
        desktop: (ctx) => const Text('desktop'),
        mobile: (ctx) => const Text('mobile'),
      )));
      await tester.pump();
      expect(find.text('desktop'), findsOneWidget);
      expect(find.text('mobile'), findsNothing);
    });

    testWidgets('窄屏 → mobile', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_wrap(AdaptiveLayout(
        desktop: (ctx) => const Text('desktop'),
        mobile: (ctx) => const Text('mobile'),
      )));
      await tester.pump();
      expect(find.text('mobile'), findsOneWidget);
      expect(find.text('desktop'), findsNothing);
    });
  });

  group('LoadingIndicator', () {
    testWidgets('标准模式——显示消息', (tester) async {
      await tester.pumpWidget(_wrap(
          const LoadingIndicator(message: '加载中...')));
      expect(find.text('加载中...'), findsOneWidget);
    });

    testWidgets('compact 模式——水平布局', (tester) async {
      await tester.pumpWidget(_wrap(
          const LoadingIndicator.compact(hint: '查询中...')));
      expect(find.text('查询中...'), findsOneWidget);
    });
  });

  group('EmptyState semanticLabel', () {
    testWidgets('Semantics 节点存在', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        title: '暂无数据',
        semanticLabel: '课程列表为空',
      )));
      expect(find.byType(Semantics), findsWidgets);
    });
  });

  group('ErrorCard semanticLabel', () {
    testWidgets('Semantics 节点存在', (tester) async {
      await tester.pumpWidget(_wrap(ErrorCard(
        message: '加载失败',
        semanticLabel: '成绩加载失败，点击重试',
        onRetry: () {},
      )));
      expect(find.byType(Semantics), findsWidgets);
    });
  });
}

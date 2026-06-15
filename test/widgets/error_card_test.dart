import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/widgets/error_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('ErrorCard 展示 message', (tester) async {
    await tester.pumpWidget(_wrap(
      const ErrorCard(message: '测试错误消息'),
    ));

    expect(find.text('测试错误消息'), findsOneWidget);
  });

  testWidgets('ErrorCard 展示 detail', (tester) async {
    await tester.pumpWidget(_wrap(
      const ErrorCard(
        message: '标题',
        detail: '技术细节：连接超时',
      ),
    ));

    expect(find.text('技术细节：连接超时'), findsOneWidget);
  });

  testWidgets('ErrorCard 展示 hint（恢复建议）', (tester) async {
    await tester.pumpWidget(_wrap(
      const ErrorCard(
        message: '加载失败',
        hint: '请检查网络连接后重试',
      ),
    ));

    expect(find.text('请检查网络连接后重试'), findsOneWidget);
    // Verify the lightbulb icon is present
    expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
  });

  testWidgets('ErrorCard 展示 retry 按钮', (tester) async {
    await tester.pumpWidget(_wrap(
      ErrorCard(
        message: '加载失败',
        onRetry: () {},
      ),
    ));

    expect(find.text('重试'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('ErrorCard retry 按钮触发回调', (tester) async {
    var called = false;
    await tester.pumpWidget(_wrap(
      ErrorCard(
        message: '加载失败',
        onRetry: () => called = true,
      ),
    ));

    await tester.tap(find.text('重试'));
    expect(called, isTrue);
  });

  testWidgets('ErrorCard 无 retry 回调时无按钮', (tester) async {
    await tester.pumpWidget(_wrap(
      const ErrorCard(message: '加载失败'),
    ));

    expect(find.text('重试'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}

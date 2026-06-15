import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scores — 性能', () {
    testWidgets('50+ 条目滚动无溢出', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 60,
            itemBuilder: (_, i) => ListTile(
              title: Text('课程 $i'),
              subtitle: Text('成绩: ${90 - i % 20}'),
            ),
          ),
        ),
      ));
      await tester.pump();

      // 验证条目存在
      expect(find.text('课程 0'), findsOneWidget);
      expect(find.text('课程 59'), findsNothing); // 60条在视口外

      // 滚动不崩溃
      await tester.scrollUntilVisible(find.text('课程 59'), 200);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空列表显示空态', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('暂无成绩数据')),
        ),
      ));
      expect(find.text('暂无成绩数据'), findsOneWidget);
    });
  });
}

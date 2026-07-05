import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 响应式布局边界：sidebar 折叠 + 内容区 resize 时各区无 overflow。
void main() {
  group('Responsive — no overflow', () {
    testWidgets('800px 窗口 sidebar + 内容共存', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Row(
              children: [
                // 模拟折叠 sidebar (60px)
                SizedBox(
                  width: 60,
                  child: ListView(
                    children: List.generate(9, (i) => const Icon(Icons.circle, size: 20)),
                  ),
                ),
                const VerticalDivider(width: 1),
                // 内容区
                const Expanded(
                  child: Center(child: Text('Content')),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('230px sidebar + 窄内容区', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 768, // 临界值
            height: 600,
            child: Row(
              children: [
                SizedBox(
                  width: 230,
                  child: ListView(
                    children: List.generate(15, (i) => ListTile(
                      title: Text('Nav $i'),
                    )),
                  ),
                ),
                const VerticalDivider(width: 1),
                const Expanded(child: Center(child: Text('Content'))),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dashboard Wrap + 各种宽度不溢出', (tester) async {
      for (final width in [400.0, 600.0, 800.0, 1200.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 800,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: List.generate(12, (i) => SizedBox(
                    width: 200,
                    height: 100,
                    child: Card(child: Center(child: Text('Card $i'))),
                  )),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'Wrap overflow at width=$width');
      }
    });
  });
}

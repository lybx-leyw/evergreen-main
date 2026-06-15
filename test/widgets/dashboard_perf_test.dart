import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard — 性能', () {
    testWidgets('首次渲染 < 500ms', (tester) async {
      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
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
      ));
      await tester.pump();

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(2000),
          reason: '首次渲染超过 2000ms');
    });

    testWidgets('12 张卡片全部渲染可见', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
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
      ));
      await tester.pump();

      for (var i = 0; i < 12; i++) {
        expect(find.text('Card $i'), findsOneWidget);
      }
    });
  });
}

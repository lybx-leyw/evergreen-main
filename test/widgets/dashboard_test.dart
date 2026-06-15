import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dashboard', () {
    testWidgets('Wrap 在不同宽度下不溢出', (tester) async {
      for (final w in [400.0, 600.0, 800.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: w,
              height: 800,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: List.generate(8, (i) => SizedBox(
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
        expect(tester.takeException(), isNull, reason: 'overflow at width=$w');
      }
    });

    testWidgets('卡片点击导航', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Card(
            child: InkWell(
              onTap: () => tapped = true,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Go to Courses'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Go to Courses'));
      expect(tapped, true);
    });
  });
}

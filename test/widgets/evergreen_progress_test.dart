import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/widgets/evergreen_progress.dart';

void main() {
  group('EvergreenProgress', () {
    testWidgets('不确定模式渲染', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: EvergreenProgress())),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('确定模式带 value', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: EvergreenProgress(value: 0.7))),
      ));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('带 label 文本', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: EvergreenProgress(label: '加载中...'))),
      ));
      expect(find.text('加载中...'), findsOneWidget);
    });

    testWidgets('主题色跟随', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        home: const Scaffold(body: Center(child: EvergreenProgress())),
      ));
      expect(find.byType(EvergreenProgress), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

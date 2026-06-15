import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/plan/widgets/plan_table.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Map<String, Map<int, String>> _emptySchedule() {
  const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  final s = <String, Map<int, String>>{};
  for (final d in days) {
    s[d] = {for (var h = 7; h <= 24; h++) h: ''};
    s[d]![1] = '';
  }
  return s;
}

Map<String, Map<int, int>> _emptyColors() {
  const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  final c = <String, Map<int, int>>{};
  for (final d in days) {
    c[d] = {for (var h = 7; h <= 24; h++) h: 0};
    c[d]![1] = 0;
  }
  return c;
}

void main() {
  group('PlanTable rendering', () {
    testWidgets('renders headers', (tester) async {
      await tester.pumpWidget(_wrap(PlanTable(schedule: _emptySchedule(), colors: _emptyColors())));
      expect(find.text('周一'), findsOneWidget);
      expect(find.text('7:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('PlanTable edit', () {
    testWidgets('long press opens dialog', (tester) async {
      final s = _emptySchedule(); s['周二']![10] = 'edit_me';
      await tester.pumpWidget(_wrap(PlanTable(schedule: s, colors: _emptyColors())));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('edit_me').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('PlanTable selection', () {
    testWidgets('tap shows toolbar', (tester) async {
      final s = _emptySchedule(); s['周一']![9] = 'test';
      await tester.pumpWidget(_wrap(PlanTable(schedule: s, colors: _emptyColors(), onCellsChanged: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test').last);
      await tester.pumpAndSettle();
      expect(find.text('填充'), findsOneWidget);
      expect(find.text('涂色'), findsOneWidget);
    });
  });

  group('PlanTable batch fill', () {
    testWidgets('fill calls onCellsChanged', (tester) async {
      Map<String, Map<int, String>>? captured;
      final s = _emptySchedule(); s['周三']![15] = 'A'; s['周三']![16] = 'B';
      await tester.pumpWidget(_wrap(PlanTable(schedule: s, colors: _emptyColors(), onCellsChanged: (c) => captured = c)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').last); await tester.pumpAndSettle();
      await tester.tap(find.text('B').last); await tester.pumpAndSettle();
      await tester.tap(find.text('填充').last); await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), '统一');
      await tester.tap(find.text('填充').last); await tester.pumpAndSettle();
      expect(captured!['周三']?[15], '统一');
      expect(captured!['周三']?[16], '统一');
    });
  });

  group('PlanTable color', () {
    testWidgets('color button opens picker', skip: true, (tester) async {
      final s = _emptySchedule(); s['周四']![10] = 'X';
      await tester.pumpWidget(_wrap(PlanTable(schedule: s, colors: _emptyColors(), onColorsChanged: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('X').last); await tester.pumpAndSettle();
      expect(find.text('涂色'), findsOneWidget);
      await tester.tap(find.text('涂色').last); await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });
}

import 'package:evergreen_base/renderer/components/shared/widgets/calendar_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CalendarWidget 基本渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CalendarWidget(
            initialMonth: null, // default = now
            events: [],
          ),
        ),
      ),
    );
    // 多帧等待 GridView 完成布局
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 当前月份标题存在
    expect(find.textContaining('年'), findsOneWidget);
    // 星期表头存在
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });

  testWidgets('右箭头切换到下月', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarWidget(
            initialMonth: DateTime(2026, 7, 1),
            events: const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('2026年7月'), findsOneWidget);

    // 点击右箭头
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('2026年8月'), findsOneWidget);
  });
}

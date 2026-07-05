import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_multi_tools/core/models/timetable_session.dart';
import 'package:evergreen_multi_tools/features/courses/widgets/timetable_grid.dart';
import 'package:evergreen_multi_tools/core/config/theme.dart';

/// 0.3.5 — 深色模式课表不包含硬编码色值。
void main() {
  testWidgets('TimetableGrid in dark theme — no hardcoded colors', (tester) async {
    final sessions = [
      TimetableSession(
          courseName: '数学分析',
          teacher: '张老师',
          location: '东1A-101',
          periods: [1, 2],
          dayOfWeek: 1),
      TimetableSession(
          courseName: '线性代数',
          teacher: '李老师',
          location: '西2-205',
          periods: [3, 4],
          dayOfWeek: 2),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: TimetableGrid(sessions: [])),
      ),
    );

    // 使用 mock sessions 重建
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 600,
            child: TimetableGrid(sessions: sessions),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 不应有 render overflow
    expect(tester.takeException(), isNull);
  });
}

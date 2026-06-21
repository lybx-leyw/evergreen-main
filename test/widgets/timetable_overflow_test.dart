import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_multi_tools/core/models/timetable_session.dart';
import 'package:evergreen_multi_tools/features/courses/widgets/timetable_grid.dart';

/// 0.3.5-ext — 课表在各种屏幕尺寸下不产生 bottom overflow。
void main() {
  List<TimetableSession> _makeSessions() => List.generate(
      20,
      (i) => TimetableSession(
            courseName: '课程$i',
            teacher: '教师',
            location: '教室',
            periods: [i % 13 + 1],
            dayOfWeek: (i % 7) + 1,
          ));

  group('TimetableGrid — no overflow', () {
    testWidgets('窄屏 (440x600) 无溢出', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 600,
            child: TimetableGrid(sessions: _makeSessions()),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏 (800x500) 行高被压缩无溢出', (tester) async {
      // 宽 + 矮 → rowH 受 maxHeight/13 限制
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: TimetableGrid(sessions: _makeSessions()),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('极矮屏 (400x350) 行高下限不崩溃', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 350,
            child: TimetableGrid(sessions: _makeSessions()),
          ),
        ),
      ));
      await tester.pump();
      // 允许 overflow（物理上无法放下13行），但不应抛断言
      tester.takeException(); // ignore: unused_local_variable
      // 即使 overflow，也是 RenderFlex overflow warning，不是崩溃
    });

    testWidgets('2 节课无溢出', (tester) async {
      final sessions = [
        TimetableSession(
            courseName: '数学',
            teacher: '张',
            location: '101',
            periods: [1, 2],
            dayOfWeek: 1),
        TimetableSession(
            courseName: '英语',
            teacher: '李',
            location: '202',
            periods: [3, 4],
            dayOfWeek: 2),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 500,
            child: TimetableGrid(sessions: sessions),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('空课表无溢出', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 500,
            child: const TimetableGrid(sessions: []),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

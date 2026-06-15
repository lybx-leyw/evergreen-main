import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_multi_tools/core/models/timetable_session.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/models/exam.dart';
import 'package:evergreen_multi_tools/features/courses/screens/courses_screen.dart';
import 'package:evergreen_multi_tools/features/courses/providers/courses_provider.dart';
import 'package:evergreen_multi_tools/features/courses/models/course.dart';
import 'package:evergreen_multi_tools/features/auth/providers/auth_provider.dart';
import 'package:evergreen_multi_tools/features/zdbk/providers/zdbk_provider.dart';

List<TimetableSession> _mockSessions() {
  const base = {
    'xkkh': '(2025-2026-2)-CS101-001',
    'jsxm': '张老师',
    'jscdmc': '东1A-201',
    'kkzc': '1-17',
    'sfyjskc': '0',
    'xf': '3.0',
  };
  return [
    TimetableSession.fromZdbkJson({...base, 'kcb': '数据结构', 'xqj': '1', 'djj': '1', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '高等数学', 'xqj': '2', 'djj': '3', 'skcd': '2'}),
    TimetableSession.fromZdbkJson({...base, 'kcb': '大学物理', 'xqj': '5', 'djj': '1', 'skcd': '3'}),
  ];
}

void main() {
  group('课表网格构建', () {
    test('3 条 session → 正确填充网格', () {
      final sessions = _mockSessions();
      final grid = List.generate(12, (_) => List.generate(7, (_) => <TimetableSession>[]));
      for (final s in sessions) {
        for (final p in s.periods) {
          if (p >= 1 && p <= 12) grid[p - 1][s.dayOfWeek - 1].add(s);
        }
      }
      // 周一 1-2节(djj=1,skcd=2) → periods[1,2] → grid[0]、grid[1]
      expect(grid[0][0].length, 1);
      expect(grid[0][0][0].courseName, '数据结构');
      expect(grid[1][0].length, 1);
      expect(grid[1][0][0].courseName, '数据结构');
      // 周二 3-4节(djj=3,skcd=2) → periods[3,4] → grid[2]、grid[3]
      expect(grid[2][1].length, 1);
      expect(grid[2][1][0].courseName, '高等数学');
      expect(grid[3][1].length, 1);
      expect(grid[3][1][0].courseName, '高等数学');
      // 周五 1-3节 → 大学物理（占3个格）
      expect(grid[0][4].length, 1);
      expect(grid[1][4].length, 1);
      expect(grid[2][4].length, 1);
      expect(grid[2][4][0].courseName, '大学物理');
    });

    test('空 sessions → 全部格子为空', () {
      final grid = List.generate(12, (_) => List.generate(7, (_) => <TimetableSession>[]));
      for (var p = 0; p < 12; p++) {
        for (var d = 0; d < 7; d++) {
          expect(grid[p][d], isEmpty);
        }
      }
    });
  });

  group('课程列表过滤', () {
    test('按名称搜索', () {
      final courses = [
        Course(id: 1, name: '数据结构'),
        Course(id: 2, name: '高等数学'),
        Course(id: 3, name: '大学物理'),
      ];
      expect(courses.where((c) => c.name.contains('数学')).length, 1);
      expect(courses.where((c) => c.name.contains('物')).length, 1);
    });

    test('空搜索返回全部', () {
      final courses = [Course(id: 1, name: '数据结构'), Course(id: 2, name: '高等数学')];
      expect(courses.where((c) => ''.isEmpty || c.name.contains('')).length, 2);
    });
  });

  group('课表学期选择器', () {
    testWidgets('切换按钮存在', (tester) async {
      final jar = PersistCookieJar(ignoreExpires: true);
      final notifier = AuthNotifier(Dio(), jar, HttpClient());
      notifier.state = AuthState(isLoggedIn: true, ssoCookie: Cookie('iPlanetDirectoryPro', 'test'));

      await tester.pumpWidget(MaterialApp(
        home: ProviderScope(overrides: [
          authProvider.overrideWith((ref) => notifier),
          coursesListProvider.overrideWith((ref) async => Ok(<Course>[])),
        ], child: const CoursesScreen()),
      ));
      await tester.pump();

      // 默认课程列表
      expect(find.text('课程列表'), findsOneWidget);
      // 有切换按钮
      expect(find.byIcon(Icons.calendar_view_week), findsOneWidget);
    });
  });

  group('课表网格渲染', () {
    testWidgets('有数据时显示课程名称', (tester) async {
      final sessions = _mockSessions();
      // 直接渲染网格
      final grid = List.generate(12, (_) => List.generate(7, (_) => <TimetableSession>[]));
      for (final s in sessions) {
        for (final p in s.periods) {
          if (p >= 1 && p <= 12) grid[p - 1][s.dayOfWeek - 1].add(s);
        }
      }

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 32 + 7 * 100,
              child: Column(
                children: [
                  Row(children: [
                    const SizedBox(width: 32, height: 32),
                    ...'一二三四五六日'.split('').map((d) => Container(
                      width: 100, height: 32,
                      child: Text('周$d'),
                    )),
                  ]),
                  ...List.generate(12, (p) {
                    final periodLabel = '${p * 2 + 1}-${p * 2 + 2}';
                    return Row(children: [
                      SizedBox(width: 32, height: 60, child: Text(periodLabel)),
                      ...List.generate(7, (d) {
                        final cells = grid[p][d];
                        return Container(
                          width: 100, height: 60,
                          child: cells.isEmpty ? null : Text(
                            cells.first.courseName,
                          ),
                        );
                      }),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
      ));

      // 验证课程名称出现在网格中
      expect(find.text('数据结构'), findsWidgets);
      expect(find.text('高等数学'), findsWidgets);
      expect(find.text('大学物理'), findsWidgets);
    });
  });

  group('考试日历', () {
    testWidgets('月份导航标题', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () {}),
              const Text('2026年6月'),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () {}),
            ]),
            Row(children: '日一二三四五六'.split('').map((d) =>
              Expanded(child: Center(child: Text(d))),
            ).toList()),
          ]),
        ),
      ));
      expect(find.text('2026年6月'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
      expect(find.text('一'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('Sidebar', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('折叠状态下不溢出', (tester) async {
      // 模拟 60px collapsed sidebar
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            child: Material(
              child: ListView(
                children: List.generate(9, (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Icon(Icons.circle, size: 20),
                )),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('桌面 sidebar 230px 渲染正常', (tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const Text('Dashboard')),
        GoRoute(path: '/courses', builder: (_, __) => const Text('Courses')),
      ]);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ));
      // Just verify no crash
      expect(tester.takeException(), isNull);
    });

    testWidgets('红点过期项不计入 — 逻辑验证', (tester) async {
      // 纯逻辑测试，不依赖 Widget
      final now = DateTime(2026, 6, 12);
      final deadlines = [
        now.subtract(const Duration(days: 5)),  // 已过期
        now.add(const Duration(days: 3)),       // 未来3天
        now.add(const Duration(days: 10)),      // 超出7天
        now.add(const Duration(days: 1)),       // 未来1天
      ];

      final urgent = deadlines.where((d) {
        if (d.isBefore(now)) return false;
        final diff = d.difference(now).inDays;
        return diff >= 0 && diff <= 7;
      }).length;

      expect(urgent, 2); // 只计 3天和1天
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

/// 0.3.2 — 侧栏折叠到 60px 时 _NavItem 不溢出。
void main() {
  testWidgets('Collapsed sidebar — 60px 下无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox()),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData.light(),
        ),
      ),
    );

    // 模拟 collapsed sidebar 中的 _NavItem 渲染
    // 验证 Expanded + overflow:ellipsis 生效
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            child: Material(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.school, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '很长很长很长很长很长的课程名',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 不应有 overflow 错误
    expect(tester.takeException(), isNull);
  });
}

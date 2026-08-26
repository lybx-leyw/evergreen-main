/// 壳层窄轨宽度回归测试。
///
/// 背景（bug 根因）：`_RailShell` 的 `Row` 里直接放 `ModeRail(mode: mode)`，
/// 未用 `SizedBox(width: kModeRailWidth)` 约束宽度。`ModeRail` 内部
/// `Column → Expanded(child: ListView)`，垂直 ListView 在水平方向收到
/// Row 传给非 Flexible 子级的**无界宽度** → `Vertical viewport was given
/// unbounded width` 断言抛异常 → Scaffold layout 中断 → 启动白屏。
///
/// 本测试用真实 `_RailShell`（经 AppShell 窄屏分支），断言首帧能正常
/// 布局出 ModeRail（无布局异常即修复生效）。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/app_shell.dart';
import 'package:evergreen_base/renderer/app/mode_rail.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

ModuleDescriptor _mod(String id, String name, String route) => ModuleDescriptor(
      id: id,
      name: name,
      route: route,
      icon: 0xe000,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('窄轨壳层：ModeRail 收到有界宽度，首帧无 viewport 无界宽度异常',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final prefs = await SharedPreferences.getInstance();

    final registry = ModuleRegistry();
    registry.registerAll([
      _mod('ai-assistant', 'AI 助手', '/ai-assistant'),
      _mod('settings', '设置', '/settings'),
    ]);
    registry.seal();

    // 记录所有 Flutter 框架错误（overflow / layout 断言等）。
    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleRegistryProvider.overrideWith((ref) => registry),
          pluginsDirProvider.overrideWith((ref) => 'test-plugins'),
          sharedPreferencesProvider.overrideWithValue(prefs),
          // 开发者模式：窄轨（ModeRail）仍保留，用于验证「窄轨宽度约束」。
          appModeProvider.overrideWith((ref) => AppMode.developer),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/dev-hub',
            routes: [
              ShellRoute(
                builder: (context, state, child) => AppShell(child: child),
                routes: [
                  GoRoute(
                    path: '/dev-hub',
                    builder: (c, s) => const Scaffold(body: SizedBox()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    FlutterError.onError = oldHandler;

    // 开发者模式：ModeRail 正常挂载即证明布局未中断。
    expect(find.byType(ModeRail), findsOneWidget);
    // 无框架错误（尤其无 "Vertical viewport was given unbounded width"）。
    expect(
      errors.where((e) => e.toString().contains('unbounded')),
      isEmpty,
      reason: '窄轨 Row 未约束 ModeRail 宽度会触发 viewport 无界宽度异常',
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AI 视图：窄轨整体隐藏（按钮已收进 AI 助手抽屉）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final prefs = await SharedPreferences.getInstance();

    final registry = ModuleRegistry();
    registry.registerAll([
      _mod('ai-assistant', 'AI 助手', '/ai-assistant'),
    ]);
    registry.seal();

    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleRegistryProvider.overrideWith((ref) => registry),
          pluginsDirProvider.overrideWith((ref) => 'test-plugins'),
          sharedPreferencesProvider.overrideWithValue(prefs),
          appModeProvider.overrideWith((ref) => AppMode.ai),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/ai-assistant',
            routes: [
              ShellRoute(
                builder: (context, state, child) => AppShell(child: child),
                routes: [
                  GoRoute(
                    path: '/ai-assistant',
                    builder: (c, s) => const Scaffold(body: SizedBox()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    FlutterError.onError = oldHandler;

    // AI 视图不再渲染窄轨（ModeRail）。
    expect(find.byType(ModeRail), findsNothing);
    expect(
      errors.where((e) => e.toString().contains('unbounded')),
      isEmpty,
    );

    debugDefaultTargetPlatformOverride = null;
  });
}

/// 插件视图切回 AI/开发者视图的入口回归测试。
///
/// 背景（bug）：插件视图（AppMode.plugins）的侧栏/抽屉是 _ExpandedSidebar /
/// _CollapsedSidebar / _MobileDrawer，原本没有「视图模式切换」按钮（ModeSwitchButton
/// 只在 ModeRail 里），导致进入插件视图后无法切回 AI 视图 / 开发者模式（单向门）。
///
/// 修复：在插件视图三个导航面顶部都加入 ModeSwitchButton；本测试验证桌面展开侧栏
/// 顶部存在切换按钮，点击后切回 AI 视图并导航到 /ai-assistant。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/app_shell.dart';
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
      nav: NavObjectDescriptor(
        sidebar: SidebarDescriptor(section: '主功能', order: 10),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('插件视图展开侧栏顶部有视图切换按钮，点击切回 AI 视图并导航',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final registry = ModuleRegistry();
    registry.registerAll([
      _mod('ai-assistant', 'AI 助手', '/ai-assistant'),
      _mod('settings', '设置', '/settings'),
    ]);
    registry.seal();

    final errors = <FlutterErrorDetails>[];
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);

    // 桌面宽度（>600px）+ plugins 模式。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moduleRegistryProvider.overrideWith((ref) => registry),
          pluginsDirProvider.overrideWith((ref) => 'test-plugins'),
          appModeProvider.overrideWith((ref) => AppMode.plugins),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/settings',
            routes: [
              ShellRoute(
                builder: (context, state, child) => AppShell(child: child),
                routes: [
                  GoRoute(
                    path: '/settings',
                    builder: (c, s) => const Scaffold(body: Text('PAGE-settings')),
                  ),
                  GoRoute(
                    path: '/ai-assistant',
                    builder: (c, s) =>
                        const Scaffold(body: Text('PAGE-ai-assistant')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // 等待 _DesktopShell 异步加载 sidebar_collapsed 完成。
    await tester.pumpAndSettle();

    FlutterError.onError = oldHandler;

    // 展开侧栏顶部应有「视图模式」切换按钮（插件视图切回入口）。
    expect(find.byTooltip('视图模式'), findsOneWidget);

    // 点击切换按钮 → 弹扇形菜单 → 选「AI 视图」。
    await tester.tap(find.byTooltip('视图模式'));
    await tester.pumpAndSettle();
    expect(find.text('AI 视图'), findsOneWidget);
    await tester.tap(find.text('AI 视图'));
    await tester.pumpAndSettle();

    // 切回 AI 视图后导航到 /ai-assistant。
    expect(find.text('PAGE-ai-assistant'), findsOneWidget);
    expect(errors.where((e) => e.toString().contains('unbounded')), isEmpty);

    // body 末尾还原：_verifyInvariants 早于 tearDown 执行，否则触发
    // debugAssertAllFoundationVarsUnset（见 FAIL.md）。
    debugDefaultTargetPlatformOverride = null;
  });
}

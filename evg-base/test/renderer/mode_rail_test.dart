/// 模式窄轨 widget 测试——系统按钮、远程同步占位、开发者插件入口、
/// 扇形模式切换菜单、安卓爬取占位。
///
/// 不实例化 App 级服务：只注入 moduleRegistryProvider + pluginsDirProvider，
/// 用最小 GoRouter 验证导航；SharedPreferences 用 mock。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/mode_rail.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

ModuleDescriptor _mod(String id, String name, String route, String section) =>
    ModuleDescriptor(
      id: id,
      name: name,
      route: route,
      icon: 0xe000,
      nav: NavObjectDescriptor(
        sidebar: SidebarDescriptor(section: section, order: 10),
      ),
    );

ModuleRegistry _sealedRegistry({bool withDev = true}) {
  final r = ModuleRegistry();
  r.registerAll([
    _mod('ai-assistant', 'AI 助手', '/ai-assistant', '主功能'),
    _mod('settings', '设置', '/settings', '系统'),
    _mod('marketplace', '插件市场', '/marketplace', '系统'),
    _mod('data-dashboard', '数据中枢', '/data-dashboard', '系统'),
    if (withDev) ...[
      _mod('theme-creator', '主题创作中心', '/theme-creator', '主功能'),
      _mod('html-creator', 'HTML 插件创作中心', '/html-creator', '主功能'),
      _mod('scraper', '所见即所得爬虫', '/scraper', '主功能'),
    ],
  ]);
  r.seal();
  return r;
}

Widget _wrap(AppMode mode, ModuleRegistry registry, {String initialLocation = '/'}) {
  return ProviderScope(
    overrides: [
      moduleRegistryProvider.overrideWith((ref) => registry),
      pluginsDirProvider.overrideWith((ref) => 'test-plugins'),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(path: '/', builder: (c, s) => ModeRail(mode: mode)),
          GoRoute(path: '/dev-hub', builder: (c, s) => const Text('PAGE-devhub')),
          GoRoute(path: '/settings', builder: (c, s) => const Text('PAGE-settings')),
          GoRoute(path: '/marketplace', builder: (c, s) => const Text('PAGE-marketplace')),
          GoRoute(path: '/data-dashboard', builder: (c, s) => const Text('PAGE-dashboard')),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AI 视图窄轨：4 系统按钮 + 视图模式，无开发者入口', (tester) async {
    await tester.pumpWidget(_wrap(AppMode.ai, _sealedRegistry()));
    await tester.pump();

    expect(find.byTooltip('视图模式'), findsOneWidget);
    expect(find.byTooltip('显示设置'), findsOneWidget);
    expect(find.byTooltip('插件中心'), findsOneWidget);
    expect(find.byTooltip('数据中心'), findsOneWidget);
    expect(find.byTooltip('远程同步'), findsOneWidget);
    // 开发者入口只在开发者模式出现
    expect(find.byTooltip('主题创作'), findsNothing);
    expect(find.byTooltip('数据爬取'), findsNothing);
  });

  testWidgets('远程同步占位：点击弹「即将上线」提示', (tester) async {
    await tester.pumpWidget(_wrap(AppMode.ai, _sealedRegistry()));
    await tester.pump();

    await tester.tap(find.byTooltip('远程同步'));
    await tester.pumpAndSettle();

    expect(find.text('远程同步即将上线，敬请期待。'), findsOneWidget);
  });

  testWidgets('显示设置：点击推入 /settings（返回按钮语义由壳层提供）', (tester) async {
    await tester.pumpWidget(_wrap(AppMode.ai, _sealedRegistry()));
    await tester.pump();

    await tester.tap(find.byTooltip('显示设置'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE-settings'), findsOneWidget);
    expect(find.byType(ModeRail), findsNothing);
  });

  testWidgets('开发者模式：3 插件入口出现；点主题创作 → /dev-hub 且索引 0', (tester) async {
    await tester.pumpWidget(_wrap(AppMode.developer, _sealedRegistry()));
    await tester.pump();

    expect(find.byTooltip('主题创作'), findsOneWidget);
    expect(find.byTooltip('插件制作'), findsOneWidget);
    expect(find.byTooltip('数据爬取'), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ModeRail)));
    await tester.tap(find.byTooltip('主题创作'));
    await tester.pumpAndSettle();

    expect(find.text('PAGE-devhub'), findsOneWidget);
    expect(container.read(devHubIndexProvider), 0);
  });

  testWidgets('扇形菜单：点击视图图标 → 3 选项；选开发者模式即切换', (tester) async {
    await tester.pumpWidget(_wrap(AppMode.ai, _sealedRegistry()));
    await tester.pump();

    await tester.tap(find.byTooltip('视图模式'));
    await tester.pumpAndSettle();

    expect(find.text('AI 视图'), findsOneWidget);
    expect(find.text('开发者模式'), findsOneWidget);
    expect(find.text('插件视图'), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ModeRail)));
    await tester.tap(find.text('开发者模式'));
    await tester.pumpAndSettle();

    expect(container.read(appModeProvider), AppMode.developer);
    // 切模式后导航到目标默认视图（开发者 → /dev-hub）。
    expect(find.text('PAGE-devhub'), findsOneWidget);
    // 注：窄轨随 mode 重建由壳层 app_shell 负责（watch appModeProvider 后
    // 把 mode 传入 ModeRail 构造参数）；本用例只断言 provider 值 + 导航结果。
  });

  testWidgets('安卓：开发者模式点数据爬取 → 提示仅 Windows 版，不导航', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_wrap(AppMode.developer, _sealedRegistry()));
    await tester.pump();

    await tester.tap(find.byTooltip('数据爬取'));
    await tester.pumpAndSettle();

    expect(find.text('数据爬取仅支持 Windows 版'), findsOneWidget);
    expect(find.text('PAGE-devhub'), findsNothing);
    // body 末尾还原，避免 _verifyInvariants 检出 debug 变量泄漏。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('插件未安装：对应开发者入口隐藏', (tester) async {
    await tester.pumpWidget(
        _wrap(AppMode.developer, _sealedRegistry(withDev: false)));
    await tester.pump();

    expect(find.byTooltip('主题创作'), findsNothing);
    expect(find.byTooltip('插件制作'), findsNothing);
    expect(find.byTooltip('数据爬取'), findsNothing);
    // 系统按钮不受影响
    expect(find.byTooltip('显示设置'), findsOneWidget);
  });
}

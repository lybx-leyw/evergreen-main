/// 开发者模式主区 DevModeHub widget 测试——
/// 懒加载：默认只挂载当前选中页，切换后已访问页 Offstage 保活；
/// query 深链选页、安卓爬取占位、插件缺失兜底。
///
/// 模块用最小描述符（template 默认 v4、无 pages）→ ModuleDispatch 落到
/// DefaultView 空状态，不依赖模板注册表与 App 级服务。
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/app_mode.dart';
import 'package:evergreen_base/renderer/app/dev_mode_hub.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/renderer/module/module_page.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

ModuleDescriptor _mod(String id, String name) =>
    ModuleDescriptor(id: id, name: name, route: '/$id', icon: 0xe000);

ModuleRegistry _registry(List<String> ids) {
  final r = ModuleRegistry();
  r.registerAll(ids.map((id) => _mod(id, id)).toList());
  r.seal();
  return r;
}

Widget _wrap(
  ModuleRegistry registry,
  Directory pluginsDir, {
  String initialLocation = '/dev-hub',
}) {
  return ProviderScope(
    overrides: [
      moduleRegistryProvider.overrideWith((ref) => registry),
      pluginsDirProvider.overrideWith((ref) => pluginsDir.path),
      v2ManifestProvider.overrideWith(
        (ref) => const <String, Map<String, dynamic>>{},
      ),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(path: '/dev-hub', builder: (c, s) => const DevModeHub()),
        ],
      ),
    ),
  );
}

void main() {
  late Directory pluginsDir;

  setUp(() {
    pluginsDir = Directory.systemTemp.createTempSync('dev_hub_test');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    if (pluginsDir.existsSync()) {
      pluginsDir.deleteSync(recursive: true);
    }
  });

  testWidgets('默认：只挂载当前选中页，切换后已访问页 Offstage 保活', (tester) async {
    // flutter_test 默认 defaultTargetPlatform==android，会让 scraper/dsh 槽位落到
    // 安卓占位页；显式设为 windows 才能验证已注册页挂载 EvergreenModulePage。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // 仅注册 3 个：dsh / skill-creator 缺失 → 后续访问会落「插件未安装」占位页。
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir));
    await tester.pump();

    // 默认索引 0=主题创作，懒加载只挂载这一页。
    expect(
      find.byType(EvergreenModulePage, skipOffstage: false),
      findsOneWidget,
      reason: '懒加载下进入开发者模式不应一次性挂载全部插件页',
    );

    // 切到 html-creator（索引 1）：新页挂载，旧页仍在 Offstage 中保活。
    final ctx = tester.element(find.byType(DevModeHub));
    ProviderScope.containerOf(ctx).read(devHubIndexProvider.notifier).state = 1;
    await tester.pump();

    expect(
      find.byType(EvergreenModulePage, skipOffstage: false),
      findsNWidgets(2),
      reason: '已访问的 theme-creator + 新访问的 html-creator 都应挂载',
    );
    // 当前可见的应是 html-creator（默认 find 会跳过 Offstage 隐藏页）。
    expect(find.byType(EvergreenModulePage), findsOneWidget);
    // 必须在 body 末尾还原：_verifyInvariants 早于 tearDown 执行，
    // 否则触发 debugAssertAllFoundationVarsUnset。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('query 深链：?plugin=scraper 直接懒加载目标页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(
      _wrap(registry, pluginsDir, initialLocation: '/dev-hub?plugin=scraper'),
    );
    await tester.pump();

    // 深链到 scraper 时只构建 scraper 一页，而不是全部 5 个槽位。
    expect(
      find.byType(EvergreenModulePage, skipOffstage: false),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('安卓：scraper 槽位为占位页（提示仅 Windows 版）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(
      _wrap(registry, pluginsDir, initialLocation: '/dev-hub?plugin=scraper'),
    );
    await tester.pump();

    expect(find.text('数据爬取仅支持 Windows 版'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('安卓：skill-creator 槽位为占位页（提示仅 Windows 版）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final registry = _registry([
      'theme-creator',
      'html-creator',
      'scraper',
      'dsh',
      'skill-creator',
    ]);
    await tester.pumpWidget(
      _wrap(
        registry,
        pluginsDir,
        initialLocation: '/dev-hub?plugin=skill-creator',
      ),
    );
    await tester.pump();

    expect(find.text('Skill 创作仅支持 Windows 版'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('插件缺失：仅当前选中的缺失槽位渲染「插件未安装」占位', (tester) async {
    // 显式非安卓：避免 scraper/dsh 槽位先落入安卓占位分支，验证 _MissingPluginPage。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final registry = _registry(['theme-creator', 'html-creator']);
    await tester.pumpWidget(
      _wrap(registry, pluginsDir, initialLocation: '/dev-hub?plugin=scraper'),
    );
    await tester.pump();

    // 懒加载：只有深链选中的 scraper 被构建，因此只出现一个缺失占位页。
    expect(find.text('插件未安装', skipOffstage: false), findsOneWidget);
    expect(find.text('scraper', skipOffstage: false), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

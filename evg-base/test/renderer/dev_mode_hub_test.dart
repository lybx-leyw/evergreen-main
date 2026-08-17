/// 开发者模式主区 DevModeHub widget 测试——
/// IndexedStack 三插件挂载、query 深链选页、安卓爬取占位、插件缺失兜底。
///
/// 模块用最小描述符（template 默认 v4、无 pages）→ ModuleDispatch 落到
/// DefaultView 空状态，不依赖模板注册表与 App 级服务。
import 'dart:io';

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/dev_mode_hub.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/renderer/module/module_page.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

ModuleDescriptor _mod(String id, String name) => ModuleDescriptor(
      id: id,
      name: name,
      route: '/$id',
      icon: 0xe000,
    );

ModuleRegistry _registry(List<String> ids) {
  final r = ModuleRegistry();
  r.registerAll(ids.map((id) => _mod(id, id)).toList());
  r.seal();
  return r;
}

Widget _wrap(ModuleRegistry registry, Directory pluginsDir,
    {String initialLocation = '/dev-hub'}) {
  return ProviderScope(
    overrides: [
      moduleRegistryProvider.overrideWith((ref) => registry),
      pluginsDirProvider.overrideWith((ref) => pluginsDir.path),
      v2ManifestProvider
          .overrideWith((ref) => const <String, Map<String, dynamic>>{}),
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

  testWidgets('默认：三插件全部挂载（IndexedStack），选中索引 0=主题创作', (tester) async {
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 0);
    expect(stack.children.length, 3);
    expect(
      find.byType(EvergreenModulePage, skipOffstage: false),
      findsNWidgets(3),
      reason: 'IndexedStack 三页同时挂载以保持状态',
    );
  });

  testWidgets('query 深链：?plugin=scraper 选中索引 2', (tester) async {
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 2);
  });

  testWidgets('安卓：scraper 槽位为占位页（提示仅 Windows 版）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    expect(find.text('数据爬取仅支持 Windows 版'), findsOneWidget);
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children.length, 3, reason: '槽位数量不变，仅内容替换');
  });

  testWidgets('插件缺失：对应槽位渲染「插件未安装」占位', (tester) async {
    final registry = _registry(['theme-creator', 'html-creator']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    expect(find.text('插件未安装'), findsOneWidget);
    expect(find.text('scraper'), findsOneWidget);
  });
}

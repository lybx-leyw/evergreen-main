/// 开发者模式主区 DevModeHub widget 测试——
/// IndexedStack 四插件挂载（theme-creator/html-creator/scraper/dsh）、
/// query 深链选页、安卓爬取占位、插件缺失兜底。
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

  testWidgets('默认：五插件全部挂载（IndexedStack），选中索引 0=主题创作', (tester) async {
    // flutter_test 默认 defaultTargetPlatform==android，会让 scraper/dsh 槽位落到
    // 安卓占位页；显式设为 windows 才能验证已注册页挂载 EvergreenModulePage。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // 仅注册 3 个：dsh / skill-creator 缺失 → 第 4/5 槽位落到「插件未安装」占位页。
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 0);
    expect(stack.children.length, 5);
    expect(
      find.byType(EvergreenModulePage, skipOffstage: false),
      findsNWidgets(3),
      reason: 'IndexedStack 五槽位同时挂载；已注册 3 页挂 EvergreenModulePage，'
          'dsh / skill-creator 缺失落占位页',
    );
    // 必须在 body 末尾还原：_verifyInvariants 早于 tearDown 执行，
    // 否则触发 debugAssertAllFoundationVarsUnset。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('query 深链：?plugin=scraper 选中索引 2', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('安卓：scraper 槽位为占位页（提示仅 Windows 版）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final registry = _registry(['theme-creator', 'html-creator', 'scraper']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    expect(find.text('数据爬取仅支持 Windows 版'), findsOneWidget);
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children.length, 5, reason: '槽位数量不变，仅内容替换');
    // body 末尾还原，避免 _verifyInvariants 检出 debug 变量泄漏。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('插件缺失：对应槽位渲染「插件未安装」占位', (tester) async {
    // 显式非安卓：避免 scraper/dsh 槽位先落入安卓占位分支，验证 _MissingPluginPage。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final registry = _registry(['theme-creator', 'html-creator']);
    await tester.pumpWidget(_wrap(registry, pluginsDir,
        initialLocation: '/dev-hub?plugin=scraper'));
    await tester.pump();

    // skipOffstage: false —— IndexedStack 中非活动页 offstage，find 默认裁剪。
    // 缺失的插件是 scraper + dsh + skill-creator 三个 → 三个「插件未安装」占位页。
    expect(find.text('插件未安装', skipOffstage: false), findsNWidgets(3));
    expect(find.text('scraper', skipOffstage: false), findsOneWidget);
    expect(find.text('dsh', skipOffstage: false), findsOneWidget);
    expect(find.text('skill-creator', skipOffstage: false), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

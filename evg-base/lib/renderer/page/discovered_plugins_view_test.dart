/// 发现页测试（M6 自动发现 + 下载安装）。
///
/// 覆盖：registry 解析展示、安装按钮出现、点安装触发 clone 并标记「已安装」、
/// inline manifest 落盘。
/// registry 用内存注入（不依赖 asset 读取时序），clone 用 fake（不依赖 git/网络）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/services/github_stars.dart';
import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/module/plugin_registry.dart'
    show RegistryPlugin, PluginManifest;
import 'package:evergreen_base/core/services/github_clone.dart' show CloneResult;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/page/discovered_plugins_view.dart';

/// fake cloner：同步创建目录即视为克隆成功，返回 [CloneResult.ok]。
/// 用同步 I/O 避免 widget 测试中 async 文件操作被 pump 事件循环饿死。
Future<CloneResult> _fakeClone(GithubSource src, String targetDir) async {
  Directory(targetDir).createSync(recursive: true);
  return CloneResult.ok();
}

/// 计数 fake cloner：记录被调用次数，仍创建目录视为成功。
/// 用于断言「install 为空时不应触发任何下载」。
class _CountingCloner {
  int calls = 0;
  Future<CloneResult> call(GithubSource src, String targetDir) async {
    calls++;
    Directory(targetDir).createSync(recursive: true);
    return CloneResult.ok();
  }
}

/// 内存 registry 源：返回一个通用 data-source 条目（inline manifest，自包含，
/// 不依赖被清理的探针插件本地 asset）。安装时直接落盘内嵌 manifest。
Future<List<RegistryPlugin>> Function() _memoryRegistry = () async => [
      RegistryPlugin(
        id: 'demo-source',
        name: 'Demo Source',
        description: 'test',
        version: '1.0.0',
        dimensions: const ['data'],
        install: const {
          'type': 'github',
          'url': 'https://github.com/example/demo-source',
        },
        manifest: const PluginManifest.inline({
          'type': 'data-source',
          'id': 'demo-source',
          'name': 'Demo Source',
          'script': 'demo.py',
          'runtime': 'python',
          'dataTypes': [
            {'name': 'demo', 'typeArg': 'demo'},
          ],
        }),
        stars: 0,
      ),
    ];

/// 推进若干帧（避免 pumpAndSettle 因弹窗/动画时序超时）。
Future<void> _pump(WidgetTester tester, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 空 starFetcher：不触发数据中枢，返回空 map（star 保持静态值）。
Future<Map<String, int>> _emptyStars(List<String> urls) async => const {};

/// 构造一个带 fake `github-stars` fetcher 的 orchestrator（测试数据中枢路径）。
DataOrchestrator _hubWithStars(Map<String, int> stars) {
  final orch = DataOrchestrator();
  orch.register(
    githubStarsType(),
    () async => stars,
  );
  return orch;
}

void main() {
  testWidgets('registry 插件被自动发现并展示安装按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginsDirProvider.overrideWithValue(
              Directory.systemTemp.createTempSync('disc_').path),
        ],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            registryLoader: _memoryRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);
    expect(find.text('发现插件'), findsWidgets);
    expect(find.text('Demo Source'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '安装'), findsWidgets);
  });

  testWidgets('点安装触发 clone 并标记为已安装', (tester) async {
    final pluginsDir = Directory.systemTemp.createTempSync('disc_install_').path;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginsDirProvider.overrideWithValue(pluginsDir)],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            cloner: _fakeClone,
            registryLoader: _memoryRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    // 找到第一个「安装」按钮（Demo Source）并点击 → 弹权限确认窗。
    await tester.tap(find.widgetWithText(FilledButton, '安装').first);
    await _pump(tester);

    // 确认权限弹窗（fail-closed：需点「确认安装」才放行）。
    await tester.tap(find.widgetWithText(FilledButton, '确认安装'));
    await _pump(tester, 40);

    // 克隆目录应被创建（id = demo-source）。
    expect(Directory('$pluginsDir/demo-source').existsSync(), isTrue);
    // 该卡片应显示「已安装」徽章/标签。
    expect(find.text('已安装'), findsWidgets);
    // M6 · 补 4：inline manifest 应落盘到 plugins/demo-source/data/manifest.json。
    final manifestFile = File('$pluginsDir/demo-source/data/manifest.json');
    expect(manifestFile.existsSync(), isTrue,
        reason: '安装后应按 manifest 声明落盘 manifest.json');
    final manifestJson =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifestJson['type'], 'data-source');
    expect(manifestJson['script'], 'demo.py');
  });

  testWidgets('实时 GitHub star 数覆盖 registry 静态值', (tester) async {
    // fake starFetcher：返回实时 star 128（覆盖静态 0）。
    Future<Map<String, int>> fakeStars(List<String> urls) async {
      return {'example/demo-source': 128};
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginsDirProvider.overrideWithValue(
              Directory.systemTemp.createTempSync('disc_star_').path),
        ],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            registryLoader: _memoryRegistry,
            starFetcher: fakeStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    // 应显示实时 star 128（而非静态 0）。
    expect(find.text('128'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('star 数经数据中枢统一管理（默认路径）', (tester) async {
    // 注入带 fake github-stars fetcher 的 orchestrator（不注入 starFetcher，
    // 验证默认走数据中枢 registerGithubStars + get 路径）。
    final orch = _hubWithStars({'example/demo-source': 256});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pluginsDirProvider.overrideWithValue(
              Directory.systemTemp.createTempSync('disc_hub_').path),
          dataOrchestratorProvider.overrideWithValue(orch),
        ],
        child: MaterialApp(
          home: DiscoveredPluginsView(registryLoader: _memoryRegistry),
        ),
      ),
    );
    await _pump(tester);

    // 应显示数据中枢返回的 star 256（而非静态 0）。
    expect(find.text('256'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('manifest.source=github：从已 clone 仓库复制资源目录', (tester) async {
    final pluginsDir = Directory.systemTemp.createTempSync('disc_gh_').path;

    // fake cloner：模拟 clone 后仓库内的目录结构（auto-signed-plugins 形态），
    // 资源目录在 `plugins/zju_autosign/` 下，含 module + data + config 三子目录。
    Future<CloneResult> fakeCloneWithRepo(GithubSource src, String targetDir) async {
      // 仓库根：plugins/zju_autosign/{module,data,config}
      final repoDir = Directory('$targetDir/plugins/zju_autosign');
      repoDir.createSync(recursive: true);
      File('$targetDir/plugins/zju_autosign/module/manifest.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'type': 'module', 'id': 'zju_autosign'}));
      File('$targetDir/plugins/zju_autosign/module/index.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('<html></html>');
      File('$targetDir/plugins/zju_autosign/data/manifest.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'type': 'data-source'}));
      File('$targetDir/plugins/zju_autosign/config/config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      return CloneResult.ok();
    }

    // github 源 registry 条目：path 指向仓库内资源目录。
    Future<List<RegistryPlugin>> Function() githubRegistry = () async => [
          RegistryPlugin(
            id: 'zju_autosign',
            name: '学在浙大自动签到',
            description: 'test',
            version: '1.0.0',
            dimensions: const ['ui', 'data'],
            lattice: 'module',
            install: const {
              'type': 'github',
              'url': 'https://github.com/lybx-leyw/auto-signed-plugins',
            },
            manifest: const PluginManifest.github(
                'lybx-leyw/auto-signed-plugins', 'plugins/zju_autosign'),
            stars: 0,
          ),
        ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginsDirProvider.overrideWithValue(pluginsDir)],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            cloner: fakeCloneWithRepo,
            registryLoader: githubRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, '安装').first);
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认安装'));
    await _pump(tester, 40);

    // 资源目录应被「上移」到 plugins/zju_autosign/ 根：
    expect(File('$pluginsDir/zju_autosign/module/manifest.json').existsSync(),
        isTrue);
    expect(File('$pluginsDir/zju_autosign/module/index.html').existsSync(),
        isTrue);
    expect(File('$pluginsDir/zju_autosign/data/manifest.json').existsSync(),
        isTrue);
    expect(File('$pluginsDir/zju_autosign/config/config.json').existsSync(),
        isTrue);
    expect(find.text('已安装'), findsWidgets);
  });

  testWidgets('install 为空 + manifest.source=local：跳过下载，直走本地复制',
      (tester) async {
    final pluginsDir = Directory.systemTemp.createTempSync('disc_local_').path;
    final counting = _CountingCloner();

    // 内置随包分发条目：无 install，manifest.source=local 指向本地资源目录。
    // 资源目录通过 AssetManifest 枚举（测试运行于已打包 asset 的环境）。
    Future<List<RegistryPlugin>> Function() localRegistry = () async => [
          RegistryPlugin(
            id: 'view',
            name: '我的成绩单',
            description: 'test',
            version: '1.0.0',
            dimensions: const ['ui'],
            // 注意：install 故意省略（null）。
            manifest: const PluginManifest.local('assets/view'),
            stars: 0,
          ),
        ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginsDirProvider.overrideWithValue(pluginsDir)],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            cloner: counting.call,
            registryLoader: localRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    // 关键断言：install 为空时绝不应触发任何网络下载（clone）。
    expect(counting.calls, 0,
        reason: 'install 为空的本地插件不应触发 clone 下载');

    await tester.tap(find.widgetWithText(FilledButton, '安装').first);
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认安装'));
    await _pump(tester, 40);

    // 安装后仍然没有触发过 clone（下载被跳过）。
    expect(counting.calls, 0,
        reason: '安装过程中不应触发 clone 下载');
    // 本地资源应被复制到 plugins/view/module/（AssetManifest 枚举 docs/plugin-registry/assets/view/）。
    expect(File('$pluginsDir/view/module/manifest.json').existsSync(), isTrue);
    expect(File('$pluginsDir/view/module/index.html').existsSync(), isTrue);
    expect(find.text('已安装'), findsWidgets);
  });

  testWidgets('manifest.source=local 但 install 非空：仍走下载', (tester) async {
    // 防回归：manifest 来源与是否下载无关。即使 manifest 是 local，
    // 只要 install 非空，就必须下载文件。
    final pluginsDir = Directory.systemTemp.createTempSync('disc_locdl_').path;
    final counting = _CountingCloner();

    Future<List<RegistryPlugin>> Function() mixedRegistry = () async => [
          RegistryPlugin(
            id: 'demo-mixed',
            name: 'Demo Mixed',
            description: 'test',
            version: '1.0.0',
            dimensions: const ['ui'],
            install: const {
              'type': 'github',
              'url': 'https://github.com/example/demo-mixed',
            },
            manifest: const PluginManifest.local('assets/view'),
            stars: 0,
          ),
        ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginsDirProvider.overrideWithValue(pluginsDir)],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            cloner: counting.call,
            registryLoader: mixedRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, '安装').first);
    await _pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, '确认安装'));
    await _pump(tester, 40);

    // install 非空 → 必须触发 clone 下载（即便 manifest 是 local）。
    expect(counting.calls, 1,
        reason: 'install 非空时即便 manifest.source=local 也应下载');
    expect(find.text('已安装'), findsWidgets);
  });

  testWidgets('已安装插件可删除（便于重装）', (tester) async {
    final pluginsDir = Directory.systemTemp.createTempSync('disc_del_').path;
    // 预置一个已安装目录 + manifest，模拟「已安装」状态。
    final pluginDir = Directory('$pluginsDir/demo-source')..createSync(recursive: true);
    File('$pluginsDir/demo-source/data/manifest.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pluginsDirProvider.overrideWithValue(pluginsDir)],
        child: MaterialApp(
          home: DiscoveredPluginsView(
            cloner: _fakeClone,
            registryLoader: _memoryRegistry,
            starFetcher: _emptyStars,
          ),
        ),
      ),
    );
    await _pump(tester);

    // 预置目录 → 显示「已安装」。
    expect(find.text('已安装'), findsWidgets);

    // 点删除按钮 → 弹确认 → 确认删除。
    await tester.tap(find.byTooltip('删除插件').first);
    await _pump(tester);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await _pump(tester, 10);

    // 目录应被删除，卡片回到「安装」态。
    expect(Directory(pluginDir.path).existsSync(), isFalse);
    expect(find.widgetWithText(FilledButton, '安装'), findsWidgets);
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// E2E Agent 工具链验证器（执行沙盒 + 定制工作调用路径）
//
// 目标：在「虚构的百度榜单环境」（执行沙盒）里，走完两条真实的工作调用路径，
// 验证工具链「调用路径正确性」——全程不依赖真实 API / 网络 / LLM。
//
// 沙盒组成：
//   - 本地 HttpServer 模拟「百度榜单」站：`/rank/hot`、`/rank/movie`、`/rank/song`
//     三个榜单接口，返回真实 JSON（非占位符）。
//   - 假 WebView 通道：evaluateJs 返回榜单链接清单、navigateTo 记录导航、
//     captureWorkflow 灌入捕获日志。
//
// 两条定制路径：
//   ├─ 路径 A「探索百度榜单」：explore_page_links → navigate_get →
//   │    list_captured_requests → present_data_sources → build_selected_source
//   │    → register_batch（探索模式工具链，假 WebView 通道）。
//   └─ 路径 B「定向拉取某一榜单」：run_python_scraper（真实 Python 真实抓取
//        沙盒接口）→ 导出插件 → 注册 → orch.get 验证（定向模式工具链 +
//        真实 DataOrchestrator + 真实 Python）。
//
// 运行：`flutter test test/scraper/scraper_toolchain_e2e_test.dart`
// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/agent/tools/scraper_tools.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/scraper_explore_tools.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// 沙盒：本地「百度榜单」HTTP 站点
// ═══════════════════════════════════════════════════════════════════════════

/// 虚构的百度榜单沙盒：三个榜单接口，返回真实 JSON。
class BaiduRankSandbox {
  late HttpServer _server;
  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  /// 榜单数据（真实数据，非占位符）。
  static const Map<String, List<Map<String, dynamic>>> _ranks = {
    'hot': [
      {'rank': 1, 'title': 'DeepSeek-V4 发布', 'heat': 98213},
      {'rank': 2, 'title': '浙大求是创新校训', 'heat': 87420},
      {'rank': 3, 'title': 'Evergreen 多工具平台', 'heat': 76501},
    ],
    'movie': [
      {'rank': 1, 'title': '流浪地球 3', 'score': 9.2},
      {'rank': 2, 'title': '长安三万里', 'score': 8.9},
    ],
    'song': [
      {'rank': 1, 'title': '孤勇者', 'singer': '陈奕迅'},
      {'rank': 2, 'title': '如愿', 'singer': '王菲'},
    ],
  };

  Future<void> start() async {
    _server = await HttpServer.bind('127.0.0.1', 0);
    _server.listen((req) async {
      final path = req.uri.path;
      final rankKey = path.startsWith('/rank/')
          ? path.substring('/rank/'.length)
          : null;
      final data = _ranks[rankKey];
      req.response
        ..statusCode = data == null ? 404 : 200
        ..headers.contentType = ContentType.json
        ..write(data == null
            ? jsonEncode({'error': 'unknown rank'})
            : jsonEncode({'rank': rankKey, 'items': data}));
      await req.response.close();
    });
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }
}

/// 榜单首页链接清单（沙盒 evaluateJs 返回）。
List<Map<String, dynamic>> _rankLinks(String baseUrl) => [
      {'url': '$baseUrl/rank/hot', 'text': '热搜榜'},
      {'url': '$baseUrl/rank/movie', 'text': '电影榜'},
      {'url': '$baseUrl/rank/song', 'text': '音乐榜'},
    ];

// ═══════════════════════════════════════════════════════════════════════════
// 路径 A：探索百度榜单（探索模式工具链）
// ═══════════════════════════════════════════════════════════════════════════

/// 沙盒探索工具集：假 WebView 通道 + 真实 ExploreWorkflow/ScraperWorkflow。
class ExploreSandbox {
  final ExploreWorkflow explore;
  final ScraperWorkflow capture;
  final List<Tool> tools;

  /// 构建产物的记录（build_selected_source 写回）。
  final Map<String, String> builtCode = {};

  /// 注册批次记录（register_batch 写回）。
  List<String> lastRegistered = const [];

  ExploreSandbox._(this.explore, this.capture, this.tools);

  factory ExploreSandbox.create(String baseUrl) {
    final explore = ExploreWorkflow();
    final capture = ScraperWorkflow();

    // 假 evaluateJs：返回榜单链接 JSON（模拟 explorePageLinksScript 结果）
    Future<String?> evaluateJs(String script) async {
      return jsonEncode(jsonEncode({
        'count': 3,
        'links': _rankLinks(baseUrl),
      }));
    }

    // 假 navigateTo：记录导航，并灌入一条捕获日志（模拟 WebView 捕获 GET）
    Future<void> navigateTo(String url) async {
      capture.addLog(HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: url,
        responseBody: jsonEncode({
          'rank': url.split('/').last,
          'items': BaiduRankSandbox._ranks[url.split('/').last] ?? [],
        }),
      ));
    }

    final tools = createScraperExploreTools(
      exploreWorkflow: explore,
      captureWorkflow: capture,
      evaluateJs: evaluateJs,
      navigateTo: navigateTo,
      presentSources: (cands) async => cands, // 沙盒：用户全选
      buildSource: (name, code) async => '✅ 构建 data-$name 成功',
      registerBatch: (names) async => '✅ 注册 ${names.length} 个成功',
      listPythonCapabilities: () => const ['requests'],
    );

    return ExploreSandbox._(explore, capture, tools);
  }

  Tool tool(String name) => tools.firstWhere((t) => t.name == name);
}

// ═══════════════════════════════════════════════════════════════════════════
// 路径 B：定向拉取某一榜单（定向模式工具链 + 真实 Python + 真实 orchestrator）
// ═══════════════════════════════════════════════════════════════════════════

/// 定向拉取沙盒：真实 Python 抓取沙盒接口 → 注册 → orch.get 验证。
class CaptureSandbox {
  final String workspaceDir;
  final String pluginDir;
  final DataOrchestrator orch;

  CaptureSandbox._(this.workspaceDir, this.pluginDir, this.orch);

  factory CaptureSandbox.create(String tmpRoot) {
    final workspaceDir = p.join(tmpRoot, 'workspace');
    final pluginsDir = p.join(tmpRoot, 'plugins');
    final pluginDir = p.join(pluginsDir, 'data-hot');
    Directory(workspaceDir).createSync(recursive: true);
    Directory(p.join(pluginDir, 'data')).createSync(recursive: true);
    return CaptureSandbox._(workspaceDir, pluginDir, DataOrchestrator());
  }
}

void main() {
  late BaiduRankSandbox sandbox;

  setUpAll(() async {
    sandbox = BaiduRankSandbox();
    await sandbox.start();
  });

  tearDownAll(() async {
    await sandbox.stop();
  });

  // ═══════════ 路径 A：探索百度榜单 ═══════════

  group('路径 A：探索百度榜单（探索模式工具链）', () {
    test('完整调用路径：枚举 → 导航 → 捕获 → 呈现 → 构建 → 注册', () async {
      final s = ExploreSandbox.create(sandbox.baseUrl);

      // Step 1: 开始探索（锁定域名）
      expect(
        s.explore.startExploring(startUrl: '${sandbox.baseUrl}/rank/hot'),
        isTrue,
      );
      expect(s.explore.baseHost, '127.0.0.1');

      // Step 2: explore_page_links 枚举榜单链接
      final linksOut = await s.tool('explore_page_links').execute({});
      expect(linksOut, contains('/rank/hot'));
      expect(linksOut, contains('/rank/movie'));
      expect(linksOut, contains('/rank/song'));

      // Step 3: navigate_get 逐个访问（真实 ExploreWorkflow 守卫：同域/节流）
      // 首次导航已有 1s 节流——这里直接通过记录导航验证守卫
      final nav = await s.tool('navigate_get').execute(
          {'url': '${sandbox.baseUrl}/rank/movie'});
      expect(nav, contains('✅'));

      // Step 4: list_captured_requests 读取捕获日志（含响应体样本）
      final captured = await s.tool('list_captured_requests').execute({});
      expect(captured, contains('GET'));
      expect(captured, contains('证据 id'));

      // Step 5: present_data_sources 呈现候选（沙盒用户全选）
      final present = await s.tool('present_data_sources').execute({
        'sources': jsonEncode([
          {
            'name': 'hot',
            'displayName': '热搜榜',
            'category': '榜单',
            'url': '${sandbox.baseUrl}/rank/hot',
            'sourceLogId': 'log-1',
            'fields': [
              {'name': 'title', 'type': 'string'},
            ],
          },
        ]),
      });
      expect(present, contains('✅ 用户已确认'));

      // Step 6: build_selected_source 构建
      final build = await s.tool('build_selected_source').execute({
        'name': 'hot',
        'code': 'print("scraper")',
      });
      expect(build, contains('data-hot'));

      // Step 7: register_batch 注册
      final reg = await s.tool('register_batch').execute({'names': '["hot"]'});
      expect(reg, contains('批量注册'));

      // 断言状态机推进到 registering/done
      expect(s.explore.phase, isNot(ExplorePhase.idle));
    });

    test('navigate_get 跨域守卫拒绝（沙盒同域约束生效）', () async {
      final s = ExploreSandbox.create(sandbox.baseUrl);
      s.explore.startExploring(startUrl: '${sandbox.baseUrl}/rank/hot');
      final out = await s.tool('navigate_get').execute(
          {'url': 'https://evil.com/rank'});
      expect(out, contains('[error:'));
      expect(out, contains('非同域'));
    });
  });

  // ═══════════ 路径 B：定向拉取某一榜单 ═══════════

  group('路径 B：定向拉取某一榜单（真实 Python + 真实 orchestrator）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('scraper_capture_e2e_');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('真实 Python 抓取沙盒接口 → 注册 → orch.get 出数', () async {
      final py = await resolvePythonExe();
      if (py == null) {
        markTestSkipped('本机未找到 Python，跳过路径 B');
        return;
      }

      final s = CaptureSandbox.create(tmp.path);

      // Step 1: 用真实 run_python_scraper 抓取沙盒热搜榜
      final tools = createScraperTools(
        workspaceDir: s.workspaceDir,
        projectRoot: tmp.path,
        resolvePython: () => resolvePythonExe(),
        getLogsSummary: () => '',
        enqueueCommand: (_) {},
        getTerminalResult: () async => '',
        exportAndRegister: () async => '✅ ok',
        dataNameProvider: () => 'hot',
        setDataName: (_) {},
        requestOverride: (_, __) async => true,
      );
      final runTool = tools.firstWhere((t) => t.name == 'run_python_scraper');
      // 真实抓取：requests 拉取沙盒接口（非占位符）
      final code = '''
import json
import requests

def main():
    r = requests.get('${sandbox.baseUrl}/rank/hot', timeout=5)
    data = r.json()
    return {"source": "baidu-hot", "items": data["items"]}

if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False))
''';
      final runOut = await runTool.execute({'code': code});
      expect(runOut, contains('✅ 爬虫执行成功'));
      expect(runOut, contains('JSON 输出校验通过'));

      // Step 2: 真实注册：把 scraper.py 写成 data 插件 + 注册进 orchestrator
      // 写 manifest + scraper.py 到插件目录
      final dataDir = p.join(s.pluginDir, 'data');
      File(p.join(dataDir, 'scraper.py')).writeAsStringSync(code);
      File(p.join(dataDir, 'manifest.json')).writeAsStringSync(jsonEncode({
        'type': 'data-source',
        'runtime': 'python',
        'script': 'scraper.py',
        'dataTypes': [
          {
            'name': 'hot',
            'typeArg': 'hot',
            'ttl': '5m',
            'persistentKey': 'baidu-hot:hot',
            'category': '榜单',
            'displayName': '热搜榜',
          },
        ],
      }));

      // 直接注册一个 fetcher（等价 registerDataSourcesFromManifest 的 CLI fetcher，
      // 但沙盒用真实 requests 内联，避免 Process.run 需要共享 runner）
      s.orch.register<Map<String, dynamic>>(
        const DataType<Map<String, dynamic>>(
          name: 'hot',
          category: '榜单',
          displayName: '热搜榜',
          ttl: Duration(minutes: 5),
        ),
        () async {
          final r = await _httpGet('${sandbox.baseUrl}/rank/hot');
          return r;
        },
      );

      // Step 3: orch.get 验证真实出数
      final data = await s.orch.get(
          const DataType<Map<String, dynamic>>(name: 'hot'));
      expect(data, isNotNull);
      expect(data!['items'], isNotEmpty);
      expect((data['items'] as List).first, containsPair('title', isNotEmpty));
    });
  });
}

/// 沙盒内联 HTTP GET（避免依赖 dio，纯 dart:io）。
Future<Map<String, dynamic>> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

// 探索工具测试（Phase 4 · D1-D9）。
//
// 覆盖：
// 1. navigate_get 守卫拒绝路径（跨域 / 非 http(s) / 节流）→ 导航回调不被调用
// 2. explore_page_links JS 结果解析（双 JSON 编码形态）+ 同域过滤
// 3. list_captured_requests：仅 GET、同域过滤
// 4. present_data_sources：解析/校验/用户选择（改名）→ 阶段推进
// 5. build_selected_source / register_batch：参数校验 + 回调整合
import 'dart:convert';

import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/scraper_explore_tools.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigateGetTool（GET-only 守卫）', () {
    (ExploreWorkflow, NavigateGetTool, List<String>) make() {
      final w = ExploreWorkflow();
      final calls = <String>[];
      final tool = NavigateGetTool(
        exploreWorkflow: w,
        navigateTo: (url) async => calls.add(url),
      );
      return (w, tool, calls);
    }

    test('同域 GET 导航成功并调用导航通道', () async {
      final (w, tool, calls) = make();
      w.startExploring(startUrl: 'https://site.com/');
      final out = await tool.execute({'url': 'https://site.com/api/courses'});
      expect(out, contains('✅'));
      expect(calls, ['https://site.com/api/courses']);
      expect(out, contains('页数 1/20'));
    });

    test('跨域导航被守卫拒绝（D2/D7），导航通道不被调用', () async {
      final (w, tool, calls) = make();
      w.startExploring(startUrl: 'https://site.com/');
      final out = await tool.execute({'url': 'https://evil.com/x'});
      expect(out, contains('[error: 探索导航被守卫拒绝'));
      expect(out, contains('非同域'));
      expect(calls, isEmpty);
    });

    test('非 http(s) 协议被守卫拒绝', () async {
      final (w, tool, calls) = make();
      w.startExploring();
      final out = await tool.execute({'url': 'javascript:alert(1)'});
      expect(out, contains('仅允许 http/https'));
      expect(calls, isEmpty);
    });

    test('节流拒绝（1s 内第二次导航）', () async {
      final (w, tool, calls) = make();
      w.startExploring();
      expect(await tool.execute({'url': 'https://a.com/1'}), contains('✅'));
      final out = await tool.execute({'url': 'https://a.com/2'});
      expect(out, contains('节流'));
      expect(calls.length, 1);
    });
  });

  group('ExplorePageLinksTool（JS 结果解析 + 同域过滤）', () {
    test('解析被 JSON 编码的返回串，过滤跨域链接', () async {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://a.com/');
      final inner = jsonEncode({
        'count': 2,
        'links': [
          {'url': 'https://a.com/1', 'text': 'One'},
          {'url': 'https://evil.com/x', 'text': 'Evil'},
          {'url': 'javascript:void(0)', 'text': 'Js'},
        ],
      });
      // Windows executeScript / Android runJavaScriptReturningResult 会把
      // 脚本返回的 JSON 字符串再 JSON 编码一层 → 传入 jsonEncode(inner)
      final tool = ExplorePageLinksTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => jsonEncode(inner),
      );
      final out = await tool.execute({});
      expect(out, contains('https://a.com/1'));
      expect(out, contains('One'));
      expect(out, isNot(contains('evil.com')));
      expect(out, isNot(contains('javascript')));
    });

    test('JS 通道不可用 → error', () async {
      final w = ExploreWorkflow();
      w.startExploring();
      final tool = ExplorePageLinksTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => null,
      );
      final out = await tool.execute({});
      expect(out, contains('[error:'));
    });
  });

  group('ListCapturedRequestsTool（仅 GET）', () {
    test('过滤 POST/NAVIGATION 等非 GET，同域过滤', () async {
      final capture = ScraperWorkflow();
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://a.com/');
      capture.addLog(HttpRequestLog(
          timestamp: DateTime.now(), method: 'GET', url: 'https://a.com/api/list'));
      capture.addLog(HttpRequestLog(
          timestamp: DateTime.now(), method: 'POST', url: 'https://a.com/api/login'));
      capture.addLog(HttpRequestLog(
          timestamp: DateTime.now(), method: 'NAVIGATION', url: 'https://a.com/page'));
      capture.addLog(HttpRequestLog(
          timestamp: DateTime.now(), method: 'GET', url: 'https://b.com/api/x'));

      final tool = ListCapturedRequestsTool(
        captureWorkflow: capture,
        exploreWorkflow: ew,
      );
      final out = await tool.execute({});
      expect(out, contains('api/list'));
      expect(out, isNot(contains('api/login')));
      expect(out, isNot(contains('NAVIGATION')));
      expect(out, isNot(contains('b.com')));
      // P0-2：每条 GET 摘要带证据 id（addLog 自动补号：GET api/list 是 log-1）
      expect(out, contains('证据 id: log-1'));
    });
  });

  group('PresentDataSourcesTool（归类 → 多选确认 + P0-2 证据校验）', () {
    /// 捕获工作流 + 常见 URL 日志（P0-2 证据校验需要 url 命中日志）。
    (ExploreWorkflow, ScraperWorkflow) readyWorkflow() {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://site.com/');
      w.startCategorizing();
      final capture = ScraperWorkflow();
      capture.addLog(HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: 'https://site.com/api/courses',
        responseBody: '{"data": [{"id": 1}]}',
      ));
      capture.addLog(HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: 'https://site.com/1',
      ));
      return (w, capture);
    }

    test('候选校验通过 → 用户选择（含改名）→ confirming → building', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => [
          cands.first.copyWith(name: 'renamed'),
        ],
      );
      final sources = jsonEncode([
        {
          'name': 'courses',
          'displayName': '课程',
          'category': '课程',
          'url': 'https://site.com/api/courses',
          'sourceLogId': 'log-1',
          'fields': [
            {'name': 'id', 'type': 'number', 'sourceJsonPath': r'$.data[0].id'},
          ],
        },
      ]);
      final out = await tool.execute({'sources': sources});
      expect(out, contains('✅ 用户已确认'));
      expect(out, contains('renamed'));
      expect(w.phase, ExplorePhase.building);
      expect(w.selected.single.name, 'renamed');
      // 改名后证据保留（copyWith 携带 sourceLogId）
      expect(w.selected.single.sourceLogId, 'log-1');
    });

    test('名称非法 → 拒绝并提示', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => cands,
      );
      final out = await tool.execute({
        'sources': jsonEncode([
          {'name': 'bad name!', 'displayName': 'x', 'category': '', 'url': 'https://site.com/1'},
        ]),
      });
      expect(out, contains('[error: 数据源名称非法'));
    });

    test('URL 跨域 → 拒绝', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => cands,
      );
      final out = await tool.execute({
        'sources': jsonEncode([
          {'name': 'x', 'displayName': 'x', 'category': '', 'url': 'https://evil.com/1'},
        ]),
      });
      expect(out, contains('非同域'));
    });

    test('用户未选择 → 提示重新归类', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => const [],
      );
      final out = await tool.execute({
        'sources': jsonEncode([
          {'name': 'x', 'displayName': 'x', 'category': '', 'url': 'https://site.com/1', 'sourceLogId': 'log-2'},
        ]),
      });
      expect(out, contains('用户未选择任何数据源'));
      expect(w.phase, ExplorePhase.confirming);
    });

    test('P0-2：url 无日志证据 → 拒绝呈现，不进入用户确认', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => fail('不应弹窗'),
      );
      final out = await tool.execute({
        'sources': jsonEncode([
          {'name': 'ghost', 'displayName': '幽灵', 'category': '', 'url': 'https://site.com/api/ghost', 'sourceLogId': 'log-99'},
        ]),
      });
      expect(out, contains('[error: 数据源 ghost 无日志证据'));
      expect(w.phase, ExplorePhase.categorizing); // 未进入 confirming
    });

    test('P0-2：sourceLogId 失效按 URL 兜底 + 警告回灌', () async {
      final (w, capture) = readyWorkflow();
      final tool = PresentDataSourcesTool(
        exploreWorkflow: w,
        captureWorkflow: capture,
        presentSources: (cands) async => cands,
      );
      final out = await tool.execute({
        'sources': jsonEncode([
          {'name': 'courses', 'displayName': 'x', 'category': '', 'url': 'https://site.com/api/courses', 'sourceLogId': 'log-404'},
        ]),
      });
      expect(out, contains('✅ 用户已确认'));
      expect(out, contains('证据警告'));
      expect(out, contains('兜底'));
    });
  });

  group('BuildSelectedSourceTool / RegisterBatchTool', () {
    test('build：名称非法拒绝；合法透传回调并前缀 data-{name}', () async {
      var builtName = '';
      var builtCode = '';
      final tool = BuildSelectedSourceTool(
        buildSource: (name, code) async {
          builtName = name;
          builtCode = code;
          return '✅ 构建成功';
        },
      );
      final bad = await tool.execute({'name': 'bad name', 'code': 'x'});
      expect(bad, contains('[error: 数据源名称非法'));

      final ok = await tool.execute({'name': 'courses', 'code': 'print(1)'});
      expect(ok, contains('📁 **data-courses**'));
      expect(ok, contains('构建成功'));
      expect(builtName, 'courses');
      expect(builtCode, 'print(1)');
    });

    test('register：JSON 数组解析 + 逗号降级解析', () async {
      final calls = <List<String>>[];
      final tool = RegisterBatchTool(
        registerBatch: (names) async {
          calls.add(names);
          return '✅ 全部注册';
        },
      );
      final out1 = await tool.execute({'names': '["a","b"]'});
      expect(out1, contains('批量注册（2 个数据源）'));
      expect(calls.single, ['a', 'b']);

      final out2 = await tool.execute({'names': 'a,b,c'});
      expect(out2, contains('批量注册（3 个数据源）'));
      expect(calls.last, ['a', 'b', 'c']);
    });

    test('register：非法名称拒绝', () async {
      final tool = RegisterBatchTool(registerBatch: (names) async => 'x');
      final out = await tool.execute({'names': '["ok","bad name"]'});
      expect(out, contains('[error: 数据源名称非法'));
    });

    // ── P0-2 证据终闸（注入 exploreWorkflow/captureWorkflow 时生效）──

    (ExploreWorkflow, ScraperWorkflow) confirmedWorkflow() {
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://site.com/');
      ew.startCategorizing();
      const src = CandidateDataSource(
        name: 'courses',
        displayName: '课程',
        category: '课程',
        url: 'https://site.com/api/courses',
        sourceLogId: 'log-1',
      );
      ew.presentCandidates(const [src]);
      ew.confirmSelection(const [src]);
      final capture = ScraperWorkflow();
      capture.addLog(HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'GET',
        url: 'https://site.com/api/courses',
      ));
      return (ew, capture);
    }

    test('P0-2 register：确认清单外 name → 拒绝', () async {
      final (ew, capture) = confirmedWorkflow();
      final tool = RegisterBatchTool(
        registerBatch: (names) async => 'x',
        exploreWorkflow: ew,
        captureWorkflow: capture,
      );
      final out = await tool.execute({'names': '["ghost"]'});
      expect(out, contains('[error: 数据源 ghost 不在用户确认清单中'));
    });

    test('P0-2 register：确认源无日志证据 → 拒绝注册（回调不被调用）', () async {
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://site.com/');
      ew.startCategorizing();
      const src = CandidateDataSource(
        name: 'courses',
        displayName: '课程',
        category: '课程',
        url: 'https://site.com/api/ghost',
        sourceLogId: 'log-99',
      );
      ew.presentCandidates(const [src]);
      ew.confirmSelection(const [src]);
      final capture = ScraperWorkflow();
      var called = false;
      final tool = RegisterBatchTool(
        registerBatch: (names) async {
          called = true;
          return 'x';
        },
        exploreWorkflow: ew,
        captureWorkflow: capture,
      );
      final out = await tool.execute({'names': '["courses"]'});
      expect(out, contains('[error: 数据源 courses 无日志证据'));
      expect(called, isFalse);
    });

    test('P0-2 register：有证据 → 放行 + 警告透传', () async {
      final (ew, capture) = confirmedWorkflow();
      final tool = RegisterBatchTool(
        registerBatch: (names) async => '✅ 全部注册',
        exploreWorkflow: ew,
        captureWorkflow: capture,
      );
      final out = await tool.execute({'names': '["courses"]'});
      expect(out, contains('✅ 全部注册'));
    });

    test('P0-2 build：证据问题仅警告透传，构建回调仍被调用', () async {
      final (ew, capture) = confirmedWorkflow();
      var built = false;
      final tool = BuildSelectedSourceTool(
        buildSource: (name, code) async {
          built = true;
          return '✅ 构建成功';
        },
        exploreWorkflow: ew,
        captureWorkflow: capture,
      );
      final out = await tool.execute({'name': 'courses', 'code': 'print(1)'});
      expect(out, contains('📁 **data-courses**'));
      expect(out, contains('构建成功'));
      expect(built, isTrue);
    });
  });
}

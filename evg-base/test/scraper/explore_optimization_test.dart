// 探索模式十大优化 Phase 的纯 Dart 单测（Phase 1/2/3/5/9/10）。
//
// 覆盖：
// - Phase 1：configureLimits 更新探索上限
// - Phase 10：explorationSufficient 最小探索量门槛
// - Phase 5：validateFetchedShape 拉取结果字段结构校验
// - Phase 9：list_captured_requests 分页 + read_request_by_id 全文
// - Phase 2/3：verify_login_flow / execute_built_source 工具回调透传
// - Phase 8：explore_network_resources 资源枚举 + 同域过滤
import 'dart:convert';

import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_evidence.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/scraper_explore_tools.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 · configureLimits（探索上限可配置）', () {
    test('更新页数/请求上限并反映到 limits 与守卫', () {
      final w = ExploreWorkflow();
      expect(w.limits.maxPages, 20);
      w.configureLimits(const ExploreLimits(maxPages: 100, maxRequests: 200));
      expect(w.limits.maxPages, 100);
      expect(w.limits.maxRequests, 200);
    });
  });

  group('Phase 10 · explorationSufficient（最小探索量门槛）', () {
    (ExploreWorkflow, DateTime Function()) ready() {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring(startUrl: 'https://site.com/');
      final advance = () => now = now.add(const Duration(seconds: 2));
      return (w, advance);
    }

    test('0 导航 → 不充分', () {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://site.com/');
      expect(w.explorationSufficient, isFalse);
    });

    test('默认门槛 3 页：1-2 页不充分', () {
      final (w, advance) = ready();
      advance();
      w.recordNavigation('https://site.com/a');
      expect(w.explorationSufficient, isFalse);
      advance();
      w.recordNavigation('https://site.com/b');
      expect(w.explorationSufficient, isFalse);
    });

    test('默认门槛 3 页：≥3 个去重页 → 充分', () {
      final (w, advance) = ready();
      advance();
      w.recordNavigation('https://site.com/a');
      advance();
      w.recordNavigation('https://site.com/b');
      advance();
      w.recordNavigation('https://site.com/c');
      expect(w.explorationSufficient, isTrue);
    });

    test('minPagesForCategorize=0 → 始终充分', () {
      final w = ExploreWorkflow(
        limits: const ExploreLimits(minPagesForCategorize: 0),
      );
      w.startExploring();
      expect(w.explorationSufficient, isTrue);
    });
  });

  group('Phase 5 · validateFetchedShape（字段结构校验）', () {
    const fields = [
      CandidateField(name: 'id', type: 'number'),
      CandidateField(name: 'name', type: 'string'),
    ];

    test('嵌套列表对象含全部字段 → 无缺失', () {
      final missing = validateFetchedShape({
        'data': [
          {'id': 1, 'name': 'x'},
        ],
      }, fields);
      expect(missing, isEmpty);
    });

    test('缺字段 → 返回缺失字段名', () {
      final missing = validateFetchedShape({
        'data': [
          {'id': 1},
        ],
      }, fields);
      expect(missing, ['name']);
    });

    test('空字段声明 → 不做校验（不误报）', () {
      final missing = validateFetchedShape({'x': 1}, const []);
      expect(missing, isEmpty);
    });
  });

  group('Phase 9 · list_captured_requests 分页 + read_request_by_id', () {
    test('分页：offset/limit 截取并提示剩余', () async {
      final capture = ScraperWorkflow();
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://a.com/');
      for (var i = 0; i < 3; i++) {
        capture.addLog(HttpRequestLog(
          timestamp: DateTime.now(),
          method: 'GET',
          url: 'https://a.com/api/$i',
        ));
      }
      final tool = ListCapturedRequestsTool(
        captureWorkflow: capture,
        exploreWorkflow: ew,
      );
      final out = await tool.execute({'limit': 2});
      expect(out, contains('api/0'));
      expect(out, contains('api/1'));
      expect(out, isNot(contains('api/2')));
      expect(out, contains('其余 1 条'));
    });

    test('read_request_by_id：命中返回全文，未命中报错', () async {
      final capture = ScraperWorkflow();
      capture.addLog(HttpRequestLog(
        timestamp: DateTime.now(),
        method: 'POST',
        url: 'https://a.com/login',
        responseBody: '{"ok": true, "token": "abc"}',
      ));
      final tool = ReadRequestByIdTool(captureWorkflow: capture);
      final hit = await tool.execute({'id': 'log-1'});
      expect(hit, contains('responseBody'));
      expect(hit, contains('token'));

      final miss = await tool.execute({'id': 'log-99'});
      expect(miss, contains('[error:'));
    });
  });

  group('Phase 2/3 · verify_login_flow / execute_built_source', () {
    test('verify_login_flow 透传执行回调', () async {
      var calledCode = '';
      final tool = VerifyLoginFlowTool(
        runLoginCheck: (code) async {
          calledCode = code;
          return '✅ 登录成功';
        },
      );
      final out = await tool.execute({'code': 'print(1)'});
      expect(out, contains('登录成功'));
      expect(calledCode, 'print(1)');
    });

    test('execute_built_source：非法名称拒绝', () async {
      final tool = ExecuteBuiltSourceTool(
        runBuiltSource: (name) async => '✅ 执行成功',
      );
      final out = await tool.execute({'name': 'bad name'});
      expect(out, contains('[error: 数据源名称非法'));
    });
  });

  group('Phase 8 · explore_network_resources', () {
    test('解析运行时资源并同域过滤', () async {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://a.com/');
      final inner = jsonEncode({
        'count': 2,
        'resources': [
          {'url': 'https://a.com/api/list', 'initiatorType': 'fetch'},
          {'url': 'https://evil.com/x', 'initiatorType': 'xmlhttprequest'},
        ],
      });
      final tool = ExploreNetworkResourcesTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => jsonEncode(inner),
      );
      final out = await tool.execute({});
      expect(out, contains('api/list'));
      expect(out, contains('fetch'));
      expect(out, isNot(contains('evil.com')));
    });
  });
}

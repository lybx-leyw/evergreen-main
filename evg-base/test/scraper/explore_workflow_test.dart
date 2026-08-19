// explore_workflow 测试（Phase 4 · D1-D9）。
//
// 覆盖：
// 1. 状态机流转：idle → exploring → categorizing → confirming → building → registering → done/failed
// 2. GET 守卫拒绝路径（D2）：非 http(s) / 非同域 / 阶段不符
// 3. 上限与节流（D7）：页数上限 / 请求上限提示 / 1s 节流（可注入时钟）
// 4. 工具白名单阶段切换（D9）：全程禁用工具 + 阶段切换矩阵
// 5. 数据源名称校验 + 候选 JSON 往返
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_scope.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('状态机流转（D1/D3-D6）', () {
    test('idle → exploring → categorizing → confirming → building → registering → done', () {
      final w = ExploreWorkflow();
      expect(w.startExploring(startUrl: 'https://site.com/'), isTrue);
      expect(w.phase, ExplorePhase.exploring);
      expect(w.baseHost, 'site.com');

      expect(w.startCategorizing(), isTrue);
      expect(w.phase, ExplorePhase.categorizing);

      const cand = CandidateDataSource(
        name: 'courses',
        displayName: '课程',
        category: '课程',
        url: 'https://site.com/api/courses',
      );
      expect(w.presentCandidates([cand]), isTrue);
      expect(w.phase, ExplorePhase.confirming);
      expect(w.candidates.length, 1);

      expect(w.confirmSelection([cand]), isTrue);
      expect(w.phase, ExplorePhase.building);
      expect(w.selected.length, 1);

      expect(w.startRegistering(), isTrue);
      expect(w.phase, ExplorePhase.registering);

      expect(w.markDone(), isTrue);
      expect(w.phase, ExplorePhase.done);
    });

    test('confirmSelection 空列表拒绝', () {
      final w = ExploreWorkflow();
      w.startExploring();
      w.startCategorizing();
      w.presentCandidates(const [CandidateDataSource(name: 'a', displayName: 'a', category: '', url: 'https://a.com/1')]);
      expect(w.confirmSelection(const []), isFalse);
      expect(w.phase, ExplorePhase.confirming);
    });

    test('markFailed 记录原因', () {
      final w = ExploreWorkflow();
      w.startExploring();
      w.markFailed('无新链接且无候选');
      expect(w.phase, ExplorePhase.failed);
      expect(w.errorMessage, contains('无新链接'));
    });

    test('reset 回到 idle 并清空计数/候选/域名', () {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://site.com/');
      w.recordNavigation('https://site.com/a');
      w.recordNavigation('https://site.com/b');
      w.reset();
      expect(w.phase, ExplorePhase.idle);
      expect(w.uniquePages, 0);
      expect(w.requestsCaptured, 0);
      expect(w.baseHost, '');
    });
  });

  group('GET 守卫拒绝路径（D2/D7 同域）', () {
    test('validateExploreUrl：非 http(s) 协议拒绝', () {
      expect(validateExploreUrl('javascript:alert(1)'), contains('仅允许 http/https'));
      expect(validateExploreUrl('ftp://files.com/a'), contains('仅允许 http/https'));
      expect(validateExploreUrl('about:blank'), contains('仅允许 http/https'));
      expect(validateExploreUrl('data:text/html,x'), contains('仅允许 http/https'));
    });

    test('validateExploreUrl：http/https 放行', () {
      expect(validateExploreUrl('https://site.com/api'), isNull);
      expect(validateExploreUrl('http://site.com/api'), isNull);
    });

    test('validateExploreUrl：同域放行（含子域），跨域拒绝', () {
      expect(validateExploreUrl('https://site.com/a', baseHost: 'site.com'), isNull);
      expect(validateExploreUrl('https://api.site.com/a', baseHost: 'site.com'), isNull);
      expect(validateExploreUrl('https://site.com/a', baseHost: 'api.site.com'), isNull);
      expect(
        validateExploreUrl('https://evil.com/a', baseHost: 'site.com'),
        contains('非同域'),
      );
    });

    test('recordNavigation：跨域导航被拒且不计数', () {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://site.com/');
      expect(w.recordNavigation('https://evil.com/x'), contains('非同域'));
      expect(w.pagesVisited, 0);
      expect(w.requestsCaptured, 0);
    });

    test('recordNavigation：探索阶段之外拒绝', () {
      final w = ExploreWorkflow();
      w.startExploring();
      w.startCategorizing();
      expect(w.recordNavigation('https://site.com/a'), contains('仅探索阶段允许导航'));
    });

    test('recordNavigation：首次导航自动锁定域名', () {
      final w = ExploreWorkflow();
      w.startExploring(); // 未提供 startUrl
      expect(w.baseHost, '');
      expect(w.recordNavigation('https://foo.com/a'), isNull);
      expect(w.baseHost, 'foo.com');
      expect(w.recordNavigation('https://bar.com/b'), contains('非同域'));
    });
  });

  group('上限与节流（D7，可注入时钟）', () {
    test('页数上限：新 URL 触达上限后拒绝 + onLimitReached', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        limits: const ExploreLimits(maxPages: 2, maxRequests: 50),
        clock: () => now,
      );
      String? limitMsg;
      w.onLimitReached = (m) => limitMsg = m;
      w.startExploring();
      expect(w.recordNavigation('https://a.com/1'), isNull);
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://a.com/2'), isNull);
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://a.com/3'), contains('页数上限'));
      expect(w.uniquePages, 2);
      expect(limitMsg, contains('页数上限'));
    });

    test('重复导航不算新页（去 fragment/大小写）', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        limits: const ExploreLimits(maxPages: 3),
        clock: () => now,
      );
      w.startExploring(startUrl: 'https://a.com/');
      expect(w.recordNavigation('https://a.com/1'), isNull);
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://a.com/1#section'), isNull);
      expect(w.uniquePages, 1);
      expect(w.pagesVisited, 2);
    });

    test('1s 节流：间隔不足被拒', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        limits: const ExploreLimits(minNavigateInterval: Duration(seconds: 1)),
        clock: () => now,
      );
      w.startExploring();
      expect(w.recordNavigation('https://a.com/1'), isNull);
      now = now.add(const Duration(milliseconds: 500));
      expect(w.recordNavigation('https://a.com/2'), contains('节流'));
      now = now.add(const Duration(milliseconds: 600)); // 距上次导航 1.1s
      expect(w.recordNavigation('https://a.com/2'), isNull);
    });

    test('请求上限：计数触达上限提示一次（不硬阻断）', () {
      final w = ExploreWorkflow(limits: const ExploreLimits(maxRequests: 3));
      final msgs = <String>[];
      w.onLimitReached = msgs.add;
      w.recordRequest();
      w.recordRequest();
      w.recordRequest();
      w.recordRequest();
      expect(w.requestsCaptured, 4);
      expect(msgs.length, 1);
      expect(msgs.first, contains('请求数上限'));
    });
  });

  group('空转熔断（P1-1，reverse-skill R43 移植）', () {
    /// 推进时钟（越过 1s 节流）后导航。
    String? nav(ExploreWorkflow w, DateTime Function() advance, String url) {
      advance();
      return w.recordNavigation(url);
    }

    test('连续 3 次导航无新页面 → 第 3 次触发熔断提示，之后重复导航被拒', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        clock: () => now,
      );
      w.startExploring(startUrl: 'https://a.com/');
      final stallMsgs = <String>[];
      w.onStallDetected = stallMsgs.add;

      final advance = () => now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://a.com/same'), isNull);
      expect(w.stallDetected, isFalse);
      expect(nav(w, advance, 'https://a.com/same'), isNull);
      expect(w.stallDetected, isFalse);
      // 第 3 次无新页面 → 触发
      expect(nav(w, advance, 'https://a.com/same'), isNull);
      expect(w.stallDetected, isTrue);
      expect(w.stallMessage, contains('连续 3 次导航无新页面'));
      expect(stallMsgs.length, 1);
      // 之后重复导航被拒绝
      expect(nav(w, advance, 'https://a.com/same'), contains('空转熔断'));
      expect(nav(w, advance, 'https://a.com/same#x'), contains('空转熔断'));
      expect(stallMsgs.length, 1); // 回调只触发一次
    });

    test('交替新 URL → 不触发熔断', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring();
      final advance = () => now = now.add(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) {
        expect(nav(w, advance, 'https://a.com/p$i'), isNull);
      }
      expect(w.stallDetected, isFalse);
    });

    test('熔断后访问新页面 → 自动恢复', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring();
      final advance = () => now = now.add(const Duration(seconds: 2));
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      expect(w.stallDetected, isTrue);
      expect(nav(w, advance, 'https://a.com/new-page'), isNull);
      expect(w.stallDetected, isFalse);
      // 恢复后重复导航重新计数（第 3 次才再触发）
      expect(nav(w, advance, 'https://a.com/new-page'), isNull);
      expect(w.stallDetected, isFalse);
    });

    test('自定义阈值：stallThreshold=2 第 2 次触发', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        limits: const ExploreLimits(stallThreshold: 2, stallWindow: 4),
        clock: () => now,
      );
      w.startExploring();
      final advance = () => now = now.add(const Duration(seconds: 2));
      nav(w, advance, 'https://a.com/same');
      expect(w.stallDetected, isFalse);
      nav(w, advance, 'https://a.com/same');
      expect(w.stallDetected, isTrue);
    });

    test('窗口滑动：新页面产出把窗口冲刷后重新计数', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(
        limits: const ExploreLimits(stallThreshold: 3, stallWindow: 4),
        clock: () => now,
      );
      w.startExploring();
      final advance = () => now = now.add(const Duration(seconds: 2));
      // 2 次无新页面后产出 2 个新页面 → 窗口被冲刷，不触发
      nav(w, advance, 'https://a.com/old');
      nav(w, advance, 'https://a.com/old');
      nav(w, advance, 'https://a.com/new1');
      nav(w, advance, 'https://a.com/new2');
      expect(w.stallDetected, isFalse);
    });

    test('restartExploring / reset 清空熔断状态', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring();
      final advance = () => now = now.add(const Duration(seconds: 2));
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      expect(w.stallDetected, isTrue);
      w.restartExploring();
      expect(w.stallDetected, isFalse);
      expect(w.stallMessage, '');
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      nav(w, advance, 'https://a.com/same');
      expect(w.stallDetected, isTrue);
      w.reset();
      expect(w.stallDetected, isFalse);
    });
  });

  group('工具白名单阶段切换（D9）', () {
    test('定向抓取工具在探索模式全程禁用', () {
      const banned = [
        'run_terminal_command',
        'save_credential',
        'run_python_scraper',
        'export_and_register_scraper',
        'get_request_logs',
        'read_request_snapshot',
        'read_existing_credential',
      ];
      for (final phase in ExplorePhase.values) {
        for (final tool in banned) {
          expect(exploreToolAllowedForPhase(tool, phase), isFalse,
              reason: '$tool 应在 $phase 被禁');
        }
      }
    });

    test('只读工具全阶段可用', () {
      const readTools = [
        'ask',
        'guardian_review',
        'guard_override',
        'list_skills',
        'read_workspace_file',
        'list_captured_requests',
        'list_python_capabilities', // P2-1 工具事实源
      ];
      for (final phase in ExplorePhase.values) {
        for (final tool in readTools) {
          expect(exploreToolAllowedForPhase(tool, phase), isTrue,
              reason: '$tool 应在 $phase 可用');
        }
      }
    });

    test('探索工具按阶段切换', () {
      // exploring：枚举/导航
      expect(exploreToolAllowedForPhase('explore_page_links', ExplorePhase.exploring), isTrue);
      expect(exploreToolAllowedForPhase('navigate_get', ExplorePhase.exploring), isTrue);
      // present_data_sources 在 exploring 也放行，由工具内部切到 categorizing
      expect(exploreToolAllowedForPhase('present_data_sources', ExplorePhase.exploring), isTrue);
      // categorizing/confirming：仅 present
      expect(exploreToolAllowedForPhase('present_data_sources', ExplorePhase.categorizing), isTrue);
      expect(exploreToolAllowedForPhase('present_data_sources', ExplorePhase.confirming), isTrue);
      expect(exploreToolAllowedForPhase('build_selected_source', ExplorePhase.confirming), isFalse);
      // building：build + register_batch（工具内先转 registering）
      expect(exploreToolAllowedForPhase('build_selected_source', ExplorePhase.building), isTrue);
      expect(exploreToolAllowedForPhase('register_batch', ExplorePhase.building), isTrue);
      expect(exploreToolAllowedForPhase('navigate_get', ExplorePhase.building), isFalse);
      // registering：register + rebuild
      expect(exploreToolAllowedForPhase('register_batch', ExplorePhase.registering), isTrue);
      expect(exploreToolAllowedForPhase('build_selected_source', ExplorePhase.registering), isTrue);
      // done/failed：修复性重构建/重注册/重新呈现
      expect(exploreToolAllowedForPhase('build_selected_source', ExplorePhase.done), isTrue);
      expect(exploreToolAllowedForPhase('register_batch', ExplorePhase.failed), isTrue);
      // idle：探索工具不可用
      expect(exploreToolAllowedForPhase('navigate_get', ExplorePhase.idle), isFalse);
    });

    test('blockedExploreToolMessage 含工具名与阶段', () {
      final m = blockedExploreToolMessage('run_python_scraper', ExplorePhase.exploring);
      expect(m, contains('run_python_scraper'));
      expect(m, contains('exploring'));
      expect(m, contains('[error:'));
    });
  });

  group('Scope 授权范围（Scope Contract）', () {
    const scope = ExploreScope(
      name: 'ZJU 教务',
      baseHost: 'zju.edu.cn',
      assets: ['zju.edu.cn', '*.zju.edu.cn'],
      paths: ['/course'],
      dataScope: '课程列表',
    );

    test('startExploring 带 scope：授权内 startUrl 放行并锁定 scope', () {
      final w = ExploreWorkflow();
      expect(
        w.startExploring(
            startUrl: 'https://zju.edu.cn/course/1', scope: scope),
        isTrue,
      );
      expect(w.phase, ExplorePhase.exploring);
      expect(w.scope, same(scope));
    });

    test('startExploring 带 scope：越界 startUrl fail-closed', () {
      final w = ExploreWorkflow();
      expect(
        w.startExploring(
            startUrl: 'https://evil.com/course', scope: scope),
        isFalse,
      );
      expect(w.phase, ExplorePhase.idle);
      expect(w.errorMessage, contains('开始探索被拒'));
    });

    test('recordNavigation：授权内放行，越界 host/path 拒绝且不计数', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring(startUrl: 'https://zju.edu.cn/course', scope: scope);
      expect(w.recordNavigation('https://zju.edu.cn/course/2'), isNull);
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://api.zju.edu.cn/course/x'), isNull);

      // 跨域 host：技术同域守卫先于 scope 授权守卫（纵深防御，先技术边界后授权边界）
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://evil.com/course'), contains('非同域导航被拒'));
      // 同域但路径越界：走 scope 授权守卫拒绝
      expect(w.recordNavigation('https://zju.edu.cn/other/x'), contains('超出授权范围'));
      expect(w.pagesVisited, 2); // 仅授权内的 2 次被计数
    });

    test('无 scope：导航仅受技术同域守卫（向后兼容）', () {
      var now = DateTime(2026, 1, 1, 12);
      final w = ExploreWorkflow(clock: () => now);
      w.startExploring(startUrl: 'https://site.com/');
      expect(w.scope, isNull);
      expect(w.recordNavigation('https://site.com/a'), isNull);
      now = now.add(const Duration(seconds: 2));
      expect(w.recordNavigation('https://api.site.com/b'), isNull);
    });

    test('reset 清空 scope', () {
      final w = ExploreWorkflow();
      w.startExploring(startUrl: 'https://zju.edu.cn/course', scope: scope);
      expect(w.scope, isNotNull);
      w.reset();
      expect(w.scope, isNull);
    });
  });

  group('数据源名称与候选模型', () {
    test('sanitizeSourceName：合法/非法', () {
      expect(sanitizeSourceName('courseList'), isNull);
      expect(sanitizeSourceName('course_list-2'), isNull);
      expect(sanitizeSourceName(''), contains('不能为空'));
      expect(sanitizeSourceName('course list'), contains('非法字符'));
      expect(sanitizeSourceName('2courses'), contains('字母开头'));
      expect(sanitizeSourceName('x' * 40), contains('过长'));
    });

    test('CandidateDataSource JSON 往返（method 透传 AI 给定值，默认 GET）', () {
      const c = CandidateDataSource(
        name: 'courses',
        displayName: '课程列表',
        category: '课程',
        url: 'https://site.com/api/courses',
        fields: [CandidateField(name: 'id', type: 'number', description: 'ID')],
      );
      final json = c.toJson();
      final back = CandidateDataSource.fromJson(json);
      expect(back.name, 'courses');
      expect(back.method, 'GET'); // 默认 GET
      expect(back.fields.single.name, 'id');
      // method 透传 AI 给定值（不再强制 GET）
      final forced = CandidateDataSource.fromJson({
        'name': 'x',
        'displayName': 'x',
        'category': '',
        'url': 'https://a.com/1',
        'method': 'POST',
        'fields': <dynamic>[],
      });
      expect(forced.method, 'POST');
    });

    test('fromJson 过滤非法字段', () {
      final c = CandidateDataSource.fromJson(const {
        'name': 'x',
        'displayName': 'x',
        'category': '',
        'url': 'https://a.com/1',
        'fields': [
          {'name': 'ok', 'type': 'string'},
          {'name': '', 'type': 'string'},
          'not-a-map',
        ],
      });
      expect(c.fields.length, 1);
    });
  });
}

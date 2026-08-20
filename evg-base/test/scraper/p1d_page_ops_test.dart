// P1-D/P2-1：AI 页面操作工具（page_click / page_fill / page_submit / page_scroll）单测。
//
// 覆盖：
// - page_click：点击前越界校验（href/formAction 越界拒绝且不触发点击）/ 成功路径 /
//   元素不存在 / 通道不可用
// - page_fill：成功路径（透传 selector/value）
// - page_submit：表单 action 越界拒绝且不提交 / 授权范围内提交成功
// - page_scroll：成功路径
// - 白名单：exploring 阶段放行 4 个新工具；blockedExploreToolMessage 含新工具
// - hooks：page_fill/page_submit 写操作需 guard_override 授权；page_click 只读免授权
import 'dart:convert';

import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_hooks.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_scope.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/scraper_explore_tools.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造已开始探索的工作流（锁定同域 a.com；[scope] 可选）。
ExploreWorkflow readyWorkflow({ExploreScope? scope}) {
  final w = ExploreWorkflow();
  w.startExploring(startUrl: 'https://a.com/', scope: scope);
  return w;
}

/// 快速构造 JSON 字符串（模拟 JS 通道返回值）。
String js(Object? obj) => jsonEncode(obj);

void main() {
  group('P1-D · page_click（点击元素 + 点击前越界校验）', () {
    test('安全按钮点击成功：返回标题/URL/请求数', () async {
      final w = readyWorkflow();
      String? clickedSelector;
      final tool = PageClickTool(
        exploreWorkflow: w,
        // 检查脚本：安全按钮（无 href / formAction）
        evaluateJs: (s) async => js({
          'found': true,
          'tag': 'button',
          'href': '',
          'formAction': '',
          'visible': true,
          'text': '加载更多',
        }),
        jsClick: (sel) async {
          clickedSelector = sel;
          return js({
            'ok': true,
            'tag': 'button',
            'text': '加载更多',
            'title': '列表页',
            'url': 'https://a.com/list',
          });
        },
      );
      final out = await tool.execute({'selector': 'button.load-more'});
      expect(clickedSelector, 'button.load-more');
      expect(out, contains('已点击'));
      expect(out, contains('加载更多'));
      expect(out, contains('列表页'));
    });

    test('元素 href 越界 → 拒绝点击且不触发点击', () async {
      var clicked = false;
      final w = readyWorkflow();
      final tool = PageClickTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({
          'found': true,
          'tag': 'a',
          'href': 'https://evil.com/x',
          'formAction': '',
          'visible': true,
        }),
        jsClick: (sel) async {
          clicked = true;
          return js({'ok': true});
        },
      );
      final out = await tool.execute({'selector': 'a.out'});
      expect(clicked, isFalse);
      expect(out, contains('越界'));
    });

    test('提交按钮所在表单 action 越界 → 拒绝点击', () async {
      var clicked = false;
      final w = readyWorkflow();
      final tool = PageClickTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({
          'found': true,
          'tag': 'button',
          'href': '',
          'formAction': 'https://evil.com/login',
          'visible': true,
        }),
        jsClick: (sel) async {
          clicked = true;
          return js({'ok': true});
        },
      );
      final out = await tool.execute({'selector': 'button.submit'});
      expect(clicked, isFalse);
      expect(out, contains('越界'));
    });

    test('元素不存在 → error 且不点击', () async {
      var clicked = false;
      final w = readyWorkflow();
      final tool = PageClickTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({'found': false, 'message': '未找到元素'}),
        jsClick: (sel) async {
          clicked = true;
          return js({'ok': true});
        },
      );
      final out = await tool.execute({'selector': '#nope'});
      expect(clicked, isFalse);
      expect(out, contains('[error:'));
    });

    test('JS 通道不可用（jsClick=null）→ error', () async {
      final w = readyWorkflow();
      final tool = PageClickTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({'found': true, 'visible': true}),
      );
      final out = await tool.execute({'selector': 'button'});
      expect(out, contains('页面操作通道（page_click）不可用'));
      expect(out, contains('check_explore_ready'));
    });
  });

  group('P1-D · page_fill（填充表单字段）', () {
    test('成功路径：透传 selector/value', () async {
      final w = readyWorkflow();
      String? filledSel;
      String? filledVal;
      final tool = PageFillTool(
        exploreWorkflow: w,
        jsFill: (sel, val) async {
          filledSel = sel;
          filledVal = val;
          return js({
            'ok': true,
            'tag': 'input',
            'type': 'password',
            'title': '登录',
            'url': 'https://a.com/login',
          });
        },
      );
      final out = await tool.execute({'selector': '#pwd', 'value': 'secret'});
      expect(filledSel, '#pwd');
      expect(filledVal, 'secret');
      expect(out, contains('已填充'));
      expect(out, contains('page_submit'));
    });

    test('selector 为空 → error', () async {
      final w = readyWorkflow();
      final tool = PageFillTool(exploreWorkflow: w);
      final out = await tool.execute({'selector': '', 'value': 'x'});
      expect(out, contains('[error: selector 参数为空]'));
    });
  });

  group('P1-D · page_submit（提交表单 + action 越界校验）', () {
    test('表单 action 越界 → 拒绝提交且不触发提交', () async {
      var submitted = false;
      final w = readyWorkflow();
      final tool = PageSubmitTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({
          'found': true,
          'action': 'https://evil.com/login',
          'method': 'post',
        }),
        jsSubmit: (sel) async {
          submitted = true;
          return js({'ok': true});
        },
      );
      final out = await tool.execute({'form': 'form.login'});
      expect(submitted, isFalse);
      expect(out, contains('越界'));
    });

    test('表单 action 在授权范围内 → 提交成功', () async {
      final scope = ExploreScope(
        name: '目标站',
        baseHost: 'a.com',
        assets: const ['a.com'],
        paths: const [],
      );
      final w = readyWorkflow(scope: scope);
      String? submittedForm;
      final tool = PageSubmitTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({
          'found': true,
          'action': 'https://a.com/login',
          'method': 'post',
        }),
        jsSubmit: (sel) async {
          submittedForm = sel;
          return js({
            'ok': true,
            'action': 'https://a.com/login',
            'method': 'post',
            'title': '登录中',
            'url': 'https://a.com/home',
          });
        },
      );
      final out = await tool.execute({'form': 'form.login'});
      expect(submittedForm, 'form.login');
      expect(out, contains('已提交表单'));
      expect(out, contains('list_captured_requests'));
    });

    test('表单不存在 → error 且不提交', () async {
      var submitted = false;
      final w = readyWorkflow();
      final tool = PageSubmitTool(
        exploreWorkflow: w,
        evaluateJs: (s) async => js({'found': false, 'message': '未找到表单'}),
        jsSubmit: (sel) async {
          submitted = true;
          return js({'ok': true});
        },
      );
      final out = await tool.execute({'form': '#nope'});
      expect(submitted, isFalse);
      expect(out, contains('[error:'));
    });
  });

  group('P1-D · page_scroll（滚动触发懒加载）', () {
    test('bottom 滚动成功', () async {
      final w = readyWorkflow();
      String? scrolled;
      final tool = PageScrollTool(
        exploreWorkflow: w,
        jsScroll: (dir) async {
          scrolled = dir;
          return js({
            'ok': true,
            'from': 0,
            'to': 3000,
            'max': 3000,
            'title': '列表',
            'url': 'https://a.com/list',
          });
        },
      );
      final out = await tool.execute({'direction': 'bottom'});
      expect(scrolled, 'bottom');
      expect(out, contains('页面底部'));
      expect(out, contains('懒加载'));
    });

    test('未知方向 → JS 返回错误', () async {
      final w = readyWorkflow();
      final tool = PageScrollTool(
        exploreWorkflow: w,
        jsScroll: (dir) async => js({'ok': false, 'message': '未知方向'}),
      );
      final out = await tool.execute({'direction': 'sideways'});
      expect(out, contains('[error: 滚动失败'));
    });
  });

  group('P1-D · 白名单与守卫', () {
    test('exploring 阶段放行 4 个页面操作工具', () {
      expect(exploreToolAllowedForPhase('page_click', ExplorePhase.exploring), isTrue);
      expect(exploreToolAllowedForPhase('page_fill', ExplorePhase.exploring), isTrue);
      expect(exploreToolAllowedForPhase('page_submit', ExplorePhase.exploring), isTrue);
      expect(exploreToolAllowedForPhase('page_scroll', ExplorePhase.exploring), isTrue);
      // 其他阶段不放行
      expect(exploreToolAllowedForPhase('page_click', ExplorePhase.idle), isFalse);
      expect(exploreToolAllowedForPhase('page_fill', ExplorePhase.building), isFalse);
    });

    test('blockedExploreToolMessage 探索阶段列出页面操作工具', () {
      final msg = blockedExploreToolMessage('navigate_get', ExplorePhase.exploring);
      expect(msg, contains('page_click'));
      expect(msg, contains('page_submit'));
    });

    test('hooks：page_fill 未授权被拒，授权后放行；page_click 只读免授权', () async {
      final capture = ScraperWorkflow();
      final ew = ExploreWorkflow();
      ew.startExploring(startUrl: 'https://a.com/');
      final hooks = ScraperHooks(workflow: capture, exploreWorkflow: ew);

      // page_click：只读操作直接放行
      final (clickBlock, _) = await hooks.preToolUse('page_click', {'selector': 'button'});
      expect(clickBlock, isFalse);

      // page_fill：写操作未授权 → 拦截并指引 guard_override
      final (fillBlock, fillMsg) =
          await hooks.preToolUse('page_fill', {'selector': '#u', 'value': 'x'});
      expect(fillBlock, isTrue);
      expect(fillMsg, contains('授权'));
      expect(fillMsg, contains('guard_override'));

      // guard_override 一次性授权后放行
      capture.requestOverride('page_fill');
      final (fillOk, _) =
          await hooks.preToolUse('page_fill', {'selector': '#u', 'value': 'x'});
      expect(fillOk, isFalse);

      // 授权被消费：再次调用重新拦截
      final (fillAgain, _) =
          await hooks.preToolUse('page_fill', {'selector': '#u', 'value': 'x'});
      expect(fillAgain, isTrue);

      // page_submit 同守卫
      final (subBlock, _) = await hooks.preToolUse('page_submit', {'form': 'form.x'});
      expect(subBlock, isTrue);
    });
  });
}

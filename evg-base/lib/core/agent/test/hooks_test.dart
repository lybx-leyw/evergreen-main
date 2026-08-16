/// ToolHooks 增强测试（Phase 1 core 底座）。
///
/// 覆盖：
/// 1. hookMatches："" / "*" 匹配全部；锚定正则精确匹配
/// 2. postToolUseFailure 事件位
/// 3. CompositeHooks：pre 任一 block 则整体 block；post/failure 全执行；match 过滤
library;

import 'package:test/test.dart';

import '../agent.dart' as agent;

void main() {
  group('hookMatches', () {
    test('空 match 匹配全部', () {
      final h = _RecorderHooks(match: '');
      expect(agent.hookMatches(h, 'run_python_scraper'), isTrue);
      expect(agent.hookMatches(h, 'anything'), isTrue);
    });

    test('* 匹配全部', () {
      final h = _RecorderHooks(match: '*');
      expect(agent.hookMatches(h, 'foo'), isTrue);
    });

    test('锚定正则精确匹配', () {
      final h = _RecorderHooks(match: r'run_.*');
      expect(agent.hookMatches(h, 'run_python_scraper'), isTrue);
      expect(agent.hookMatches(h, 'run_terminal_command'), isTrue);
      expect(agent.hookMatches(h, 'save_credential'), isFalse);
    });

    test('非法正则不抛异常（返回 false）', () {
      final h = _RecorderHooks(match: '(');
      expect(agent.hookMatches(h, 'x'), isFalse);
    });
  });

  group('postToolUseFailure 事件位', () {
    test('失败结果触发 postToolUseFailure', () async {
      final h = _RecorderHooks(match: '');
      await h.postToolUseFailure('run_python_scraper', {'code': 'x'},
          '[error: 执行失败]');
      expect(h.failures, contains('run_python_scraper'));
      expect(h.successes, isEmpty);
    });

    test('成功结果触发 postToolUse', () async {
      final h = _RecorderHooks(match: '');
      await h.postToolUse('run_python_scraper', {'code': 'x'}, '✅ 成功');
      expect(h.successes, contains('run_python_scraper'));
      expect(h.failures, isEmpty);
    });
  });

  group('CompositeHooks', () {
    test('pre 任一 block 则整体 block（取第一个 block 消息）', () async {
      final blocking = _RecorderHooks(match: '', blockOn: 'run_python_scraper');
      final free = _RecorderHooks(match: '');
      final composite = agent.CompositeHooks([blocking, free]);
      final (block, msg) =
          await composite.preToolUse('run_python_scraper', {});
      expect(block, isTrue);
      expect(msg, contains('blocked'));
    });

    test('pre 全部放行则放行', () async {
      final a = _RecorderHooks(match: '');
      final b = _RecorderHooks(match: '');
      final composite = agent.CompositeHooks([a, b]);
      final (block, _) = await composite.preToolUse('save_credential', {});
      expect(block, isFalse);
    });

    test('match 过滤：不匹配的工具不触发', () async {
      final h = _RecorderHooks(match: r'run_python_scraper');
      final composite = agent.CompositeHooks([h]);
      await composite.postToolUse('save_credential', {}, 'ok');
      expect(h.successes, isEmpty);
      await composite.postToolUse('run_python_scraper', {}, 'ok');
      expect(h.successes, contains('run_python_scraper'));
    });

    test('post/failure 全部执行', () async {
      final a = _RecorderHooks(match: '');
      final b = _RecorderHooks(match: '');
      final composite = agent.CompositeHooks([a, b]);
      await composite.postToolUseFailure('x', {}, '[error: e]');
      expect(a.failures, contains('x'));
      expect(b.failures, contains('x'));
    });
  });
}

/// 记录调用、可配置 match / block 的假 hooks。
class _RecorderHooks implements agent.ToolHooks {
  @override
  final String match;
  final String? blockOn;
  final List<String> successes = [];
  final List<String> failures = [];

  _RecorderHooks({this.match = '', this.blockOn});

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    if (name == blockOn) return (true, 'blocked: $name');
    return (false, '');
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    successes.add(name);
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    failures.add(name);
  }
}

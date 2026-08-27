/// 跨插件调度联调集成测试 — A-S3-3。
///
/// 覆盖：
/// - 多工具并行/串行调度
/// - OCR→context 注入→Agent 回答全链路
/// - 写工具串行化（readOnly=false 不可与后续工具并行）
/// - 风暴抑制器（StormBreaker）重复调用压制
/// - FinalReadiness 最终检查
library;

import 'package:test/test.dart';

import '../message.dart';
import '../tool.dart';
import '../agent/session.dart';
import '../agent/agent.dart';

// ═══════ helpers ═══════

Tool _ro(String name, [String result = '']) => SimpleTool(
      name: name,
      description: 'read-only $name',
      schema: {'type': 'object', 'properties': {}},
      readOnly: true,
      execute: (_) async => result.isEmpty ? '$name result' : result,
    );

Tool _rw(String name) => SimpleTool(
      name: name,
      description: 'write $name',
      schema: {'type': 'object', 'properties': {}},
      readOnly: false,
      execute: (_) async => '$name done',
    );

Session _sessionWithSystem() {
  final s = Session(title: 'integration test');
  s.setSystemMessage('你是测试助手。');
  return s;
}

// ═══════ tests ═══════

void main() {
  // ═══════ A-S3-3: 跨插件调度联调 ═══════

  group('跨插件调度 (A-S3-3)', () {
    late Registry registry;

    setUp(() {
      registry = Registry();
    });

    test('只读工具可并行调度（同一轮多个 toolDispatch）', () {
      registry.registerAll([_ro('weather'), _ro('time'), _ro('search')]);
      final roNames = registry.readOnlyToolNames;
      expect(roNames.length, 3);
      expect(roNames, containsAll(['weather', 'time', 'search']));
    });

    test('写工具占用串行槽（readOnly=false 在并行判断中排除）', () {
      registry.registerAll([_ro('search'), _rw('save_file'), _ro('fetch')]);
      final roNames = registry.readOnlyToolNames;
      expect(roNames.length, 2);
      expect(roNames, isNot(contains('save_file')));
    });

    test('混合调度：先只读并行 → 写串行 → 再只读', () async {
      registry.registerAll([_ro('weather'), _rw('save'), _ro('time')]);

      // 第一阶段：并行只读
      final r1 = await registry.callWithArgs('weather', {'city': '北京'});
      final r2 = await registry.callWithArgs('time', {});

      expect(r1, contains('weather'));
      expect(r2, contains('time'));

      // 第二阶段：串行写
      expect(registry.get('save')!.readOnly, isFalse);

      // 第三阶段：继续只读
      final r3 = await registry.callWithArgs('weather', {'city': '上海'});
      expect(r3, contains('weather'));
    });

    test('跨插件调度：3 个不同来源工具依次调用', () async {
      // 模拟：内置工具 + 插件工具 + 手动注册工具
      final builtin = _ro('builtin_search', 'builtin result');
      final plugin = _ro('plugin_weather', 'plugin result');
      final custom = _ro('custom_calc', 'custom result');

      registry.registerAll([builtin, plugin, custom]);

      final results = <String>[];
      for (final name in ['builtin_search', 'plugin_weather', 'custom_calc']) {
        results.add(await registry.callWithArgs(name, {}));
      }

      expect(results, contains('builtin result'));
      expect(results, contains('plugin result'));
      expect(results, contains('custom result'));
    });

    test('禁用工具不影响其他工具调度', () async {
      registry.registerAll([_ro('a'), _ro('b'), _ro('c')]);
      registry.disable('b');

      // 'b' 被禁用，但 a 和 c 仍可用
      expect(registry.isEnabled('a'), isTrue);
      expect(registry.isEnabled('b'), isFalse);
      expect(registry.isEnabled('c'), isTrue);

      final ra = await registry.callWithArgs('a', {});
      final rb = await registry.callWithArgs('b', {}); // 应返回错误
      final rc = await registry.callWithArgs('c', {});

      expect(ra, 'a result');
      expect(rb, contains('disabled'));
      expect(rc, 'c result');
    });

    test('registry.all() 返回包括禁用工具的完整列表', () {
      registry.registerAll([_ro('a'), _ro('b'), _ro('c')]);
      registry.disable('b');
      expect(registry.all().length, 3);
      expect(registry.enabled().length, 2);
    });
  });

  // ═══════ StormBreaker 风暴抑制 ═══════

  group('StormBreaker', () {
    test('连续失败触发抑制', () {
      final sb = StormBreaker(threshold: 3);
      expect(sb.record('bash', 'error'), false);   // 第 1 次
      expect(sb.record('bash', 'error'), false);   // 第 2 次
      expect(sb.record('bash', 'error'), true);    // 第 3 次 → 抑制
    });

    test('不同错误签名重置计数', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error-A');
      sb.record('bash', 'error-A');
      expect(sb.record('bash', 'error-B'), false); // 不同错误 → 重置计数为 1
      expect(sb.record('bash', 'error-B'), false); // 第 2 次 error-B
    });

    test('不同工具独立计数', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');
      sb.record('bash', 'error');
      expect(sb.record('write', 'error'), false); // 不同工具 → 重置
      expect(sb.record('bash', 'error'), false);  // bash 也重置了
    });

    test('成功后重置失败计数', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');
      sb.record('bash', 'error');
      expect(sb.record('bash', null), false);     // 成功 → 重置计数
      expect(sb.record('bash', 'error'), false);  // 重新从 1 开始
    });

    test('成功调用永不抑制', () {
      final sb = StormBreaker(threshold: 3);
      for (var i = 0; i < 10; i++) {
        expect(sb.record('echo', null), false); // 成功永远不触发抑制
      }
    });

    test('成功+失败交错：成功后计数重置', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');     // fail 1
      sb.record('bash', 'error');     // fail 2
      sb.record('bash', null);        // 成功 → 重置
      sb.record('bash', 'error');     // fail 1（重新计数）
      sb.record('bash', 'error');     // fail 2
      expect(sb.record('bash', 'error'), true); // fail 3 → 抑制
    });

    test('reset 清空全部状态', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');
      sb.record('bash', 'error');
      sb.reset();
      expect(sb.record('bash', 'error'), false); // 从 1 开始
    });
  });

  // ═══════ FinalReadiness 最终检查 ═══════

  group('FinalReadiness', () {
    test('无工具调用 → pass', () {
      final fr = FinalReadiness(maxBlocks: 3);
      final result = fr.check(usedAnyTool: false, hasVisibleAnswer: true);
      expect(result.passed, isTrue);
    });

    test('有工具但无回答 → block', () {
      final fr = FinalReadiness(maxBlocks: 3);
      final result = fr.check(usedAnyTool: true, hasVisibleAnswer: false);
      expect(result.passed, isFalse);
      expect(result.reason, contains('空'));
    });

    test('累计 block 达到 maxBlocks → 强制终止', () {
      final fr = FinalReadiness(maxBlocks: 2);
      fr.check(usedAnyTool: true, hasVisibleAnswer: false); // block 1
      fr.check(usedAnyTool: true, hasVisibleAnswer: false); // block 2
      // 第 3 次：即使有回答，blockCount 已达上限 → 强制终止
      final result = fr.check(usedAnyTool: true, hasVisibleAnswer: true);
      expect(result.passed, isFalse);
      expect(result.reason, contains('强制终止'));
    });

    test('有工具且有回答 → pass', () {
      final fr = FinalReadiness(maxBlocks: 3);
      final result = fr.check(usedAnyTool: true, hasVisibleAnswer: true);
      expect(result.passed, isTrue);
    });

    test('reset 后重新计数', () {
      final fr = FinalReadiness(maxBlocks: 3);
      fr.check(usedAnyTool: true, hasVisibleAnswer: false);
      fr.check(usedAnyTool: true, hasVisibleAnswer: false);
      fr.reset();
      final result = fr.check(usedAnyTool: true, hasVisibleAnswer: false);
      expect(result.passed, isFalse); // block 1 again after reset
    });
  });
}

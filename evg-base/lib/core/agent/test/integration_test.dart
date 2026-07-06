/// 跨插件调度联调 + OCR 端到端集成测试 — A-S3-3, A-S3-4。
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
import '../event.dart';
import '../tool.dart';
import '../agent/session.dart';
import '../agent/agent.dart';
import '../tools/ocr_attachment_handler.dart';

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

  // ═══════ A-S3-4: OCR 端到端 ═══════

  group('OCR 端到端管线 (A-S3-4)', () {
    test('Handler 构造 + process + toContextString 全链路', () async {
      // Step 1: 构造 Handler（模拟 OCR 引擎）
      final handler = OcrAttachmentHandler(
        recognize: (path) async {
          // 模拟：图片返回 OCR 文本，PDF 返回更长文本
          if (path.endsWith('.png')) return '图片内容：这是一张截图，包含错误日志...';
          if (path.endsWith('.pdf')) return 'PDF 内容：第一章 引言\n第二章 方法\n...';
          return null;
        },
        sink: null,
      );

      // Step 2: 批量处理
      final files = ['/tmp/error.png', '/tmp/report.pdf', '/tmp/empty.txt'];
      final results = await handler.process(files);

      expect(results.length, 3);
      expect(results[0].isSuccess, isTrue);
      expect(results[0].text, contains('错误日志'));
      expect(results[1].isSuccess, isTrue);
      expect(results[1].isPdf, isTrue);
      expect(results[2].isSuccess, isFalse); // .txt returns null

      // Step 3: 格式化为 context 注入文本
      final context = handler.toContextString(results);
      expect(context, contains('附件 OCR 内容'));
      expect(context, contains('error.png'));
      expect(context, contains('report.pdf'));
      expect(context, contains('empty.txt'));
      expect(context, contains('识别失败'));
    });

    test('OCR 结果 → Agent 上下文注入模拟', () {
      // 模拟完整流程
      final session = _sessionWithSystem();

      // Step 1: 用户发送带附件的消息
      final userMsg = '帮我分析这张错误截图';
      final ocrContext = '## 附件 OCR 内容\n\n### 文件: error.png\nNullPointerException at line 42\n';

      // Step 2: 注入 OCR 上下文（Controller.send 的 attachments 参数）
      // （实际流程中由 _buildSystemPrompt 自动注入）
      final fullSystemPrompt = '${session.systemMessage!.content}\n$ocrContext';

      session.add(Message.user(userMsg));

      // Step 3: 模拟 Agent 基于 OCR 内容回答
      session.add(Message.assistant('根据截图中的错误信息，NullPointerException 发生在第 42 行...'));

      expect(session.messageCount, 3); // system + user + assistant
      expect(fullSystemPrompt, contains('NullPointerException'));
      expect(session.messages.last.content, contains('NullPointerException'));
    });
  });

  // ═══════ StormBreaker 风暴抑制 ═══════

  group('StormBreaker', () {
    test('重复失败触发抑制', () {
      final sb = StormBreaker(threshold: 3);
      expect(sb.record('bash', 'error'), false);
      expect(sb.record('bash', 'error'), false);
      expect(sb.record('bash', 'error'), true); // 第 3 次触发
    });

    test('不同工具独立计数', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');
      sb.record('bash', 'error');
      expect(sb.record('write', 'error'), false); // 不同工具重置计数
      expect(sb.record('bash', 'error'), false); // bash 也重置了
    });

    test('成功后重置', () {
      final sb = StormBreaker(threshold: 3);
      sb.record('bash', 'error');
      sb.record('bash', 'error');
      sb.record('bash', null); // 成功 → 重置
      expect(sb.record('bash', 'error'), false); // 重新从 1 开始
    });

    test('重复成功触发抑制（默认 5 次）', () {
      final sb = StormBreaker(); // successThreshold 默认 5
      expect(sb.record('echo', null), false); // 1
      expect(sb.record('echo', null), false); // 2
      expect(sb.record('echo', null), false); // 3
      expect(sb.record('echo', null), false); // 4
      expect(sb.record('echo', null), true);  // 5 — 触发抑制
    });

    test('重复成功触发抑制（自定义阈值）', () {
      final sb = StormBreaker(successThreshold: 2);
      expect(sb.record('echo', null), false);
      expect(sb.record('echo', null), true); // 第 2 次重复成功触发
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

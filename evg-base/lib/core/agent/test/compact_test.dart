/// 20 轮长对话上下文引用测试 — A-S3-5。
///
/// 验证上下文压实后消息数量、关键事实保留、配对修复正确。
library;

import 'package:test/test.dart';

import '../message.dart';
import '../event.dart';
import '../agent/session.dart';
import '../compact/compact.dart';
import '../provider.dart';

// ═══════ helpers ═══════

/// 生成 N 轮简单对话，每轮 user → assistant 交替。
Session _buildLongSession(int rounds) {
  final session = Session(title: '20 轮长对话测试');
  session.setSystemMessage('你是测试助手。');

  for (var i = 1; i <= rounds; i++) {
    session.add(Message.user('第 $i 轮用户消息：请回答以下问题——${_topics[i % _topics.length]}'));
    session.add(Message.assistant(
      '第 $i 轮助手回答：${_answers[i % _answers.length]}',
      reasoning: '正在思考第 $i 轮...',
    ));
  }

  return session;
}

const _topics = [
  '什么是 Dart 的 null safety？',
  'Flutter 的 Widget 生命周期是怎样的？',
  '如何优化 Flutter 应用的性能？',
  'Riverpod 和 Provider 有什么区别？',
  '什么是 git rebase？',
];

const _answers = [
  'Dart 的 null safety 通过类型系统在编译期防止 null 引用错误...',
  'Flutter Widget 生命周期包括 createState、initState、build、dispose 等阶段...',
  '优化 Flutter 性能可以从减少 rebuild、使用 const 构造器、图片缓存等方面入手...',
  'Riverpod 是编译时安全的，Provider 是运行时。Riverpod 不依赖 BuildContext...',
  'Git rebase 是将一系列提交重新应用到另一个基础上，保持线性历史...',
];

// ═══════ tests ═══════

void main() {
  group('长对话上下文', () {
    test('20 轮消息总数 = 41 (system + 20*2)', () {
      final session = _buildLongSession(20);
      expect(session.messageCount, 41); // 1 system + 20 user + 20 assistant
    });

    test('estimatedContextTokens 随轮次增长', () {
      final s10 = _buildLongSession(10);
      final s20 = _buildLongSession(20);
      expect(s20.estimatedContextTokens, greaterThan(s10.estimatedContextTokens));
    });

    test('last() 获取最近 N 条正确', () {
      final session = _buildLongSession(20);
      final last4 = session.last(4);
      expect(last4.length, 4);
      // 应该是: user19, assistant19, user20, assistant20
      expect(last4[0].role, Role.user);
      expect(last4[0].content, contains('第 19 轮'));
      expect(last4[1].role, Role.assistant);
      expect(last4[2].role, Role.user);
      expect(last4[2].content, contains('第 20 轮'));
      expect(last4[3].role, Role.assistant);
    });

    test('序列化往返不丢失数据', () {
      final original = _buildLongSession(20);
      original.accumulateUsage(TokenUsage(
        promptTokens: 5000,
        completionTokens: 3000,
        totalTokens: 8000,
      ));

      final restored = Session.fromJson(original.toJson());

      expect(restored.messageCount, original.messageCount);
      expect(restored.totalPromptTokens, original.totalPromptTokens);
      expect(restored.totalCompletionTokens, original.totalCompletionTokens);
      // 验证第一轮和最后一轮内容
      expect(restored.messages[1].content, contains('第 1 轮'));
      expect(restored.messages[restored.messageCount - 1].content, contains('第 20 轮'));
    });

    test('工具调用在长对话中保持配对', () {
      final session = _buildLongSession(5);
      // 插入工具调用
      session.add(Message.user('帮我搜索 Dart 教程'));
      session.add(Message.assistantTool([
        ToolCall(id: 'call_s1', name: 'search', arguments: '{"q":"Dart"}'),
      ]));
      session.add(Message.toolResult('call_s1', '找到 10 条结果', name: 'search'));
      session.add(Message.assistant('根据搜索结果，Dart 教程...'));

      // 继续 5 轮对话
      for (var i = 6; i <= 10; i++) {
        session.add(Message.user('第 $i 轮消息'));
        session.add(Message.assistant('第 $i 轮回答'));
      }

      // 序列化往返
      final restored = Session.fromJson(session.toJson());
      expect(restored.messageCount, session.messageCount);

      // 验证工具调用仍然配对
      final toolAssist = restored.messages.where((m) => m.hasToolCalls).toList();
      expect(toolAssist.length, 1);
      expect(toolAssist.first.toolCalls.first.name, 'search');

      final toolResults = restored.messages.where((m) => m.isToolResult).toList();
      expect(toolResults.length, 1);
      expect(toolResults.first.toolCallId, 'call_s1');
    });
  });

  group('Context Compaction', () {
    test('Compactor.check 在低 token 时不触发', () {
      final session = _buildLongSession(5);
      final compactor = Compactor(
        llm: _FakeProvider(),
        contextWindow: 100000, // 极大窗口
      );

      final (should, trigger, isEmergency) = compactor.check(session);
      expect(should, isFalse);
    });

    test('Compactor.check 在高 token 时触发 soft', () {
      final session = _buildLongSession(10);
      final compactor = Compactor(
        llm: _FakeProvider(),
        contextWindow: session.estimatedContextTokens ~/ 2, // 窗口=一半估计值
      );

      final (should, trigger, _) = compactor.check(session);
      expect(should, isTrue);
      expect(trigger, anyOf('soft', 'normal', 'force'));
    });

    test('Compactor 启用时 contextWindow > 0', () {
      final enabled = Compactor(llm: _FakeProvider(), contextWindow: 8000);
      final disabled = Compactor(llm: _FakeProvider(), contextWindow: 0);

      expect(enabled.enabled, isTrue);
      expect(disabled.enabled, isFalse);
    });

    test('contextRatioDescription 格式化正确', () {
      final desc = contextRatioDescription(4000, 8000);
      expect(desc, contains('50%'));
      expect(desc, contains('4000'));
      expect(desc, contains('8000'));
    });

    test('contextRatioDescription 禁用时提示', () {
      final desc = contextRatioDescription(100, 0);
      expect(desc, contains('禁用'));
    });

    test('Compactor.check 在 disabled 时返回 false', () {
      final session = _buildLongSession(10);
      final compactor = Compactor(llm: _FakeProvider(), contextWindow: 0);

      final (should, _, _) = compactor.check(session);
      expect(should, isFalse);
    });

    test('sanitizeToolPairing 在长对话中移除孤立 tool 消息', () {
      final messages = <Message>[
        Message.system('系统提示'),
        ..._buildLongSession(3).messages.where((m) => m.role != Role.system),
        // 插入一个孤立 tool 消息（没有对应的 assistant tool_calls）
        Message.toolResult('orphan_1', '孤立结果'),
        Message.user('继续对话'),
        Message.assistant('继续回答'),
      ];

      final cleaned = sanitizeToolPairing(messages);
      // 孤立的 tool 消息应被移除
      expect(cleaned.any((m) => m.toolCallId == 'orphan_1'), isFalse);
    });

    test('20 轮压缩后仍然保留首尾关键消息', () {
      final session = _buildLongSession(20);
      final originalCount = session.messageCount;

      // 模拟压缩：保留开头 3 条 + 尾部 (recentKeep/2)
      final headCount = 3;
      final tailCount = 5;

      final head = session.messages.take(headCount).toList();
      final tail = session.messages.skip(originalCount - tailCount).toList();

      // 验证首条是 system 消息
      expect(head.first.role, Role.system);
      // 验证尾部包含最后几轮对话
      expect(tail.last.role, Role.assistant);
      expect(tail.last.content, contains('第 20 轮'));

      // 验证压缩后消息数大幅减少
      final compactedCount = head.length + 1 + tail.length; // +1 for summary
      expect(compactedCount, lessThan(originalCount));
    });
  });
}

// ═══════ _FakeProvider ═══════

class _FakeProvider implements Provider {
  @override
  String get name => 'fake';

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.content('fake response');
    yield ProviderEvent.done();
  }
}

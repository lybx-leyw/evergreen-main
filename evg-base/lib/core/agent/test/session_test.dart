/// Session 序列化往返、消息管理、token 统计测试。
library;

import 'package:test/test.dart';

import '../message.dart';
import '../event.dart';
import '../agent/session.dart';

void main() {
  group('Session CRUD', () {
    late Session session;

    setUp(() {
      session = Session(title: '测试');
    });

    test('id auto-generated and unique', () {
      final a = Session();
      final b = Session();
      expect(a.id, isNot(b.id));
      expect(a.id, startsWith('session_'));
    });

    test('add message increments count and updates timestamp', () async {
      // 短暂延时确保时间戳可区分
      await Future.delayed(const Duration(milliseconds: 5));
      final before = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 1));
      session.add(Message.user('hi'));
      expect(session.messageCount, 1);
      expect(session.updatedAt.millisecondsSinceEpoch, greaterThanOrEqualTo(before.millisecondsSinceEpoch));
    });

    test('addAll adds multiple', () {
      session.addAll([Message.user('a'), Message.assistant('b')]);
      expect(session.messageCount, 2);
    });

    test('setSystemMessage replaces/inserts at head', () {
      session.add(Message.user('hi'));
      session.setSystemMessage('sys');
      expect(session.systemMessage!.content, 'sys');
      expect(session.messages.first.role, Role.system);
    });

    test('removeSystemMessage removes it', () {
      session.setSystemMessage('sys');
      session.removeSystemMessage();
      expect(session.systemMessage, isNull);
    });

    test('last returns last N messages', () {
      session.addAll([
        Message.user('1'),
        Message.assistant('2'),
        Message.user('3'),
      ]);
      final last2 = session.last(2);
      expect(last2.length, 2);
      expect(last2.first.content, '2');
      expect(last2.last.content, '3');
    });

    test('last with n >= count returns all', () {
      session.add(Message.user('hi'));
      final all = session.last(10);
      expect(all.length, 1);
    });
  });

  group('Session token tracking', () {
    late Session session;

    setUp(() {
      session = Session();
    });

    test('accumulateUsage sums totals', () {
      session.accumulateUsage(TokenUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      ));
      session.accumulateUsage(TokenUsage(
        promptTokens: 200,
        completionTokens: 100,
        totalTokens: 300,
      ));
      expect(session.totalPromptTokens, 300);
      expect(session.totalCompletionTokens, 150);
      expect(session.totalTokens, 450);
    });

    test('cacheHitRate computes ratio', () {
      session.accumulateUsage(TokenUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        promptCacheHitTokens: 80,
        promptCacheMissTokens: 20,
      ));
      expect(session.cacheHitRate, closeTo(0.8, 0.01));
    });

    test('cacheHitRate returns 0 when no cache data', () {
      session.accumulateUsage(TokenUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      ));
      expect(session.cacheHitRate, 0);
    });

    test('lastUsage stores most recent', () {
      final u = TokenUsage(
        promptTokens: 10,
        completionTokens: 5,
        totalTokens: 15,
      );
      session.accumulateUsage(u);
      expect(session.lastUsage!.totalTokens, 15);
    });
  });

  group('Session serialization', () {
    test('toJson → fromJson roundtrip preserves all fields', () {
      final original = Session(title: '会话1');
      original.setSystemMessage('你是助手。');
      original.add(Message.user('你好'));
      original.add(Message.assistant('你好！'));
      original.accumulateUsage(TokenUsage(
        promptTokens: 50,
        completionTokens: 20,
        totalTokens: 70,
        promptCacheHitTokens: 30,
        promptCacheMissTokens: 20,
      ));

      final json = original.toJson();
      final restored = Session.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.messageCount, original.messageCount);
      expect(restored.totalPromptTokens, original.totalPromptTokens);
      expect(restored.totalCompletionTokens, original.totalCompletionTokens);
      expect(restored.totalCacheHitTokens, original.totalCacheHitTokens);
      expect(restored.totalCacheMissTokens, original.totalCacheMissTokens);
    });

    test('fromJson handles missing fields gracefully', () {
      final s = Session.fromJson({'id': 's1', 'title': 'test'});
      expect(s.id, 's1');
      expect(s.messageCount, 0);
      expect(s.totalTokens, 0);
    });

    test('roundtrip preserves tool calls', () {
      final original = Session();
      original.add(Message.user('搜索'));
      original.add(Message.assistantTool([
        ToolCall(id: 'c1', name: 'search', arguments: '{"q":"x"}'),
      ]));
      original.add(Message.toolResult('c1', '3条结果', name: 'search'));
      original.add(Message.assistant('找到了3条结果'));

      final json = original.toJson();
      final restored = Session.fromJson(json);

      expect(restored.messageCount, 4);
      final toolMsg = restored.messages[1];
      expect(toolMsg.hasToolCalls, isTrue);
      expect(toolMsg.toolCalls[0].name, 'search');

      final resultMsg = restored.messages[2];
      expect(resultMsg.isToolResult, isTrue);
      expect(resultMsg.toolCallId, 'c1');
    });

    test('roundtrip preserves reasoning content', () {
      final original = Session();
      original.add(Message.assistant('回答', reasoning: '深度思考中...'));

      final restored = Session.fromJson(original.toJson());
      expect(restored.messages.first.reasoningContent, '深度思考中...');
    });
  });

  group('Session edge cases', () {
    test('estimatedContextTokens returns non-negative', () {
      final s = Session();
      expect(s.estimatedContextTokens, greaterThanOrEqualTo(0));
    });

    test('estimatedContextTokens grows with content', () {
      final s = Session();
      s.add(Message.user('x' * 1000));
      expect(s.estimatedContextTokens, greaterThan(400));
    });

    test('empty session has null systemMessage', () {
      expect(Session().systemMessage, isNull);
    });

    test('title defaults to empty', () {
      expect(Session().title, '');
    });
  });
}

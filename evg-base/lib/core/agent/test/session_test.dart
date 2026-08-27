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

  // ═══════ R3 会话树形分支 ═══════

  group('Session tree · 轮次感知 add', () {
    test('user 消息开新轮，assistant/tool 归当前轮', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      s.add(Message.user('u2'));
      s.add(Message.assistant('a2'));

      expect(s.roots, hasLength(1));
      expect(s.roots.first.loopId, 0);
      expect(s.roots.first.messages.map((m) => m.content), ['u1', 'a1']);
      expect(s.roots.first.children, hasLength(1));
      expect(
          s.roots.first.children.first.messages.map((m) => m.content),
          ['u2', 'a2']);
      expect(s.activePath, hasLength(2));
      // 双写一致：messages = 活动路径展平
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);
    });

    test('system 消息不单独成轮（与首条 user 同轮）', () {
      final s = Session();
      s.setSystemMessage('sys');
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      expect(s.roots.first.messages.map((m) => m.content), ['sys', 'u1', 'a1']);
      expect(s.roots.first.children, isEmpty);
    });
  });

  group('Session tree · forkRound / switchRound', () {
    test('forkRound 同轮插 sibling 并切换活动路径（同一会话 id）', () {
      final s = Session();
      s.add(Message.user('hi'));
      s.add(Message.assistant('hello'));
      s.add(Message.user('ok'));
      s.add(Message.assistant('怎么了？'));
      final idBefore = s.id;

      expect(s.forkRound(1, 'ok啊'), isTrue);
      expect(s.id, idBefore); // 同一会话，不产生新 session id
      // 新分支为空轮：messages 回到前缀（双写一致）
      expect(s.messages.map((m) => m.content), ['hi', 'hello']);
      expect(s.roots.first.children, hasLength(2));
      expect(s.activePath, hasLength(2));

      // 续写新分支
      s.add(Message.user('ok啊'));
      s.add(Message.assistant('好的'));
      expect(s.messages.map((m) => m.content), ['hi', 'hello', 'ok啊', '好的']);
      // 旧分支内容完整保留
      expect(
          s.roots.first.children.first.messages.map((m) => m.content),
          ['ok', '怎么了？']);
    });

    test('switchRound 切换兄弟分支重建活动路径', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      s.add(Message.user('u2'));
      s.add(Message.assistant('a2'));
      s.forkRound(1, 'u2b');
      s.add(Message.user('u2b'));
      s.add(Message.assistant('a2b'));
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2b', 'a2b']);

      expect(s.switchRound(1, 0), isTrue);
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);

      expect(s.switchRound(1, 1), isTrue);
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2b', 'a2b']);

      // 越界 / 非法参数 → false，状态不变
      expect(s.switchRound(1, 2), isFalse);
      expect(s.switchRound(5, 0), isFalse);
      expect(s.forkRound(5, 'x'), isFalse);
    });

    test('根轮分叉（loopId=0）产生多个根轮', () {
      final s = Session();
      s.add(Message.user('first'));
      s.add(Message.assistant('reply'));
      expect(s.forkRound(0, 'first2'), isTrue);

      expect(s.roots, hasLength(2));
      expect(s.messages, isEmpty); // 新根轮为空
      s.add(Message.user('first2'));
      s.add(Message.assistant('reply2'));
      expect(s.messages.map((m) => m.content), ['first2', 'reply2']);

      // 切回原根轮
      expect(s.switchRound(0, 0), isTrue);
      expect(s.messages.map((m) => m.content), ['first', 'reply']);
    });
  });

  group('Session tree · 序列化往返', () {
    test('toJson/fromJson 树往返（含兄弟分支与活动路径）', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      s.add(Message.user('u2'));
      s.add(Message.assistant('a2'));
      s.forkRound(1, 'u2b');
      s.add(Message.user('u2b'));
      s.add(Message.assistant('a2b'));
      // 活动路径在分支 1
      final json = s.toJson();
      expect(json['tree'], isA<List>());

      final restored = Session.fromJson(json);
      expect(restored.messages.map((m) => m.content),
          ['u1', 'a1', 'u2b', 'a2b']);
      expect(restored.roots, hasLength(1));
      expect(restored.roots.first.children, hasLength(2));
      // 切回分支 0 仍可用（树完整恢复）
      expect(restored.switchRound(1, 0), isTrue);
      expect(restored.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2']);
    });

    test('旧数据（无 tree 字段）→ 推导单路径树，行为等同旧直线', () {
      final json = {
        'id': 's1',
        'title': 'old',
        'messages': [
          {'role': 'user', 'content': 'u1'},
          {'role': 'assistant', 'content': 'a1'},
          {'role': 'user', 'content': 'u2'},
          {'role': 'assistant', 'content': 'a2'},
        ],
      };
      final s = Session.fromJson(json);
      expect(s.roots, hasLength(1));
      expect(s.roots.first.messages.map((m) => m.content), ['u1', 'a1']);
      expect(s.roots.first.children, hasLength(1));
      expect(s.messages, hasLength(4));

      // 续写：新 user 开新轮
      s.add(Message.user('u3'));
      expect(s.messages.map((m) => m.content), ['u1', 'a1', 'u2', 'a2', 'u3']);
      expect(s.roots.first.children.first.children, hasLength(1));

      // 再次序列化：tree 已写入（懒迁移）
      final json2 = s.toJson();
      expect(json2['tree'], isA<List>());
    });

    test('未知字段静默忽略（tree 非 List 视为缺失）', () {
      final s = Session.fromJson({
        'id': 's2',
        'tree': 'corrupt',
        'messages': [
          {'role': 'user', 'content': 'u1'},
        ],
      });
      expect(s.roots, hasLength(1));
      expect(s.messages, hasLength(1));
    });
  });

  group('Session tree · 编辑/压实保持双写一致', () {
    test('removeLastTurn 移除末轮并保持树一致', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      s.add(Message.user('u2'));
      s.add(Message.assistant('a2'));
      final removed = s.removeLastTurn();
      expect(removed, 'u2');
      expect(s.messages.map((m) => m.content), ['u1', 'a1']);
      expect(s.activePath, hasLength(1));
      expect(s.roots.first.children, isEmpty);
    });

    test('removeFrom 移除指定轮及其子树并保持树一致', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.add(Message.assistant('a1'));
      s.add(Message.user('u2'));
      s.add(Message.assistant('a2'));
      s.removeFrom(2); // u2 所在轮
      expect(s.messages.map((m) => m.content), ['u1', 'a1']);
      expect(s.roots.first.children, isEmpty);
    });

    test('setSystemMessage / removeSystemMessage 保持树一致', () {
      final s = Session();
      s.add(Message.user('u1'));
      s.setSystemMessage('sys');
      expect(s.messages.first.role, Role.system);
      expect(s.messages.map((m) => m.content), ['sys', 'u1']);
      expect(s.roots.first.messages.first.content, 'sys');
      s.removeSystemMessage();
      expect(s.messages.map((m) => m.content), ['u1']);
      expect(s.systemMessage, isNull);
    });

    test('rebuildTreeFromMessages（压实）后重建单路径树', () {
      final s = Session();
      s.addAll([
        Message.user('u1'),
        Message.assistant('a1'),
        Message.user('u2'),
        Message.assistant('a2'),
      ]);
      s.forkRound(1, 'u2b');
      s.add(Message.user('u2b'));
      s.add(Message.assistant('a2b'));
      expect(s.roots.first.children, hasLength(2));

      // 模拟压实直接重写 messages
      s.messages
        ..clear()
        ..addAll([Message.user('head'), Message.system('summary')]);
      s.rebuildTreeFromMessages();
      expect(s.roots, hasLength(1));
      expect(s.roots.first.children, isEmpty);
      expect(s.messages.map((m) => m.content), ['head', 'summary']);
    });

    test('adoptFrom 深拷贝树并重建活动路径', () {
      final a = Session();
      a.add(Message.user('u1'));
      a.add(Message.assistant('a1'));
      a.add(Message.user('u2'));
      a.add(Message.assistant('a2'));
      a.forkRound(1, 'u2b');
      a.add(Message.user('u2b'));
      a.add(Message.assistant('a2b'));

      final b = Session();
      b.adoptFrom(a);
      expect(b.messages.map((m) => m.content),
          ['u1', 'a1', 'u2b', 'a2b']);
      expect(b.roots, hasLength(1));
      expect(b.roots.first.children, hasLength(2));
      // 独立副本：切 a 不影响 b
      expect(b.switchRound(1, 0), isTrue);
      expect(a.messages.map((m) => m.content),
          ['u1', 'a1', 'u2b', 'a2b']);
    });
  });
}

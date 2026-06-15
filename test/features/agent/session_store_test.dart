import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/agent/session.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';

void main() {
  group('Session serialize', () {
    test('toJson / fromJson 往返', () {
      final s = Session(title: '测试对话');
      s.add(Message.user('你好'));
      s.add(Message.assistant('你好！有什么可以帮你的？'));
      s.totalPromptTokens = 100;
      s.totalCompletionTokens = 50;

      final json = s.toJson();
      final restored = Session.fromJson(json);

      expect(restored.id, s.id);
      expect(restored.title, '测试对话');
      expect(restored.messages.length, 2);
      expect(restored.messages[0].role, Role.user);
      expect(restored.messages[0].content, '你好');
      expect(restored.totalPromptTokens, 100);
      expect(restored.totalCompletionTokens, 50);
    });

    test('空会话往返', () {
      final s = Session();
      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.id, s.id);
      expect(restored.messages, isEmpty);
    });

    test('工具调用消息往返', () {
      final s = Session();
      s.add(Message.user('查成绩'));
      s.add(Message.assistantTool([
        ToolCall(id: 'c1', name: 'get_scores', arguments: '{}'),
      ]));
      s.add(Message.toolResult('c1', 'GPA: 4.5'));

      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.messages.length, 3);
      expect(restored.messages[1].hasToolCalls, true);
      expect(restored.messages[1].toolCalls[0].name, 'get_scores');
      expect(restored.messages[2].toolCallId, 'c1');
    });

    test('消息排序正确', () {
      final s = Session();
      s.add(Message.user('m1'));
      s.add(Message.assistant('r1'));
      s.add(Message.user('m2'));

      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.messages[0].content, 'm1');
      expect(restored.messages[1].content, 'r1');
      expect(restored.messages[2].content, 'm2');
    });
  });

  group('Session metadata', () {
    test('updatedAt 在 add 后更新', () {
      final s = Session();
      final before = s.updatedAt;
      // 等一下确保时间戳不同
      Future.delayed(const Duration(milliseconds: 1), () {
        s.add(Message.user('test'));
        expect(s.updatedAt.isAfter(before), true);
      });
    });

    test('messageCount 正确', () {
      final s = Session();
      expect(s.messageCount, 0);
      s.add(Message.user('a'));
      expect(s.messageCount, 1);
      s.add(Message.assistant('b'));
      expect(s.messageCount, 2);
    });
  });

  group('Session — 大量消息历史保留', () {
    test('50轮对话全部保留（不压缩）', () {
      final s = Session();
      for (var i = 0; i < 50; i++) {
        s.add(Message.user('问题 $i'));
        s.add(Message.assistant('回答 $i'));
      }
      expect(s.messages.length, 100);
      // 验证首尾完整
      expect(s.messages.first.content, '问题 0');
      expect(s.messages.last.content, '回答 49');
    });

    test('estimatedContextTokens 正确增长', () {
      final s = Session();
      expect(s.estimatedContextTokens, 0);
      s.add(Message.user('你好')); // ~1 char → 0 token approximate
      expect(s.estimatedContextTokens, greaterThan(0));
    });

    test('cacheHitRate 空时返回 0', () {
      final s = Session();
      expect(s.cacheHitRate, 0);
    });
  });
}

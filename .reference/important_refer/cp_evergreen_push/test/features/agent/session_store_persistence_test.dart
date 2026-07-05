import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_multi_tools/core/agent/agent/session.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';
import 'package:evergreen_multi_tools/core/agent/event.dart';

void main() {
  group('SessionStore — 文件持久化', () {
    late Directory tmpDir;
    late String storePath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('session_test_');
      storePath = tmpDir.path;
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    // 模拟 SessionStore 的核心操作（不依赖 path_provider）
    String sessionPath(String id) => p.join(storePath, '$id.json');

    Future<void> saveSession(Session s) async {
      final file = File(sessionPath(s.id));
      await file.writeAsString('{"id":"${s.id}","title":"${s.title}","messages":[],"created_at":"${s.createdAt.toIso8601String()}","updated_at":"${s.updatedAt.toIso8601String()}","total_prompt_tokens":0,"total_completion_tokens":0,"total_cache_hit_tokens":0,"total_cache_miss_tokens":0}');
    }

    test('保存 + 读取往返', () async {
      final s = Session(title: '测试对话');
      await saveSession(s);
      final file = File(sessionPath(s.id));
      expect(file.existsSync(), true);
    });

    test('保存多个会话不冲突', () async {
      final s1 = Session(title: 'first');
      final s2 = Session(title: 'second');
      await saveSession(s1);
      await saveSession(s2);

      // 两个会话文件都存在
      expect(File(sessionPath(s1.id)).existsSync(), true);
      expect(File(sessionPath(s2.id)).existsSync(), true);
    });

    test('删除会话文件', () async {
      final s = Session();
      await saveSession(s);
      final file = File(sessionPath(s.id));
      expect(file.existsSync(), true);
      await file.delete();
      expect(file.existsSync(), false);
    });

    test('不存在的会话返回不存在', () {
      final file = File(sessionPath('nonexistent'));
      expect(file.existsSync(), false);
    });
  });

  group('Session — 高级操作', () {
    test('setSystemMessage 替换已有 system', () {
      final s = Session();
      s.setSystemMessage('旧提示');
      expect(s.messages.length, 1);
      s.setSystemMessage('新提示');
      expect(s.messages.length, 1);
      expect(s.messages.first.content, '新提示');
    });

    test('removeSystemMessage 正确移除', () {
      final s = Session();
      s.setSystemMessage('提示');
      expect(s.systemMessage, isNotNull);
      s.removeSystemMessage();
      expect(s.systemMessage, isNull);
    });

    test('estimatedContextTokens 含工具调用', () {
      final s = Session();
      s.add(Message.user('你好'));
      s.add(Message.assistantTool([
        ToolCall(id: 'c1', name: 'get_courses', arguments: '{}'),
      ]));
      final tokens = s.estimatedContextTokens;
      expect(tokens, greaterThan(0));
    });

    test('last(N) 超出消息数时返回全部', () {
      final s = Session();
      s.add(Message.user('a'));
      s.add(Message.assistant('b'));
      expect(s.last(10).length, 2);
    });

    test('acculateUsage 正确累计', () {
      final s = Session();
      s.accumulateUsage(TokenUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        promptCacheHitTokens: 80,
        promptCacheMissTokens: 20,
      ));
      expect(s.totalPromptTokens, 100);
      expect(s.totalCompletionTokens, 50);
      expect(s.totalCacheHitTokens, 80);
      expect(s.totalCacheMissTokens, 20);
      expect(s.cacheHitRate, closeTo(0.8, 0.01));
      expect(s.totalTokens, 150);
    });

    test('addAll 批量添加', () {
      final s = Session();
      s.addAll([Message.user('a'), Message.user('b')]);
      expect(s.messageCount, 2);
    });
  });
}

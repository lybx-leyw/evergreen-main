import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory_agent.dart';
import 'package:evergreen_multi_tools/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';
import 'package:evergreen_multi_tools/core/agent/provider.dart';

/// 轻量 Mock LLM——返回预设 JSON。
class _MockLlm extends Provider {
  final String _response;
  _MockLlm(this._response);

  @override String get name => 'mock-memory';

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    yield ProviderEvent.content(_response);
    yield ProviderEvent.done();
  }
}

void main() {
  group('MemoryAgent — JSON parsing', () {
    const dir = '.test_mem_agent';

    test('解析合法 JSON remember 动作', () async {
      final llm = _MockLlm('''
      分析完成。
      ```json
      {"actions": [{"type": "remember", "fact": "[2026年6月] 用户是大三学生", "style": false}]}
      ```
      ''');
      final agent = MemoryAgent(llm, dir);
      final (added, updated, removed) = await agent.analyze(
        '我是大三CS专业',
        '好的，大三的CS课程包括...',
        '2026年6月',
      );
      expect(added, 1);
      expect(removed, 0);
    });

    test('解析 set_cardinal 动作', () async {
      final llm = _MockLlm('''
      {"actions": [{"type": "set_cardinal", "trait": "完美主义者"}]}
      ''');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze(
        '我做每件事都要做到最好',
        '追求完美是好事',
        '2026年6月',
      );
      expect(added, 1);
    });

    test('解析 add_central 动作', () async {
      final llm = _MockLlm('''
      {"actions": [{"type": "add_central", "traits": ["勤奋", "严谨", "好奇"]}]}
      ''');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze(
        '我每天学习到很晚，而且很细心',
        '你很努力',
        '2026年6月',
      );
      expect(added, 3);
    });

    test('解析 update 动作（矛盾检测）', () async {
      final store = FileMemoryStore(dir);
      await store.save(Memory(
        name: 'fact-${'[2025年6月] 用户是大二学生'.hashCode.toRadixString(16)}',
        title: '[2025年6月] 用户是大二学生',
        type: MemoryType.user,
        body: '[2025年6月] 用户是大二学生',
        priority: 'high',
      ));

      final llm = _MockLlm('''
      {"actions": [
        {"type": "update", "old_fact": "[2025年6月] 用户是大二学生", "fact": "[2026年6月] 用户是大三学生"}
      ]}
      ''');
      final agent = MemoryAgent(llm, dir);
      final (added, updated, removed) = await agent.analyze(
        '我是大三了',
        '明白了',
        '2026年6月',
      );
      expect(added, 1);
      expect(removed, 1);
    });

    test('解析 forget 动作', () async {
      final store = FileMemoryStore(dir);
      await store.save(Memory(
        name: 'fact-${'[2026年6月] 用户主修数学'.hashCode.toRadixString(16)}',
        title: '[2026年6月] 用户主修数学',
        type: MemoryType.user,
        body: '[2026年6月] 用户主修数学',
        priority: 'high',
      ));

      final llm = _MockLlm('''
      {"actions": [
        {"type": "forget", "old_fact": "[2026年6月] 用户主修数学"}
      ]}
      ''');
      final agent = MemoryAgent(llm, dir);
      final (_, _, removed) = await agent.analyze(
        '我转专业了，不再是数学系',
        '了解了',
        '2026年6月',
      );
      expect(removed, 1);
    });

    test('LLM 返回无 JSON → 0 操作', () async {
      final llm = _MockLlm('没什么可记录的。');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze(
        '今天好累啊',
        '注意休息',
        '2026年6月',
      );
      expect(added, 0);
    });

    test('skip 动作 → 0 操作', () async {
      final llm = _MockLlm('{"actions": [{"type": "skip"}]}');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze(
        '今天天气不错',
        '是的',
        '2026年6月',
      );
      expect(added, 0);
    });
  });

  group('MemoryAgent — compaction', () {
    const dir = '.test_mem_comp';

    test('超 70% 阈值 → 需要压缩', () {
      final llm = _MockLlm('');
      final agent = MemoryAgent(llm, dir);
      expect(agent.shouldCompact(90000, 128000), true);  // 70.3%
    });

    test('低于 70% → 不需要', () {
      final llm = _MockLlm('');
      final agent = MemoryAgent(llm, dir);
      expect(agent.shouldCompact(50000, 128000), false); // 39%
    });

    test('contextWindow=0 → 不需要', () {
      final llm = _MockLlm('');
      final agent = MemoryAgent(llm, dir);
      expect(agent.shouldCompact(100, 0), false);
    });
  });
}

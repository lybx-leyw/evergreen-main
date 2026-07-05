import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/agent/memory/memory_agent.dart';
import 'package:evergreen_multi_tools/core/agent/message.dart';
import 'package:evergreen_multi_tools/core/agent/provider.dart';

class _EdgeLlm extends Provider {
  final String _response;
  _EdgeLlm(this._response);
  @override String get name => 'edge';

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
  group('MemoryAgent — 边界', () {
    const dir = '.test_mem_edge';

    test('LLM 返回空响应 → 0 操作', () async {
      final llm = _EdgeLlm('');
      final agent = MemoryAgent(llm, dir);
      final (a, u, r) = await agent.analyze('我是大三', '好的', '2026年6月');
      expect(a + u + r, 0);
    });

    test('LLM 返回乱码 → 0 操作', () async {
      final llm = _EdgeLlm('这是一段无法解析的文字，没有 JSON 块');
      final agent = MemoryAgent(llm, dir);
      final (a, _, _) = await agent.analyze('test', 'ok', '2026年6月');
      expect(a, 0);
    });

    test('JSON 在代码块中', () async {
      final llm = _EdgeLlm('''
分析完成：
```json
{"actions": [{"type": "remember", "fact": "[2026年6月] 用户是大三学生", "style": false}]}
```
      ''');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze('我是大三', '好的', '2026年6月');
      expect(added, 1);
    });

    test('JSON 无代码块包裹', () async {
      final llm = _EdgeLlm('{"actions": [{"type": "remember", "fact": "[2026年6月] 用户主修数学", "style": false}]}');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze('我是数学系', '好的', '2026年6月');
      expect(added, 1);
    });

    test('同时 remember + forget', () async {
      final llm = _EdgeLlm('''{"actions": [
        {"type": "forget", "old_fact": "[2025年6月] 用户是大二学生"},
        {"type": "remember", "fact": "[2026年6月] 用户是大三学生", "style": false}
      ]}''');
      final agent = MemoryAgent(llm, dir);
      final (added, _, removed) = await agent.analyze('我现在大三了', '好的', '2026年6月');
      expect(added, 1);
      expect(removed, 1);
    });

    test('set_cardinal 覆盖旧的首要特质', () async {
      final llm = _EdgeLlm('{"actions": [{"type": "set_cardinal", "trait": "实干家"}]}');
      final agent = MemoryAgent(llm, dir);
      final (added, _, _) = await agent.analyze('我先做再说', '行动力很强', '2026年6月');
      expect(added, 1);
    });
  });

  group('MemoryAgent — compaction', () {
    const dir = '.test_mem_comp2';

    test('shouldCompact 70% threshold', () {
      final agent = MemoryAgent(_EdgeLlm(''), dir);
      expect(agent.shouldCompact(64000, 128000), false);  // 50%
      expect(agent.shouldCompact(90000, 128000), true);   // 70.3%
      expect(agent.shouldCompact(100000, 128000), true);  // 78%
      expect(agent.shouldCompact(100, 0), false);         // 禁用
    });
  });
}

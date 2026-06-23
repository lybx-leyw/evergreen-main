import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/palace.dart';

void main() {
  group('ConsciousnessEvent 模型', () {
    test('create → 自动生成 UUID + 时间戳', () {
      final event = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '今天想到一个有趣的点子',
      );

      expect(event.id, isNotEmpty);
      expect(event.id.length, greaterThan(20)); // UUID v4
      expect(event.type, EventType.thought);
      expect(event.source, SourceTool.manual);
      expect(event.rawContent, '今天想到一个有趣的点子');
      expect(event.capturedAt, isNotNull);
      expect(event.isVerified, isFalse);
    });

    test('title → rawContent 前 60 字', () {
      final short = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.agent,
        rawContent: '简短想法',
      );
      expect(short.title, '简短想法');

      final long = ConsciousnessEvent.create(
        type: EventType.reflection,
        source: SourceTool.manual,
        rawContent: '这是一个非常长的想法描述' * 10,
      );
      expect(long.title.length, 63); // 60 + "..."
      expect(long.title.endsWith('...'), isTrue);
    });

    test('copyWith → 不可变更新', () {
      final event = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '原始内容',
        tagIds: ['tag1'],
      );

      final updated = event.copyWith(
        type: EventType.lesson,
        aiSummary: 'AI 摘要',
      );

      // 原始不变
      expect(event.type, EventType.thought);
      expect(event.aiSummary, isNull);

      // 新对象有更新字段
      expect(updated.type, EventType.lesson);
      expect(updated.aiSummary, 'AI 摘要');
      expect(updated.rawContent, '原始内容'); // 未改字段保留
      expect(updated.id, event.id); // ID 保留
    });
  });

  group('ConsciousnessEvent 序列化', () {
    test('toFileContent → fromFileContent 往返', () {
      final event = ConsciousnessEvent.create(
        type: EventType.lesson,
        source: SourceTool.agent,
        rawContent: '上午 9-11 点是最佳深度工作时间。\n\n应该严格保护这段时间。',
        aiSummary: '用户认为上午是深度工作的黄金时段',
        tagIds: ['deep-work', 'habit'],
        emotionalValence: 0.7,
        isVerified: true,
      );

      final content = event.toFileContent();

      // 验证 YAML frontmatter 格式
      expect(content.startsWith('---\n'), isTrue);
      expect(content.contains('id: ${event.id}'), isTrue);
      expect(content.contains('event_type: lesson'), isTrue);
      expect(content.contains('source: agent'), isTrue);
      expect(content.contains('ai_summary:'), isTrue);
      expect(content.contains('tags:\n  - deep-work\n  - habit'), isTrue);
      expect(content.contains('emotional_valence: 0.7'), isTrue);
      expect(content.contains('is_verified: true'), isTrue);
      expect(content.contains('上午 9-11 点'), isTrue);

      // 往返
      final parsed = ConsciousnessEvent.fromFileContent(content);
      expect(parsed.id, event.id);
      expect(parsed.type, EventType.lesson);
      expect(parsed.source, SourceTool.agent);
      expect(parsed.rawContent, event.rawContent);
      expect(parsed.aiSummary, event.aiSummary);
      expect(parsed.tagIds, ['deep-work', 'habit']);
      expect(parsed.emotionalValence, 0.7);
      expect(parsed.isVerified, true);
    });

    test('fromFileContent → 处理空字段', () {
      final content = '''---
id: test-id-123
event_type: thought
source: manual
captured_at: 2026-06-23T14:30:00.000
ai_summary: ~
tags: ~
context: ~
linked_events: ~
lesson_id: ~
emotional_valence: ~
is_verified: false
---

一段简单的想法。
''';

      final event = ConsciousnessEvent.fromFileContent(content);
      expect(event.id, 'test-id-123');
      expect(event.type, EventType.thought);
      expect(event.source, SourceTool.manual);
      expect(event.rawContent, '一段简单的想法。');
      expect(event.aiSummary, isNull);
      expect(event.tagIds, isEmpty);
      expect(event.emotionalValence, isNull);
      expect(event.isVerified, isFalse);
    });

    test('fromFileContent → 处理多标签', () {
      final content = '''---
id: test-id-456
event_type: decision
source: agent
captured_at: 2026-06-23T10:00:00.000
tags:
  - 职业规划
  - 决策
ai_summary: ~
linked_events: ~
lesson_id: ~
emotional_valence: ~
is_verified: true
---

决定接受 offer。
''';

      final event = ConsciousnessEvent.fromFileContent(content);
      expect(event.tagIds, ['职业规划', '决策']);
      expect(event.type, EventType.decision);
    });
  });

  group('ContextSnapshot', () {
    test('fromYaml → 解析嵌套 context', () {
      final content = '''---
id: test-id
event_type: thought
source: agent
captured_at: 2026-06-23T14:00:00.000
ai_summary: ~
tags: ~
context:
  active_feature: agent
  active_task: 讨论工作习惯
  recent_actions:
    - 打开 AI 助手
    - 输入问题
  trigger_source: Agent 对话中用户主动触发
linked_events: ~
lesson_id: ~
emotional_valence: ~
is_verified: false
---

测试内容。
''';

      final event = ConsciousnessEvent.fromFileContent(content);
      expect(event.context, isNotNull);
      expect(event.context!.activeFeature, 'agent');
      expect(event.context!.activeTask, '讨论工作习惯');
      expect(event.context!.recentActions, ['打开 AI 助手', '输入问题']);
    });

    test('ContextSnapshot.empty → 无有意义内容', () {
      expect(ContextSnapshot.empty.isEmpty, isTrue);
      final partial = const ContextSnapshot(activeFeature: 'agent');
      expect(partial.isEmpty, isFalse);
    });
  });
}

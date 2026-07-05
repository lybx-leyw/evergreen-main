import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_multi_tools/core/palace/palace.dart';

const _testBase = '.test_palace_store';

String get _eventsDir => p.join(_testBase, 'events');

void main() {
  setUp(() {
    final dir = Directory(_testBase);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  tearDown(() {
    final dir = Directory(_testBase);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('EventStore CRUD', () {
    test('保存事件 → 文件存在 + 可读取', () async {
      final store = EventStore(_eventsDir);
      final event = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '测试事件内容',
        tagIds: ['test'],
      );

      await store.save(event);

      final loaded = store.get(event.id);
      expect(loaded, isNotNull);
      expect(loaded!.id, event.id);
      expect(loaded.rawContent, '测试事件内容');
      expect(loaded.tagIds, ['test']);
    });

    test('保存多条 → all() 返回所有', () async {
      final store = EventStore(_eventsDir);

      for (var i = 0; i < 5; i++) {
        final event = ConsciousnessEvent.create(
          type: EventType.thought,
          source: SourceTool.manual,
          rawContent: '事件 $i',
        );
        await store.save(event);
      }

      expect(store.count, 5);
      final all = store.all();
      expect(all.length, 5);
    });

    test('删除事件 → 文件不存在 + 索引更新', () async {
      final store = EventStore(_eventsDir);
      final event = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '将被删除的事件',
      );
      await store.save(event);
      expect(store.count, 1);

      await store.delete(event.id);
      expect(store.count, 0);
      expect(store.get(event.id), isNull);
    });

    test('更新事件 → 新数据生效', () async {
      final store = EventStore(_eventsDir);
      var event = ConsciousnessEvent.create(
        type: EventType.thought,
        source: SourceTool.manual,
        rawContent: '原始内容',
      );
      await store.save(event);

      event = event.copyWith(
        rawContent: '更新后的内容',
        aiSummary: '新增摘要',
      );
      await store.update(event);

      final loaded = store.get(event.id);
      expect(loaded!.rawContent, '更新后的内容');
      expect(loaded.aiSummary, '新增摘要');
    });
  });

  group('EventStore 索引与查询', () {
    test('按类型过滤 → listByType', () async {
      final store = EventStore(_eventsDir);
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.manual,
        rawContent: '想法 1',
      ));
      await store.save(ConsciousnessEvent.create(
        type: EventType.lesson, source: SourceTool.manual,
        rawContent: '教训 1',
      ));
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.agent,
        rawContent: '想法 2',
      ));

      final thoughts = store.listByType(EventType.thought);
      expect(thoughts.length, 2);

      final lessons = store.listByType(EventType.lesson);
      expect(lessons.length, 1);

      final decisions = store.listByType(EventType.decision);
      expect(decisions, isEmpty);
    });

    test('按标签过滤 → listByTag', () async {
      final store = EventStore(_eventsDir);
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.manual,
        rawContent: '深度工作相关', tagIds: ['deep-work', 'habit'],
      ));
      await store.save(ConsciousnessEvent.create(
        type: EventType.lesson, source: SourceTool.agent,
        rawContent: '效率相关', tagIds: ['efficiency'],
      ));

      expect(store.listByTag('deep-work').length, 1);
      expect(store.listByTag('habit').length, 1);
      expect(store.listByTag('efficiency').length, 1);
      expect(store.listByTag('nonexistent'), isEmpty);
    });

    test('关键词搜索 → 匹配 title + rawContent', () async {
      final store = EventStore(_eventsDir);
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.manual,
        rawContent: '关于深度工作和专注力',
      ));
      await store.save(ConsciousnessEvent.create(
        type: EventType.lesson, source: SourceTool.agent,
        rawContent: '运动可以提高认知能力',
      ));

      expect(store.search('深度').length, 1);
      expect(store.search('认知').length, 1);
      expect(store.search('不存在'), isEmpty);
    });

    test('allTags → 去重排序', () async {
      final store = EventStore(_eventsDir);
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.manual,
        rawContent: 'a', tagIds: ['ccc', 'aaa'],
      ));
      await store.save(ConsciousnessEvent.create(
        type: EventType.lesson, source: SourceTool.agent,
        rawContent: 'b', tagIds: ['bbb', 'aaa'],
      ));

      final tags = store.allTags();
      expect(tags, ['aaa', 'bbb', 'ccc']);
    });

    test('索引文件存在 → 三个 EVENTS_BY_*.md 都被写', () async {
      final store = EventStore(_eventsDir);
      await store.save(ConsciousnessEvent.create(
        type: EventType.thought, source: SourceTool.manual,
        rawContent: '测试', tagIds: ['test'],
      ));

      final byDate = File(p.join(_eventsDir, 'EVENTS_BY_DATE.md'));
      final byType = File(p.join(_eventsDir, 'EVENTS_BY_TYPE.md'));
      final byTag = File(p.join(_eventsDir, 'EVENTS_BY_TAG.md'));

      expect(byDate.existsSync(), isTrue);
      expect(byType.existsSync(), isTrue);
      expect(byTag.existsSync(), isTrue);

      final dateContent = byDate.readAsStringSync();
      expect(dateContent.contains('# Palace 事件索引 — 按日期'), isTrue);
      expect(dateContent.contains('thought'), isTrue);

      final typeContent = byType.readAsStringSync();
      expect(typeContent.contains('## thought'), isTrue);

      final tagContent = byTag.readAsStringSync();
      expect(tagContent.contains('## test'), isTrue);
    });
  });

  group('EventStore 空状态', () {
    test('新 EventStore → count=0, all()=[]', () {
      final store = EventStore(_eventsDir);
      expect(store.count, 0);
      expect(store.all(), isEmpty);
      expect(store.allTags(), isEmpty);
    });

    test('get 不存在的 id → null', () {
      final store = EventStore(_eventsDir);
      expect(store.get('nonexistent-id'), isNull);
    });
  });
}

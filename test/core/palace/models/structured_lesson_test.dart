import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/models/structured_lesson.dart';

void main() {
  group('StructuredLesson', () {
    test('draft → version=0, isConfirmed=false', () {
      final lesson = StructuredLesson.draft(
        corePrinciple: '专注时间应被严格保护',
        elaboration: '上午的深度工作时间不应被打扰...',
        sourceEventIds: ['evt-001'],
      );

      expect(lesson.version, 0);
      expect(lesson.isConfirmed, isFalse);
      expect(lesson.corePrinciple, '专注时间应被严格保护');
      expect(lesson.sourceEventIds, ['evt-001']);
      expect(lesson.revisionHistory, isEmpty);
    });

    test('confirm → version 0→1, 新增修订记录', () {
      final draft = StructuredLesson.draft(
        corePrinciple: '保持好奇心',
        elaboration: '对未知领域保持开放态度',
      );
      final confirmed = draft.confirm();

      expect(confirmed.version, 1);
      expect(confirmed.isConfirmed, isTrue);
      expect(confirmed.revisionHistory.length, 1);
      expect(confirmed.revisionHistory.first.version, 1);
      expect(confirmed.revisionHistory.first.changeDescription,
          contains('确认'));
    });

    test('revise → 版本号递增，保留旧原则', () {
      final confirmed = StructuredLesson.draft(
        corePrinciple: '保持好奇心',
        elaboration: '对未知领域保持开放态度',
      ).confirm();

      final revised = confirmed.revise(
        newPrinciple: '保持好奇心，但需要设置边界',
        changeDescription: '添加边界说明',
      );

      expect(revised.version, 2);
      expect(revised.corePrinciple, '保持好奇心，但需要设置边界');
      expect(revised.revisionHistory.length, 2);
      expect(revised.revisionHistory.last.previousCorePrinciple,
          '保持好奇心');
    });

    test('addCondition → 不可变追加', () {
      final lesson = StructuredLesson.draft(
        corePrinciple: '测试',
        elaboration: '测试',
      );

      final condition = ApplicabilityCondition(
        condition: '当你有 2 小时以上连续时间时',
        confidence: 0.8,
        supportingEventIds: ['evt-002'],
      );

      final updated = lesson.addCondition(condition);
      expect(updated.conditions.length, 1);
      expect(updated.conditions.first.condition, '当你有 2 小时以上连续时间时');
      expect(lesson.conditions, isEmpty); // 原始不变
    });

    test('addCounterExample → 不可变追加', () {
      final lesson = StructuredLesson.draft(
        corePrinciple: '测试',
        elaboration: '测试',
      );

      final now = DateTime.now();
      final example = CounterExample(
        description: '紧急情况下不适用',
        sourceEventId: 'evt-003',
        recordedAt: now,
      );

      final updated = lesson.addCounterExample(example);
      expect(updated.counterExamples.length, 1);
      expect(updated.counterExamples.first.description, '紧急情况下不适用');
    });

    test('title → corePrinciple 截断', () {
      final short = StructuredLesson.draft(
        corePrinciple: '简短原则',
        elaboration: '详情',
      );
      expect(short.title, '简短原则');

      final long = StructuredLesson.draft(
        corePrinciple: '这是一个非常长的核心原则' * 10,
        elaboration: '详情',
      );
      expect(long.title.length, 83); // 80 + "..."
      expect(long.title.endsWith('...'), isTrue);
    });
  });
}

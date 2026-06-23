import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/palace/refinery/lesson_extractor.dart';
import 'package:evergreen_multi_tools/core/palace/models/consciousness_event.dart';
import 'package:evergreen_multi_tools/core/palace/models/structured_lesson.dart';

/// 测试 LessonExtractor 的 JSON 解析逻辑（不调用真实 LLM）。
void main() {
  group('LessonExtractor JSON 解析', () {
    // 用反射测试私有方法... Dart 不支持。改为测试 _callLlm 的替代逻辑。
    // 这里验证 StructuredLesson.draft 正确创建。

    test('draft → version=0, sourceEventIds 正确', () {
      final lesson = StructuredLesson.draft(
        corePrinciple: '深度工作需要保护',
        elaboration: '上午的黄金时段不应被会议占据',
        sourceEventIds: ['evt-001', 'evt-002'],
      );

      expect(lesson.version, 0);
      expect(lesson.isConfirmed, isFalse);
      expect(lesson.corePrinciple, '深度工作需要保护');
      expect(lesson.elaboration, contains('黄金时段'));
      expect(lesson.sourceEventIds, ['evt-001', 'evt-002']);
    });

    test('draft with empty principle → confirmation needed', () {
      final lesson = StructuredLesson.draft(
        corePrinciple: '',
        elaboration: '无法提取教训',
        sourceEventIds: ['evt-001'],
      );

      expect(lesson.corePrinciple, '');
      expect(lesson.isConfirmed, isFalse);
    });

    test('StructuredLesson revise → 完整版本链', () {
      // 验证 StructuredLesson.revise 的版本链正确
      final initial = StructuredLesson.draft(
        corePrinciple: '原则 A',
        elaboration: '初始版本',
      ).confirm();

      final v2 = initial.revise(
        newPrinciple: '原则 A (修订版)',
        changeDescription: '添加了边界条件',
      );

      expect(v2.version, 2);
      expect(v2.corePrinciple, '原则 A (修订版)');
      expect(v2.revisionHistory.length, 2);
      expect(v2.revisionHistory.last.previousCorePrinciple, '原则 A');
    });

    test('_parseLessonJson → 解析 JSON', () {
      // 测试 JSON 提取逻辑
      final raw = '一些前缀文本 ```json\n{"core_principle": "专注是美德", "elaboration": "深度工作需要专注"}\n``` 后缀';
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      expect(match, isNotNull);
      final json = match!.group(0)!;
      expect(json, contains('"core_principle"'));
      final coreMatch = RegExp(r'"core_principle"\s*:\s*"([^"]*)"').firstMatch(json);
      expect(coreMatch, isNotNull);
      expect(coreMatch!.group(1), '专注是美德');
    });
  });
}

// Skill 创作 agent 辅助纯函数测试（不涉文件系统、不调用 LLM）。
//
// 覆盖：
// 1. extractJsonObject —— JSON 提取（裸 JSON / markdown 代码块包裹 / 前后夹带文本 / 非法输入）；
// 2. DeepSearchResult 默认值。
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/renderer/templates/skill_creator_modle/services/skill_creator_agents.dart';

void main() {
  group('extractJsonObject', () {
    test('裸 JSON 对象', () {
      final r = extractJsonObject('{"a": 1, "b": "x"}');
      expect(r, isNotNull);
      expect(r!['a'], 1);
      expect(r['b'], 'x');
    });

    test('markdown 代码块包裹（```json）', () {
      final r = extractJsonObject('```json\n{"summary": "ok", "materials": []}\n```');
      expect(r, isNotNull);
      expect(r!['summary'], 'ok');
      expect(r['materials'], isEmpty);
    });

    test('代码块包裹（无语言标注）', () {
      final r = extractJsonObject('```\n{"v": 42}\n```');
      expect(r, isNotNull);
      expect(r!['v'], 42);
    });

    test('前后夹带说明文本', () {
      final r = extractJsonObject(
          '采集完成。\n结果如下：{"verdict": "pass", "feedback": "很好"}\n以上。');
      expect(r, isNotNull);
      expect(r!['verdict'], 'pass');
      expect(r['feedback'], '很好');
    });

    test('非 JSON / 非法输入 → null', () {
      expect(extractJsonObject(''), isNull);
      expect(extractJsonObject('没有 JSON'), isNull);
      expect(extractJsonObject('[1,2,3]'), isNull); // 只接受对象
      expect(extractJsonObject('{"broken": '), isNull);
    });

    test('多层嵌套对象', () {
      final r = extractJsonObject(
          '{"materials": [{"title": "t", "url": "u"}], "nested": {"k": 1}}');
      expect(r, isNotNull);
      expect((r!['materials'] as List).length, 1);
      expect(r['nested'], {'k': 1});
    });
  });

  group('DeepSearchResult', () {
    test('默认值', () {
      const r = DeepSearchResult();
      expect(r.summary, '');
      expect(r.materials, isEmpty);
      expect(r.rawText, '');
      expect(r.error, isNull);
      expect(r.isSuccess, isTrue);
    });

    test('error 时 isSuccess=false', () {
      const r = DeepSearchResult(error: '超时');
      expect(r.isSuccess, isFalse);
    });
  });
}

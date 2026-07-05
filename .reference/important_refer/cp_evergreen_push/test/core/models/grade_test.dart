import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/grade.dart';

const validGradeJson = {
  'xkkh': '(2024-2025-2)-CS101-001',
  'kcmc': '数据结构基础',
  'xf': '4.0',
  'cj': '92',
  'jd': '4.8',
};

const emptyGradeJson = <String, dynamic>{};

const partialGradeJson = {
  'kcmc': '操作系统',
};

const brokenGradeJson = {
  'xkkh': 12345,
  'kcmc': '编译原理',
  'xf': 'not_a_number',
  'cj': null,
  'jd': ['array'],
};

void main() {
  group('Grade.fromJson', () {
    test('合法 JSON → 所有字段正确 + fivePointSource = jd', () {
      final g = Grade.fromJson(validGradeJson);
      expect(g.id, '(2024-2025-2)-CS101-001');
      expect(g.name, '数据结构基础');
      expect(g.credit, 4.0);
      expect(g.original, '92');
      expect(g.fivePoint, 4.8);
      expect(g.fivePointSource, FivePointSource.jd);
    });

    test('空 {} → 不抛异常，默认值', () {
      final g = Grade.fromJson(emptyGradeJson);
      expect(g.id, '');
      expect(g.name, '未命名课程');
      expect(g.credit, 0.0);
      expect(g.original, '');
      expect(g.fivePoint, 0.0);
      expect(g.fivePointSource, FivePointSource.fallback);
    });

    test('字段缺失 → 缺失字段为默认值', () {
      final g = Grade.fromJson(partialGradeJson);
      expect(g.name, '操作系统');
      expect(g.id, '');
      expect(g.credit, 0.0);
      expect(g.fivePointSource, FivePointSource.fallback);
    });

    test('类型错误 → fallback，不抛异常', () {
      final g = Grade.fromJson(brokenGradeJson);
      expect(g.name, '编译原理');
      expect(g.credit, 0.0);
      expect(g.original, '');
      expect(g.fivePoint, 0.0);
      expect(g.fivePointSource, FivePointSource.fallback);
    });

    test('jd 字段缺失时 fivePointSource = fallback', () {
      final g = Grade.fromJson({'kcmc': '测试', 'cj': '优'});
      expect(g.fivePoint, 5.0); // "优" → 5.0
      expect(g.fivePointSource, FivePointSource.fallback);
    });
  });
}

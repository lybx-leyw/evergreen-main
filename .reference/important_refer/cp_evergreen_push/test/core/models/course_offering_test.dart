import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/course_offering.dart';

const validCourseOfferingJson = {
  'kcdm': 'CS101',
  'kcmc': '数据结构基础',
  'jsxm': '张三',
  'skdd': '紫金港东1A-301',
  'sksj': '周一 3-4节',
  'xf': '4.0',
  'zxss': '64',
  'kkxy': '计算机学院',
  'kcxz': '必修',
  'kclb': '专业核心',
  'kcgs': '理工类',
  'xn': '2024-2025',
  'xxq': '2',
  'kssj': '2025-06-20',
  'zymc': '计算机科学与技术',
  'jxjhh': '2024-001',
  'xkkh': '(2024-2025-2)-CS101-001',
};

const emptyJson = <String, dynamic>{};

const brokenJson = {
  'kcmc': '编译原理',
  'xf': 'not_a_number',
  'zxss': null,
  'kcdm': null,
};

void main() {
  group('CourseOffering.fromJson', () {
    test('合法 JSON → 所有字段正确', () {
      final c = CourseOffering.fromJson(validCourseOfferingJson);
      expect(c.courseName, '数据结构基础');
      expect(c.teacher, '张三');
      expect(c.credits, 4.0);
      expect(c.totalHours, 64);
      expect(c.college, '计算机学院');
      expect(c.courseType, '必修');
      expect(c.academicYear, '2024-2025');
    });

    test('空 {} → 不抛异常', () {
      final c = CourseOffering.fromJson(emptyJson);
      expect(c.courseName, '未命名课程');
      expect(c.credits, 0);
      expect(c.totalHours, 0);
    });

    test('类型错误 → fallback', () {
      final c = CourseOffering.fromJson(brokenJson);
      expect(c.courseName, '编译原理');
      expect(c.credits, 0);
      expect(c.totalHours, 0);
      expect(c.courseCode, '');
    });
  });
}

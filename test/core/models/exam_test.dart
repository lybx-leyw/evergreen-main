import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/exam.dart';

const validZdbkExamJson = {
  'xkkh': '(2024-2025-2)-CS101-001',
  'kcmc': '数据结构基础',
  'cdmc': '紫金港东1A-301',
  'kssj': '2025年06月20日(14:00-16:40)',
  'jssj': 'null',
  'zwh': 'A12',
};

const emptyJson = <String, dynamic>{};

const brokenDateJson = {
  'xkkh': 'CS101',
  'kcmc': '操作系统',
  'kssj': '2025年13月00日(14:00-16:40)',
};

const validCoursesExamJson = {
  'id': 'exam-001',
  'title': '操作系统期末',
  'location': '紫金港西1-201',
  'start_at': '2025-06-20T14:00:00',
  'end_at': '2025-06-20T16:40:00',
};

void main() {
  group('Exam.fromZdbk', () {
    test('合法 JSON → 所有字段正确', () {
      final e = Exam.fromZdbk(validZdbkExamJson);
      expect(e.name, '数据结构基础');
      expect(e.location, '紫金港东1A-301');
      expect(e.seatNumber, 'A12');
      expect(e.source, 'zdbk');
      expect(e.startTime, isNotNull);
      expect(e.startTime!.month, 6);
      expect(e.startTime!.day, 20);
      expect(e.startTime!.hour, 14);
    });

    test('空 {} → 不抛异常', () {
      final e = Exam.fromZdbk(emptyJson);
      expect(e.name, '未命名考试');
      expect(e.startTime, isNull);
      expect(e.endTime, isNull);
    });

    test('异常日期格式 → 不崩溃，clamp 到合法值', () {
      final e = Exam.fromZdbk(brokenDateJson);
      expect(e.startTime, isNotNull);
      // month=13 → clamped to 12, day=0 → clamped to 1
      expect(e.startTime!.month, 12);
      expect(e.startTime!.day, 1);
    });
  });

  group('Exam.fromCourses', () {
    test('合法 JSON → 所有字段正确', () {
      final e = Exam.fromCourses(validCoursesExamJson);
      expect(e.name, '操作系统期末');
      expect(e.location, '紫金港西1-201');
      expect(e.source, 'courses');
      expect(e.startTime, isNotNull);
    });

    test('空 {} → 不抛异常', () {
      final e = Exam.fromCourses(emptyJson);
      expect(e.name, '');
      expect(e.startTime, isNull);
    });
  });
}

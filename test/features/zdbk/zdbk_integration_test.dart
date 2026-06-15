import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/grade.dart';
import 'package:evergreen_multi_tools/core/models/exam.dart';
import 'package:evergreen_multi_tools/core/models/timetable_session.dart';

void main() {
  group('ZDBK integration', () {
    test('Grade 模型正确解析 ZDBK JSON', () {
      final json = {
        'kcmc': '高等数学',
        'jd': '4.5',
        'cj': '90',
        'xf': '3.0',
      };
      final grade = Grade.fromJson(json);
      expect(grade.fivePoint, 4.5);
      expect(grade.hundredPoint, 90.0);
      expect(grade.credit, 3.0);
    });

    test('Grade 容错空 JSON', () {
      final grade = Grade.fromJson({});
      expect(grade.fivePoint, 0.0);
      expect(grade.hundredPoint, 0.0);
    });

    test('Exam 模型正确解析 ZDBK JSON', () {
      final json = {
        'ksmc': '高等数学期末考试',
        'kssj': '2026-06-25 14:00',
      };
      final exam = Exam.fromZdbk(json);
      expect(exam.startTime, isNotNull);
    });

    test('TimetableSession 区间节次展开', () {
      final s = TimetableSession.fromZdbkJson({
        'kcb': '数据结构',
        'djj': '3',
        'skcd': '2',
        'xqj': '2',
      });
      expect(s.periods, containsAll([3, 4]));
      expect(s.dayOfWeek, 2);
    });
  });
}

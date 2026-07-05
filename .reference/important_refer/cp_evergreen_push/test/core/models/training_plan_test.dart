import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/models/training_plan.dart';

void main() {
  group('TrainingPlan', () {
    test('fromJson 合法 JSON → 所有字段正确', () {
      final plan = TrainingPlan.fromJson({
        'pyfabh': '2025-001',
        'pyfamc': '计算机科学与技术培养方案',
        'zymc': '计算机科学与技术',
        'nj': '2025',
        'xy': '计算机科学与技术学院',
        'pycc': '本科',
        'xz': '4',
        'minxf': 160.0,
        'yxxf': 85.5,
        'zt': '1',
        'ksxq': '2025-2026-1',
      });
      expect(plan.planNo, '2025-001');
      expect(plan.planName, '计算机科学与技术培养方案');
      expect(plan.major, '计算机科学与技术');
      expect(plan.grade, '2025');
      expect(plan.college, '计算机科学与技术学院');
      expect(plan.level, '本科');
      expect(plan.duration, '4');
      expect(plan.minCredits, 160.0);
      expect(plan.earnedCredits, 85.5);
      expect(plan.status, '1');
      expect(plan.remarks, '');
    });

    test('fromJson 空 {} → 不抛异常，默认值正确', () {
      final plan = TrainingPlan.fromJson({});
      expect(plan.planName, '未命名方案');
      expect(plan.planNo, isNull);
      expect(plan.major, isNull);
      expect(plan.minCredits, 0);
      expect(plan.earnedCredits, 0);
    });

    test('fromJson 类型错误 → fallback，不抛异常', () {
      final plan = TrainingPlan.fromJson({
        'pyfamc': 12345,
        'minxf': '不是数字',
        'nj': null,
      });
      expect(plan.planName, '12345');
      expect(plan.minCredits, 0);
      expect(plan.grade, isNull);
    });

    test('toShortDescription 包含所有非空字段', () {
      final plan = TrainingPlan(
        planNo: 'P001',
        planName: '数学与应用数学',
        major: '数学',
        grade: '2024',
        college: '数学科学学院',
        minCredits: 150,
      );
      final desc = plan.toShortDescription();
      expect(desc, contains('数学与应用数学'));
      expect(desc, contains('数学'));
      expect(desc, contains('2024'));
      expect(desc, contains('150')); // minCredits 是 double，显示为 150.0
      expect(desc, contains('数学科学学院'));
    });

    test('toShortDescription 空字段不包含', () {
      final plan = TrainingPlan(planName: '空方案');
      final desc = plan.toShortDescription();
      expect(desc, '空方案');
    });

    test('fromJson 学分字符串 → 正确解析', () {
      final plan = TrainingPlan.fromJson({
        'pyfamc': '测试',
        'minxf': '170.5',
      });
      expect(plan.minCredits, 170.5);
    });

    test('fromJson 大数字学分 → 正确解析', () {
      final plan = TrainingPlan.fromJson({
        'pyfamc': '测试',
        'minxf': 200,
        'yxxf': 100,
      });
      expect(plan.minCredits, 200);
      expect(plan.earnedCredits, 100);
    });

    test('status 不同值', () {
      expect(TrainingPlan.fromJson({'pyfamc': 'a', 'zt': '1'}).status, '1');
      expect(TrainingPlan.fromJson({'pyfamc': 'b', 'zt': '2'}).status, '2');
      expect(TrainingPlan.fromJson({'pyfamc': 'c'}).status, '');
    });
  });
}

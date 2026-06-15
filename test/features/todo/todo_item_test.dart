import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/todo/services/todo_service.dart';

void main() {
  group('TodoItem', () {
    test('source 默认 courses', () {
      final t = TodoItem(
          id: '1', title: '作业', courseName: '数学', type: 'homework');
      expect(t.source, 'courses');
    });

    test('source pintia → sourceLabel = PTA', () {
      final t = TodoItem(
          id: 'p-1',
          title: 'PTA 考试',
          courseName: 'PTA',
          type: 'exam',
          source: 'pintia');
      expect(t.sourceLabel, 'PTA');
    });

    test('source courses → sourceLabel = 学在浙大', () {
      final t = TodoItem(
          id: '1', title: '作业', courseName: '数学', type: 'homework');
      expect(t.sourceLabel, '学在浙大');
    });

    test('isExpired — 昨天截止 → true', () {
      final yesterday =
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      final t = TodoItem(
          id: '1',
          title: '过期作业',
          courseName: '数学',
          type: 'homework',
          deadline: yesterday);
      expect(t.isExpired, isTrue);
    });

    test('isExpired — 明天截止 → false', () {
      final tomorrow =
          DateTime.now().add(const Duration(days: 1)).toIso8601String();
      final t = TodoItem(
          id: '1',
          title: '未来作业',
          courseName: '数学',
          type: 'homework',
          deadline: tomorrow);
      expect(t.isExpired, isFalse);
    });

    test('isExpired — 无 deadline → false', () {
      final t = TodoItem(
          id: '1', title: '无期限', courseName: '数学', type: 'homework');
      expect(t.isExpired, isFalse);
    });

    test('daysUntil 计算正确', () {
      // 使用 +25h 确保即使有毫秒级偏差也 > 1 整天
      final tomorrow =
          DateTime.now().add(const Duration(hours: 25)).toIso8601String();
      final t = TodoItem(
          id: '1',
          title: '明天',
          courseName: '数学',
          type: 'homework',
          deadline: tomorrow);
      expect(t.daysUntil, greaterThanOrEqualTo(1));
    });

    test('statusLabel — 已过期', () {
      final yesterday =
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      final t = TodoItem(
          id: '1',
          title: '过期',
          courseName: '数学',
          type: 'homework',
          deadline: yesterday);
      expect(t.statusLabel, '已过期');
    });

    test('typeLabel — homework → 作业', () {
      final t = TodoItem(
          id: '1', title: '作业', courseName: '数学', type: 'homework');
      expect(t.typeLabel, '作业');
    });

    test('typeLabel — exam → 考试', () {
      final t = TodoItem(
          id: '1', title: '考试', courseName: '数学', type: 'exam');
      expect(t.typeLabel, '考试');
    });
  });
}

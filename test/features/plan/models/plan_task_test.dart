import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/plan/models/plan_task.dart';
import 'package:evergreen_multi_tools/features/todo/services/todo_service.dart';

void main() {
  group('PlanTask model', () {
    test('PlanTask.create 生成 UUID 和默认值', () {
      final t = PlanTask.create(title: '复习数学');
      expect(t.id, isNotEmpty);
      expect(t.id.length, greaterThan(10));
      expect(t.title, '复习数学');
      expect(t.source, 'manual');
      expect(t.completed, false);
      expect(t.notes, isEmpty);
      expect(t.deadline, isNull);
      expect(t.createdAt, isNotNull);
    });

    test('PlanTask.create 带 deadline 和 notes', () {
      final d = DateTime(2026, 7, 1);
      final t = PlanTask.create(title: '考试', deadline: d, notes: '重点复习');
      expect(t.deadline, d);
      expect(t.notes, '重点复习');
    });

    test('PlanTask.fromTodoItem 正确转换', () {
      final todo = TodoItem(
        id: 't1', title: '数据结构作业', courseName: '数据结构',
        type: 'homework', deadline: '2026-07-01T00:00:00.000',
        isSubmitted: true, source: 'courses',
      );
      final t = PlanTask.fromTodoItem(todo);
      expect(t.title, '数据结构作业');
      expect(t.source, 'imported');
      expect(t.completed, true);
      expect(t.notes, contains('数据结构'));
      expect(t.deadline, isNotNull);
    });

    test('PlanTask.fromExam 正确转换', () {
      final exam = _FakeExam(name: '期末考试', startTime: DateTime(2026, 7, 10), location: '教七-506');
      final t = PlanTask.fromExam(exam);
      expect(t.title, '期末考试');
      expect(t.deadline, DateTime(2026, 7, 10));
      expect(t.notes, contains('教七-506'));
    });

    test('PlanTask.fromExam 无地点', () {
      final exam = _FakeExam(name: '考试', startTime: null, location: '');
      final t = PlanTask.fromExam(exam);
      expect(t.deadline, isNull);
      expect(t.notes, isEmpty);
    });

    test('PlanTask.fromSession 正确转换', () {
      final s = _FakeSession(courseName: '数据结构', teacher: '张老师', location: '东1A-301');
      final t = PlanTask.fromSession(s);
      expect(t.title, '数据结构');
      expect(t.notes, contains('张老师'));
      expect(t.notes, contains('东1A-301'));
      expect(t.deadline, isNull);
    });

    test('PlanTask.fromSession 无教师无地点', () {
      final s = _FakeSession(courseName: '课程', teacher: null, location: null);
      final t = PlanTask.fromSession(s);
      expect(t.notes, isEmpty);
    });
  });

  group('PlanTask 序列化', () {
    test('toJson / fromJson 往返', () {
      final original = PlanTask(
        id: 'abc', title: '测试', deadline: DateTime(2026, 6, 15),
        notes: '备注', source: 'manual', completed: false,
        createdAt: DateTime(2026, 6, 1),
      );
      final json = original.toJson();
      final restored = PlanTask.fromJson(json);
      expect(restored.id, 'abc');
      expect(restored.title, '测试');
      expect(restored.deadline, DateTime(2026, 6, 15));
      expect(restored.notes, '备注');
      expect(restored.completed, false);
    });

    test('fromJson 处理 null deadline', () {
      final json = {'id': 'x', 'title': 'y', 'source': 'manual', 'completed': false, 'createdAt': '2026-06-01T00:00:00.000'};
      final t = PlanTask.fromJson(json);
      expect(t.deadline, isNull);
      expect(t.notes, '');
    });
  });

  group('PlanTask 计算属性', () {
    test('daysUntil 无 deadline → 999', () {
      expect(PlanTask.create(title: 'x').daysUntil, 999);
    });

    test('daysUntil 未来日期', () {
      final t = PlanTask(id: '1', title: 'x', deadline: DateTime.now().add(const Duration(hours: 48)), createdAt: DateTime.now());
      expect(t.daysUntil, greaterThanOrEqualTo(1));
      expect(t.daysUntil, lessThanOrEqualTo(2));
    });

    test('isExpired 过期', () {
      final t = PlanTask(id: '1', title: 'x', deadline: DateTime.now().subtract(const Duration(days: 1)), createdAt: DateTime.now());
      expect(t.isExpired, true);
    });

    test('priority 已完成 → 0', () {
      final t = PlanTask.create(title: 'x').copyWith(completed: true);
      expect(t.priority, 0);
    });

    test('priority 过期 → 4', () {
      final t = PlanTask(id: '1', title: 'x', deadline: DateTime.now().subtract(const Duration(days: 1)), createdAt: DateTime.now());
      expect(t.priority, 4);
    });

    test('statusLabel 已完成', () {
      final t = PlanTask.create(title: 'x').copyWith(completed: true);
      expect(t.statusLabel, '已完成');
    });

    test('statusLabel 无截止', () {
      expect(PlanTask.create(title: 'x').statusLabel, '无截止');
    });

    test('sourceLabel', () {
      expect(PlanTask.create(title: 'x').sourceLabel, '手动');
      expect(PlanTask(id: '1', title: 'x', source: 'imported', createdAt: DateTime.now()).sourceLabel, '导入');
    });
  });

  group('PlanTask copyWith', () {
    test('只改 title', () {
      final t = PlanTask.create(title: '旧');
      final u = t.copyWith(title: '新');
      expect(u.title, '新');
      expect(u.id, t.id);
      expect(u.completed, t.completed);
    });
  });
}

// Fake objects for testing factories
class _FakeExam {
  final String name;
  final DateTime? startTime;
  final String location;
  const _FakeExam({required this.name, this.startTime, this.location = ''});
}

class _FakeSession {
  final String courseName;
  final String? teacher;
  final String? location;
  const _FakeSession({required this.courseName, this.teacher, this.location});
}

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/features/plan/models/plan.dart';
import 'package:evergreen_multi_tools/features/plan/models/plan_task.dart';

void main() {
  group('Plan model', () {
    test('Plan.create 生成空计划', () {
      final p = Plan.create(name: '期末复习');
      expect(p.id, startsWith('plan_'));
      expect(p.name, '期末复习');
      expect(p.preface, isEmpty);
      expect(p.summary, isEmpty);
      expect(p.keyPoints, isEmpty);
      expect(p.outline, isEmpty);
      expect(p.schedule, isNotEmpty); // 预置空表
      expect(p.scheduleMerges, isEmpty);
      expect(p.createdAt, isNotNull);
    });

    test('Plan.create 空名称默认新计划', () {
      final p = Plan.create();
      expect(p.name, '新计划');
    });

    test('Plan.create 从旧计划复制', () {
      final old = Plan(
        id: 'plan_old',
        name: '旧计划', preface: '序', summary: '总结', keyPoints: '要点',
        outline: [PlanTask.create(title: '任务1')],
      );
      final p = Plan.create(name: '新计划', copyFrom: old);
      expect(p.name, '新计划');
      expect(p.preface, '序');
      expect(p.summary, '总结');
      expect(p.keyPoints, '要点');
      expect(p.outline.length, 1);
      expect(p.outline.first.title, '任务1');
      expect(p.id, isNot(equals(old.id))); // 不同 ID
    });

    test('Plan.create 复制空名称时自动加"(副本)"', () {
      final old = Plan.create(name: '旧计划');
      final p = Plan.create(copyFrom: old);
      expect(p.name, '旧计划 (副本)');
    });

    test('Schedule 预置 7天 × 19小时', () {
      final p = Plan.create();
      expect(p.schedule.length, 7);
      expect(p.schedule.containsKey('周一'), true);
      expect(p.schedule.containsKey('周日'), true);
      for (final day in p.schedule.keys) {
        expect(p.schedule[day]!.length, 19); // 7-24 + 1
      }
    });
  });

  group('Plan 序列化', () {
    test('toJson / fromJson 往返（空计划）', () {
      final p = Plan.create(name: '测试计划');
      final json = p.toJson();
      final restored = Plan.fromJson(json);
      expect(restored.id, p.id);
      expect(restored.name, p.name);
      expect(restored.preface, p.preface);
      expect(restored.outline, isEmpty);
    });

    test('toJson / fromJson 往返（含大纲）', () {
      final p = Plan(
        id: 'p1', name: '计划', preface: '序',
        outline: [PlanTask.create(title: '任务1'), PlanTask.create(title: '任务2')],
      );
      final json = p.toJson();
      final restored = Plan.fromJson(json);
      expect(restored.outline.length, 2);
      expect(restored.outline[0].title, '任务1');
    });

    test('toJson / fromJson 含 schedule', () {
      final p = Plan.create(name: 'x');
      // 修改一格
      final sched = <String, Map<int, String>>{};
      for (final d in p.schedule.keys) {
        sched[d] = Map<int, String>.from(p.schedule[d]!);
      }
      sched['周一']![8] = '复习数学';
      final withSched = p.copyWith(schedule: sched);
      final json = withSched.toJson();
      final restored = Plan.fromJson(json);
      expect(restored.schedule['周一']![8], '复习数学');
    });

    test('fromJson 处理缺失 schedule → 回填空表', () {
      final json = {'id': 'x', 'name': '', 'createdAt': '2026-01-01T00:00:00.000', 'updatedAt': '2026-01-01T00:00:00.000'};
      final p = Plan.fromJson(json);
      expect(p.schedule.length, 7);
    });
  });

  group('Plan copyWith', () {
    test('只改 name', () {
      final p = Plan.create(name: '旧');
      final u = p.copyWith(name: '新');
      expect(u.name, '新');
      expect(u.id, p.id);
      expect(u.preface, p.preface);
    });

    test('updatedAt 更新', () {
      final p = Plan.create();
      final u = p.copyWith();
      expect(u.updatedAt.isAfter(p.updatedAt) || u.updatedAt == p.updatedAt, true);
    });
  });

  group('CellMerge', () {
    test('默认 span 为 1', () {
      final m = CellMerge(row: 0, col: 1);
      expect(m.rowSpan, 1);
      expect(m.colSpan, 1);
    });

    test('toJson / fromJson', () {
      final m = CellMerge(row: 2, col: 3, rowSpan: 2, colSpan: 1);
      final json = m.toJson();
      final r = CellMerge.fromJson(json);
      expect(r.row, 2);
      expect(r.col, 3);
      expect(r.rowSpan, 2);
      expect(r.colSpan, 1);
    });
  });
}

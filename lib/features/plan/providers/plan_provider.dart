/// 计划管理 Riverpod 状态 — 参照 agent_provider 的 session 模式。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../services/plan_store.dart';
import '../../todo/services/todo_service.dart';
import '../../../core/models/exam.dart';
import '../../../core/models/timetable_session.dart';

// ─── Store ───

final planStoreProvider = FutureProvider<PlanStore>((ref) async {
  return PlanStore.create();
});

// ─── Active plan ───

final activePlanIdProvider = StateProvider<String?>((ref) => null);

final planListProvider = FutureProvider<List<Plan>>((ref) async {
  final store = await ref.watch(planStoreProvider.future);
  return store.listAll();
});

final activePlanProvider = FutureProvider<Plan?>((ref) async {
  final id = ref.watch(activePlanIdProvider);
  if (id == null) return null;
  final store = await ref.watch(planStoreProvider.future);
  return store.load(id);
});

final activePlanTitleProvider = Provider<String>((ref) {
  final id = ref.watch(activePlanIdProvider);
  if (id == null) return '计划管理';
  final plans = ref.watch(planListProvider).valueOrNull ?? [];
  return plans.where((p) => p.id == id).firstOrNull?.name ?? '计划管理';
});

// ─── Actions ───

final createPlanProvider =
    Provider<void Function(String name, {String? copyFromId})>((ref) {
  return (String name, {String? copyFromId}) async {
    final store = await ref.read(planStoreProvider.future);
    Plan? copyFrom;
    if (copyFromId != null) copyFrom = store.load(copyFromId);
    final plan = Plan.create(name: name, copyFrom: copyFrom);
    await store.save(plan);
    ref.read(activePlanIdProvider.notifier).state = plan.id;
    ref.invalidate(planListProvider);
  };
});

final switchPlanProvider = Provider<void Function(String id)>((ref) {
  return (String id) {
    ref.read(activePlanIdProvider.notifier).state = id;
  };
});

final deletePlanProvider = Provider<void Function(String id)>((ref) {
  return (String id) async {
    final store = await ref.read(planStoreProvider.future);
    await store.delete(id);
    if (ref.read(activePlanIdProvider) == id) {
      ref.read(activePlanIdProvider.notifier).state = null;
    }
    ref.invalidate(planListProvider);
  };
});

final renamePlanProvider =
    Provider<void Function(String id, String newName)>((ref) {
  return (String id, String newName) async {
    final store = await ref.read(planStoreProvider.future);
    final plan = store.load(id);
    if (plan != null) {
      await store.save(plan.copyWith(name: newName));
      ref.invalidate(planListProvider);
    }
  };
});

// ─── Outline (task list within active plan) ───

final activePlanOutlineProvider = Provider<List<PlanTask>>((ref) {
  final plan = ref.watch(activePlanProvider).valueOrNull;
  return plan?.outline ?? [];
});

/// 保存计划（内部辅助）：直接写 store。
Future<void> _saveAndRefresh(Ref ref, Plan plan) async {
  final store = await ref.read(planStoreProvider.future);
  await store.save(plan);
  ref.invalidate(planListProvider);
  ref.invalidate(activePlanProvider);
}

final addOutlineTaskProvider =
    Provider<void Function(PlanTask task)>((ref) {
  return (PlanTask task) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final updated = plan.outline.toList()..add(task);
    _saveAndRefresh(ref, plan.copyWith(outline: updated));
  };
});

final updateOutlineTaskProvider =
    Provider<void Function(PlanTask task)>((ref) {
  return (PlanTask task) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final idx = plan.outline.indexWhere((t) => t.id == task.id);
    if (idx < 0) return;
    final updated = plan.outline.toList();
    updated[idx] = task;
    _saveAndRefresh(ref, plan.copyWith(outline: updated));
  };
});

final deleteOutlineTaskProvider =
    Provider<void Function(String taskId)>((ref) {
  return (String taskId) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final updated = plan.outline.where((t) => t.id != taskId).toList();
    _saveAndRefresh(ref, plan.copyWith(outline: updated));
  };
});

final toggleOutlineTaskProvider =
    Provider<void Function(String taskId)>((ref) {
  return (String taskId) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final idx = plan.outline.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final updated = plan.outline.toList();
    updated[idx] = updated[idx].copyWith(completed: !updated[idx].completed);
    _saveAndRefresh(ref, plan.copyWith(outline: updated));
  };
});

// ─── Import from external sources ───

final importTodoToPlanProvider =
    Provider<void Function(List<TodoItem> todos)>((ref) {
  return (List<TodoItem> todos) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final existing = plan.outline
        .where((t) => t.source == 'imported')
        .map((t) => t.title)
        .toSet();
    final newTasks = <PlanTask>[];
    for (final todo in todos) {
      if (existing.contains(todo.title)) continue;
      newTasks.add(PlanTask.fromTodoItem(todo));
    }
    if (newTasks.isEmpty) return;
    _saveAndRefresh(ref, plan.copyWith(outline: [...plan.outline, ...newTasks]));
  };
});

final importExamsToPlanProvider =
    Provider<void Function(List<Exam> exams)>((ref) {
  return (List<Exam> exams) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final existing = plan.outline
        .where((t) => t.source == 'imported')
        .map((t) => t.title)
        .toSet();
    final newTasks = <PlanTask>[];
    for (final exam in exams) {
      if (existing.contains(exam.name)) continue;
      newTasks.add(PlanTask.fromExam(exam));
    }
    if (newTasks.isEmpty) return;
    _saveAndRefresh(ref, plan.copyWith(outline: [...plan.outline, ...newTasks]));
  };
});

final importSessionsToPlanProvider =
    Provider<void Function(List<TimetableSession> sessions)>((ref) {
  return (List<TimetableSession> sessions) {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final existing = plan.outline
        .where((t) => t.source == 'imported')
        .map((t) => t.title)
        .toSet();
    final newTasks = <PlanTask>[];
    for (final s in sessions) {
      if (existing.contains(s.courseName)) continue;
      newTasks.add(PlanTask.fromSession(s));
    }
    if (newTasks.isEmpty) return;
    _saveAndRefresh(ref, plan.copyWith(outline: [...plan.outline, ...newTasks]));
  };
});

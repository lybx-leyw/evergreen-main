/// 计划管理主界面 V2。
///
/// 布局：抽屉切换计划 + 各字段(名称/序语/总结/要点) + 大纲任务 + 周时间表。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../providers/plan_provider.dart';
import '../widgets/plan_drawer.dart';
import '../widgets/plan_table.dart';
import '../widgets/plan_task_card.dart';
import '../widgets/add_edit_task_dialog.dart';
import '../../todo/providers/todo_provider.dart';
import '../../exams/providers/exams_provider.dart';
import '../../zdbk/providers/zdbk_provider.dart';
import '../../../core/models/exam.dart';
import '../../../core/models/timetable_session.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  final _nameCtrl = TextEditingController();
  final _prefaceCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _keyPointsCtrl = TextEditingController();
  Timer? _saveTimer;
  bool _firstLoad = true;

  @override
  void dispose() {
    _saveTimer?.cancel();
    _doSave();
    _nameCtrl.dispose();
    _prefaceCtrl.dispose();
    _summaryCtrl.dispose();
    _keyPointsCtrl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _doSave);
  }

  void _doSave() {
    final plan = ref.read(activePlanProvider).valueOrNull;
    if (plan == null) return;
    final updated = plan.copyWith(
      name: _nameCtrl.text,
      preface: _prefaceCtrl.text,
      summary: _summaryCtrl.text,
      keyPoints: _keyPointsCtrl.text,
    );
    _saveSchedule(updated);
  }

  void _saveSchedule(Plan updated) {
    ref.read(planStoreProvider).whenData((store) async {
      await store.save(updated);
      ref.invalidate(planListProvider);
      ref.invalidate(activePlanProvider);
    });
  }

  void _syncFromPlan(Plan plan) {
    if (_nameCtrl.text != plan.name) {
      _nameCtrl.text = plan.name;
    }
    if (_prefaceCtrl.text != plan.preface) {
      _prefaceCtrl.text = plan.preface;
    }
    if (_summaryCtrl.text != plan.summary) {
      _summaryCtrl.text = plan.summary;
    }
    if (_keyPointsCtrl.text != plan.keyPoints) {
      _keyPointsCtrl.text = plan.keyPoints;
    }
  }

  // ── Import dialog ──

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImportSheet(),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(activePlanProvider);
    final title = ref.watch(activePlanTitleProvider);

    // 同步 plan → controllers
    planAsync.whenData((plan) {
      if (plan != null && _firstLoad) {
        _syncFromPlan(plan);
        _firstLoad = false;
      } else if (plan != null) {
        _syncFromPlan(plan);
      }
    });

    return Scaffold(
      drawer: const PlanDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(title),
        actions: [
          if (planAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: '导入',
              onPressed: _showImportDialog,
            ),
        ],
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (plan) {
          if (plan == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('选择一个计划或创建新计划',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    child: const Text('打开计划列表'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // 计划名称
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => _scheduleSave(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '计划名称',
                  border: InputBorder.none,
                ),
              ),
              const Divider(),

              // 序语
              _MarkdownField(
                title: '序语',
                icon: Icons.format_quote,
                controller: _prefaceCtrl,
                onChanged: () => _scheduleSave(),
              ),

              // 得失总结
              _MarkdownField(
                title: '得失总结',
                icon: Icons.balance,
                controller: _summaryCtrl,
                onChanged: () => _scheduleSave(),
              ),

              // 规划要点
              _MarkdownField(
                title: '规划要点',
                icon: Icons.star_outline,
                controller: _keyPointsCtrl,
                onChanged: () => _scheduleSave(),
              ),

              // 规划大纲
              _OutlineSection(plan: plan),

              const SizedBox(height: 12),

              // 规划方案
              Card(
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.grid_on),
                  title: const Text('规划方案',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  children: [
                    PlanTable(
                      schedule: plan.schedule,
                      colors: plan.scheduleColors,
                      onCellChanged: (day, hour, text) {
                        final updated = <String, Map<int, String>>{};
                        for (final d in plan.schedule.keys) {
                          updated[d] = Map<int, String>.from(plan.schedule[d]!);
                        }
                        updated[day]![hour] = text;
                        _saveSchedule(plan.copyWith(schedule: updated));
                      },
                      onCellsChanged: (changes) {
                        final updated = <String, Map<int, String>>{};
                        for (final d in plan.schedule.keys) {
                          updated[d] = Map<int, String>.from(plan.schedule[d]!);
                        }
                        for (final day in changes.keys) {
                          for (final hour in changes[day]!.keys) {
                            updated[day]![hour] = changes[day]![hour]!;
                          }
                        }
                        _saveSchedule(plan.copyWith(schedule: updated));
                      },
                      onColorsChanged: (changes) {
                        final updated = <String, Map<int, int>>{};
                        for (final d in plan.scheduleColors.keys) {
                          updated[d] = Map<int, int>.from(plan.scheduleColors[d]!);
                        }
                        for (final day in changes.keys) {
                          for (final hour in changes[day]!.keys) {
                            updated[day]![hour] = changes[day]![hour]!;
                          }
                        }
                        _saveSchedule(plan.copyWith(scheduleColors: updated));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

// ─── 纯文本编辑 ExpansionTile ───

class _MarkdownField extends StatelessWidget {
  final String title;
  final IconData icon;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _MarkdownField({
    required this.title,
    required this.icon,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '输入$title...',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 大纲任务 Section ───

class _OutlineSection extends ConsumerWidget {
  final Plan plan;
  const _OutlineSection({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = plan.outline;
    final active = tasks.where((t) => !t.completed).toList();
    final done = tasks.where((t) => t.completed).toList();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.checklist),
        title: Text('规划大纲 (${tasks.length}项)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              tooltip: '添加任务',
              onPressed: () => _addTask(context, ref),
            ),
          ],
        ),
        children: [
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无任务，点击 + 添加或从待办/考试导入',
                  style: TextStyle(color: Colors.grey)),
            )
          else ...[
            ...active.map((t) => PlanTaskCard(
                  task: t,
                  onTap: () => _editTask(context, ref, t),
                  onToggle: () => ref.read(toggleOutlineTaskProvider)(t.id),
                  onDelete: () => ref.read(deleteOutlineTaskProvider)(t.id),
                )),
            if (done.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('已完成',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ...done.map((t) => PlanTaskCard(
                  task: t,
                  onTap: () => _editTask(context, ref, t),
                  onToggle: () => ref.read(toggleOutlineTaskProvider)(t.id),
                  onDelete: () => ref.read(deleteOutlineTaskProvider)(t.id),
                )),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _addTask(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AddEditTaskDialog(
        onSave: (task) => ref.read(addOutlineTaskProvider)(task),
      ),
    );
  }

  void _editTask(BuildContext context, WidgetRef ref, PlanTask task) {
    showDialog(
      context: context,
      builder: (_) => AddEditTaskDialog(
        existingTask: task,
        onSave: (updated) => ref.read(updateOutlineTaskProvider)(updated),
      ),
    );
  }
}

// ─── 导入 BottomSheet ───

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet();

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 3, vsync: this);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Column(
        children: [
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: '待办'),
              Tab(text: '考试'),
              Tab(text: '课表'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _TodoImportTab(),
                _ExamImportTab(),
                _SessionImportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}

class _TodoImportTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todoListProvider);
    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (todos) {
        final active = todos.where((t) => !t.isSubmitted).toList();
        if (active.isEmpty) return const Center(child: Text('没有可导入的待办任务'));
        final selected = <String, bool>{for (final t in active) t.id: false};

        return StatefulBuilder(builder: (ctx, setState) {
          final allSel = active.every((t) => selected[t.id] == true);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        final v = !allSel;
                        for (final t in active) { selected[t.id] = v; }
                      }),
                      child: Text(allSel ? '取消全选' : '全选'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final picked = active.where((t) => selected[t.id] == true).toList();
                        if (picked.isNotEmpty) {
                          ref.read(importTodoToPlanProvider)(picked);
                        }
                        Navigator.pop(context);
                      },
                      child: Text('导入 (${active.where((t) => selected[t.id] == true).length})'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: ScrollController(),
                  children: active
                      .map((t) => CheckboxListTile(
                            title: Text(t.title, style: const TextStyle(fontSize: 13)),
                            subtitle: Text('${t.courseName} · ${t.statusLabel}',
                                style: const TextStyle(fontSize: 11)),
                            value: selected[t.id] ?? false,
                            onChanged: (v) => setState(() => selected[t.id] = v ?? false),
                            dense: true,
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

class _ExamImportTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final examsAsync = ref.watch(examsListProvider);
    return examsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (exams) {
        if (exams.isEmpty) return const Center(child: Text('没有考试'));
        final selected = <String, bool>{for (final e in exams) e.id: false};

        return StatefulBuilder(builder: (ctx, setState) {
          final allSel = exams.every((e) => selected[e.id] == true);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        final v = !allSel;
                        for (final e in exams) { selected[e.id] = v; }
                      }),
                      child: Text(allSel ? '取消全选' : '全选'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final picked = exams.where((e) => selected[e.id] == true).toList();
                        if (picked.isNotEmpty) {
                          ref.read(importExamsToPlanProvider)(picked);
                        }
                        Navigator.pop(context);
                      },
                      child: Text('导入 (${exams.where((e) => selected[e.id] == true).length})'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: ScrollController(),
                  children: exams
                      .map((e) => CheckboxListTile(
                            title: Text(e.name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                '${e.location ?? ""} · ${e.startTime != null ? "${e.startTime!.month}/${e.startTime!.day}" : ""}',
                                style: const TextStyle(fontSize: 11)),
                            value: selected[e.id] ?? false,
                            onChanged: (v) => setState(() => selected[e.id] = v ?? false),
                            dense: true,
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

class _SessionImportTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttAsync = ref.watch(zdbkTimetableProvider);
    return ttAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (result) {
        final sessions = result.fold((ok) => ok, (_) => <TimetableSession>[]);
        if (sessions.isEmpty) return const Center(child: Text('没有课表数据'));
        final selected = <String, bool>{for (final s in sessions) s.courseId ?? s.courseName: false};

        return StatefulBuilder(builder: (ctx, setState) {
          final allSel = sessions.every((s) => selected[s.courseId ?? s.courseName] == true);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        final v = !allSel;
                        for (final s in sessions) { selected[s.courseId ?? s.courseName] = v; }
                      }),
                      child: Text(allSel ? '取消全选' : '全选'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        final picked = sessions.where((s) => selected[s.courseId ?? s.courseName] == true).toList();
                        if (picked.isNotEmpty) {
                          ref.read(importSessionsToPlanProvider)(picked);
                        }
                        Navigator.pop(context);
                      },
                      child: Text('导入 (${sessions.where((s) => selected[s.courseId ?? s.courseName] == true).length})'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: ScrollController(),
                  children: sessions
                      .map((s) => CheckboxListTile(
                            title: Text(s.courseName, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                '${s.teacher ?? ""} · ${s.location ?? ""} 周${s.dayOfWeek}',
                                style: const TextStyle(fontSize: 11)),
                            value: selected[s.courseId ?? s.courseName] ?? false,
                            onChanged: (v) => setState(() => selected[s.courseId ?? s.courseName] = v ?? false),
                            dense: true,
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

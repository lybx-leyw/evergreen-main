/// 计划任务数据模型。
///
/// 支持手动创建和从待办列表导入，持久化到本地 JSON 文件。
library;

import 'package:uuid/uuid.dart';
import '../../todo/services/todo_service.dart';

class PlanTask {
  final String id;
  final String title;
  final DateTime? deadline;
  final String notes;
  final String source; // 'manual' | 'imported'
  final bool completed;
  final DateTime createdAt;

  const PlanTask({
    required this.id,
    required this.title,
    this.deadline,
    this.notes = '',
    this.source = 'manual',
    this.completed = false,
    required this.createdAt,
  });

  // ── 工厂 ──

  factory PlanTask.create({
    required String title,
    DateTime? deadline,
    String notes = '',
  }) {
    return PlanTask(
      id: const Uuid().v4(),
      title: title,
      deadline: deadline,
      notes: notes,
      source: 'manual',
      completed: false,
      createdAt: DateTime.now(),
    );
  }

  /// 从 TodoItem 导入（复制语义，独立于原始数据）。
  factory PlanTask.fromTodoItem(TodoItem todo) {
    return PlanTask(
      id: const Uuid().v4(),
      title: todo.title,
      deadline: todo.deadlineDate,
      notes: todo.courseName.isNotEmpty ? '来自: ${todo.courseName}' : '',
      source: 'imported',
      completed: todo.isSubmitted,
      createdAt: DateTime.now(),
    );
  }

  /// 从考试导入 — deadline = 考试开始时间。
  factory PlanTask.fromExam(dynamic exam) {
    final name = (exam.name ?? exam.title ?? '').toString();
    final start = exam.startTime is DateTime ? exam.startTime as DateTime : null;
    final loc = (exam.location ?? '').toString();
    return PlanTask.create(
      title: name,
      deadline: start,
      notes: loc.isNotEmpty ? '考场: $loc' : '',
    );
  }

  /// 从课表导入 — 不设截止，备注课程信息。
  factory PlanTask.fromSession(dynamic session) {
    final name = (session.courseName ?? '').toString();
    final teacher = (session.teacher ?? '').toString();
    final loc = (session.location ?? '').toString();
    final notes = [if (teacher.isNotEmpty) '教师: $teacher', if (loc.isNotEmpty) '地点: $loc'].join(' · ');
    return PlanTask.create(
      title: name,
      deadline: null,
      notes: notes,
    );
  }

  // ── 序列化 ──

  factory PlanTask.fromJson(Map<String, dynamic> json) {
    return PlanTask(
      id: json['id'] as String,
      title: json['title'] as String,
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      notes: json['notes'] as String? ?? '',
      source: json['source'] as String? ?? 'manual',
      completed: json['completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'deadline': deadline?.toIso8601String(),
        'notes': notes,
        'source': source,
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
      };

  // ── 计算属性 ──

  int get daysUntil {
    if (deadline == null) return 999;
    final d = deadline!.difference(DateTime.now()).inDays;
    // inDays truncates, use difference in hours for "today" detection
    final hours = deadline!.difference(DateTime.now()).inHours;
    return hours < 0 ? -1 : hours < 24 ? 0 : d;
  }

  bool get isExpired => deadline != null && deadline!.isBefore(DateTime.now());

  int get priority {
    if (completed) return 0;
    if (deadline == null) return 1;
    if (isExpired) return 4;
    if (daysUntil <= 1) return 3;
    if (daysUntil <= 3) return 2;
    return 1;
  }

  String get statusLabel {
    if (completed) return '已完成';
    if (deadline == null) return '无截止';
    if (isExpired) return '已过期';
    if (daysUntil == 0) return '今天截止';
    if (daysUntil == 1) return '明天截止';
    return '剩余 $daysUntil 天';
  }

  String get sourceLabel => source == 'imported' ? '导入' : '手动';

  PlanTask copyWith({
    String? title,
    DateTime? deadline,
    String? notes,
    bool? completed,
  }) {
    return PlanTask(
      id: id,
      title: title ?? this.title,
      deadline: deadline ?? this.deadline,
      notes: notes ?? this.notes,
      source: source,
      completed: completed ?? this.completed,
      createdAt: createdAt,
    );
  }
}

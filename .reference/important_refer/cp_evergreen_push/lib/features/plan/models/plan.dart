/// 计划容器模型 — 像 AI 会话一样管理多个计划。
library;

import 'package:uuid/uuid.dart';
import 'plan_task.dart';

const _uuid = Uuid();

/// 计划方案表格中的合并单元格。
class CellMerge {
  final int row; // 起始行 (hour index)
  final int col; // 起始列 (day index)
  final int rowSpan;
  final int colSpan;

  const CellMerge({
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
  });

  factory CellMerge.fromJson(Map<String, dynamic> json) => CellMerge(
        row: json['row'] as int,
        col: json['col'] as int,
        rowSpan: json['rowSpan'] as int? ?? 1,
        colSpan: json['colSpan'] as int? ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'row': row,
        'col': col,
        'rowSpan': rowSpan,
        'colSpan': colSpan,
      };
}

/// 空颜色表 — 0 = 无颜色。
Map<String, Map<int, int>> _emptyColors() {
  const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  final c = <String, Map<int, int>>{};
  for (final d in days) {
    c[d] = {for (var h = 7; h <= 24; h++) h: 0};
    c[d]![1] = 0;
  }
  return c;
}

/// 周计划时间表 — 预置 7 天 × 19 小时空表。
Map<String, Map<int, String>> _emptySchedule() {
  const days = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  final s = <String, Map<int, String>>{};
  for (final d in days) {
    s[d] = {for (var h = 7; h <= 24; h++) h: ''};
    s[d]![1] = ''; // 次日凌晨1点
  }
  return s;
}

class Plan {
  final String id;
  final String name;
  final String preface;
  final String summary;
  final String keyPoints;
  final List<PlanTask> outline;
  final Map<String, Map<int, String>> schedule;
  final Map<String, Map<int, int>> scheduleColors; // day → hour → Color.value (0=none)
  final List<CellMerge> scheduleMerges; // 保留以兼容旧数据，不再使用
  final DateTime createdAt;
  final DateTime updatedAt;

  Plan({
    required this.id,
    this.name = '',
    this.preface = '',
    this.summary = '',
    this.keyPoints = '',
    List<PlanTask>? outline,
    Map<String, Map<int, String>>? schedule,
    Map<String, Map<int, int>>? scheduleColors,
    List<CellMerge>? scheduleMerges,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : outline = outline ?? [],
        schedule = schedule ?? _emptySchedule(),
        scheduleColors = scheduleColors ?? _emptyColors(),
        scheduleMerges = scheduleMerges ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Plan.create({String name = '', Plan? copyFrom}) {
    if (copyFrom != null) {
      // 深拷贝旧计划
      final copiedOutline = copyFrom.outline
          .map((t) => PlanTask.create(
                title: t.title,
                deadline: t.deadline,
                notes: t.notes,
              ))
          .toList();
      final copiedSchedule = <String, Map<int, String>>{};
      for (final day in copyFrom.schedule.keys) {
        copiedSchedule[day] = Map<int, String>.from(copyFrom.schedule[day]!);
      }
      final copiedColors = <String, Map<int, int>>{};
      for (final day in copyFrom.scheduleColors.keys) {
        copiedColors[day] = Map<int, int>.from(copyFrom.scheduleColors[day]!);
      }
      final copiedMerges = copyFrom.scheduleMerges
          .map((m) => CellMerge(row: m.row, col: m.col, rowSpan: m.rowSpan, colSpan: m.colSpan))
          .toList();
      return Plan(
        id: 'plan_${_uuid.v4()}',
        name: name.isNotEmpty ? name : '${copyFrom.name} (副本)',
        preface: copyFrom.preface,
        summary: copyFrom.summary,
        keyPoints: copyFrom.keyPoints,
        outline: copiedOutline,
        schedule: copiedSchedule,
        scheduleColors: copiedColors,
        scheduleMerges: copiedMerges,
      );
    }
    return Plan(
      id: 'plan_${_uuid.v4()}',
      name: name.isNotEmpty ? name : '新计划',
    );
  }

  factory Plan.fromJson(Map<String, dynamic> json) {
    final outline = (json['outline'] as List<dynamic>?)
            ?.map((e) => PlanTask.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final scheduleRaw = json['schedule'] as Map<String, dynamic>?;
    final schedule = <String, Map<int, String>>{};
    if (scheduleRaw != null) {
      for (final day in scheduleRaw.keys) {
        final hoursRaw = scheduleRaw[day] as Map<String, dynamic>;
        schedule[day] = hoursRaw.map((k, v) => MapEntry(int.parse(k), v.toString()));
      }
    }
    final merges = (json['scheduleMerges'] as List<dynamic>?)
            ?.map((e) => CellMerge.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final colorsRaw = json['scheduleColors'] as Map<String, dynamic>?;
    final colors = <String, Map<int, int>>{};
    if (colorsRaw != null) {
      for (final day in colorsRaw.keys) {
        final hoursRaw = colorsRaw[day] as Map<String, dynamic>;
        colors[day] = hoursRaw.map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
      }
    }

    return Plan(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      preface: json['preface'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      keyPoints: json['keyPoints'] as String? ?? '',
      outline: outline,
      schedule: schedule.isEmpty ? _emptySchedule() : schedule,
      scheduleColors: colors.isEmpty ? _emptyColors() : colors,
      scheduleMerges: merges,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'preface': preface,
        'summary': summary,
        'keyPoints': keyPoints,
        'outline': outline.map((t) => t.toJson()).toList(),
        'schedule': schedule.map((day, hours) =>
            MapEntry(day, hours.map((k, v) => MapEntry(k.toString(), v)))),
        'scheduleColors': scheduleColors.map((day, hours) =>
            MapEntry(day, hours.map((k, v) => MapEntry(k.toString(), v)))),
        'scheduleMerges': scheduleMerges.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Plan copyWith({
    String? name,
    String? preface,
    String? summary,
    String? keyPoints,
    List<PlanTask>? outline,
    Map<String, Map<int, String>>? schedule,
    Map<String, Map<int, int>>? scheduleColors,
    List<CellMerge>? scheduleMerges,
  }) {
    return Plan(
      id: id,
      name: name ?? this.name,
      preface: preface ?? this.preface,
      summary: summary ?? this.summary,
      keyPoints: keyPoints ?? this.keyPoints,
      outline: outline ?? this.outline,
      schedule: schedule ?? this.schedule,
      scheduleColors: scheduleColors ?? this.scheduleColors,
      scheduleMerges: scheduleMerges ?? this.scheduleMerges,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

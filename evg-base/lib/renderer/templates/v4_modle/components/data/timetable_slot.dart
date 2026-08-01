/// 课表 slot——委托 [TimetableGrid] 渲染周视图。
///
/// M2 P2 迁移：由 P4 桩升级为真实实现，读取 `config.sessions` 渲染课程网格，
/// 并支持 dataSource 注入 `{sessions:[{courseName,periods,dayOfWeek}]}`。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/timetable_grid.dart';

class TimetableSlot extends DataSourceSlot {
  const TimetableSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定 — 优先提取 sessions 键
  @override
  DataMapping get dataMapping => const DataMapping(sourcePath: 'sessions', targetKey: 'sessions');

  @override
  DataSourceSlotState<TimetableSlot> createState() => _TimetableSlotState();
}

class _TimetableSlotState extends DataSourceSlotState<TimetableSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final sessions = <TimetableSession>[];
    final raw = cfg['sessions'];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map<String, dynamic>) {
          sessions.add(TimetableSession.fromJson(s));
        } else if (s is Map) {
          sessions.add(TimetableSession.fromJson(
              s.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    return TimetableGrid(sessions: sessions);
  }
}



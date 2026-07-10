/// 课表 slot——委托 [TimetableGrid] 渲染。
/// TODO(P4): 从 composite_view.dart 迁移完整实现。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

class TimetableSlot extends ConsumerStatefulWidget {
  final ComponentDescriptor config;
  const TimetableSlot({required this.config});

  @override
  ConsumerState<TimetableSlot> createState() => _TimetableSlotStateProxy();
}

class _TimetableSlotStateProxy extends ConsumerState<TimetableSlot> {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Timetable — P4 迁移'));
  }
}

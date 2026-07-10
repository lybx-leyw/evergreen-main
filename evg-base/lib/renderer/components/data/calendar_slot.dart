/// 日历 slot——自绘月历组件。
/// TODO(P4): 从 composite_view.dart 迁移完整实现。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

class CalendarSlot extends StatefulWidget {
  final ComponentDescriptor config;
  const CalendarSlot({required this.config});

  @override
  State<CalendarSlot> createState() => _CalendarSlotStateProxy();
}

class _CalendarSlotStateProxy extends State<CalendarSlot> {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Calendar — P4 迁移'));
  }
}

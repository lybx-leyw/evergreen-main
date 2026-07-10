/// 抽奖转盘 slot——自绘交互式转盘。
/// TODO(P4): 从 composite_view.dart 迁移完整实现。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

class LotteryWheelSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const LotteryWheelSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('LotteryWheel — P4 迁移'));
  }
}

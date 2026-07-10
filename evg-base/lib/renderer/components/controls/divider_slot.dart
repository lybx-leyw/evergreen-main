/// 分割线组件——纯视觉分隔。
import 'package:flutter/material.dart';
import '../../slot/service/slot_scale.dart';

class DividerSlot extends StatelessWidget {
  const DividerSlot();

  @override
  Widget build(BuildContext context) {
    final s = SlotScale.of(context).scale;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * s),
      child: const Divider(height: 1),
    );
  }
}

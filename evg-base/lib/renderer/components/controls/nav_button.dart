/// 导航按钮——emit `slot:switch_page:<target>` 实现页面跳转。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import '../../slot/service/slot_scale.dart';

class NavButton extends StatelessWidget {
  final String label;
  final String icon;
  final String target;
  final PageEventBus? pageEventBus;

  const NavButton({
    required this.label,
    required this.icon,
    required this.target,
    this.pageEventBus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SlotScale.of(context).scale;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * s)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10 * s),
        onTap: () {
          if (target.isNotEmpty && pageEventBus != null) {
            pageEventBus!.emit('slot:switch_page:$target', sourceSlot: 'nav');
          }
        },
        child: Padding(
          padding: EdgeInsets.all(20 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: TextStyle(fontSize: 32 * s)),
              SizedBox(height: 12 * s),
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) * s,
                      ),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

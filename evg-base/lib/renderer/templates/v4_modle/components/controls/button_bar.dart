/// 动作按钮栏——支持 5 种样式（card/filled/outlined/icon/text/tonal）。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';

class ActionButtonBar extends StatelessWidget {
  final Map<String, dynamic> config;
  final PageEventBus? pageEventBus;

  const ActionButtonBar({required this.config, this.pageEventBus});

  @override
  Widget build(BuildContext context) {
    final buttons = (config['buttons'] as List<dynamic>?) ?? [];
    if (buttons.isEmpty) return const SizedBox.shrink();

    final direction = config['direction'] as String? ?? 'row';
    final gap = (config['gap'] as num?)?.toDouble() ?? 8;

    final children = <Widget>[];
    for (final raw in buttons) {
      if (raw is! Map) continue;
      final btn = raw.cast<String, dynamic>();
      final label = btn['label'] as String?;
      final icon = btn['icon'] as String?;
      final desc = btn['desc'] as String?;
      final event = btn['event'] as String? ?? '';
      final style = btn['style'] as String? ?? 'tonal';
      final onPressed = (event.isNotEmpty && pageEventBus != null)
          ? () => pageEventBus!.emit(event, sourceSlot: 'button')
          : null;

      final child = _buildButton(context, label, icon, desc, style, onPressed);
      if (child != null) children.add(child);
    }

    if (children.isEmpty) return const SizedBox.shrink();

    // card 风格：用 LayoutBuilder 等分宽度，不用 Flex 机制（避免无界约束崩溃）
    final hasCardStyle = (config['buttons'] as List<dynamic>?)
        ?.any((b) => b is Map && b['style'] == 'card') ?? false;

    if (hasCardStyle && direction != 'column') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final numCards = children.length;
          if (totalWidth.isFinite && numCards > 0) {
            final totalGap = gap * (numCards - 1);
            final cardWidth = ((totalWidth - totalGap) / numCards).clamp(0.0, totalWidth).toDouble();
            final sized = children
                .map((c) => SizedBox(width: cardWidth, child: c))
                .toList();
            return Row(children: _interleave(sized, SizedBox(width: gap)));
          }
          // 约束无界时退化为内容宽度
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: _interleave(children, SizedBox(width: gap)),
          );
        },
      );
    }

    if (direction == 'column') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _interleave(children, SizedBox(height: gap)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _interleave(children, SizedBox(width: gap)),
    );
  }

  Widget? _buildButton(BuildContext context, String? label, String? icon,
      String? desc, String style, VoidCallback? onPressed) {
    final theme = Theme.of(context);
    final s = SlotScale.of(context).scale;

    // 卡片风格：图标 + 标题 + 描述，适合导航卡片
    if (style == 'card') {
      final colorScheme = theme.colorScheme;
      final bgColor = colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
      final borderColor = colorScheme.outline.withValues(alpha: 0.15);
      return GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12 * s),
              border: Border.all(color: borderColor, width: 1 * s),
            ),
            padding: EdgeInsets.all(16 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null && icon.isNotEmpty)
                  Text(icon, style: TextStyle(fontSize: 28 * s)),
                const SizedBox(height: 8),
                if (label != null && label.isNotEmpty)
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11 * s,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
      );
    }

    Widget? child;
    switch (style) {
      case 'filled':
        if (icon != null && label != null) {
          child = FilledButton.icon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = FilledButton(onPressed: onPressed, child: Text(label));
        } else {
          return null;
        }
      case 'outlined':
        if (icon != null && label != null) {
          child = OutlinedButton.icon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = OutlinedButton(onPressed: onPressed, child: Text(label));
        } else {
          return null;
        }
      case 'icon':
        return IconButton(
          onPressed: onPressed,
          icon: Text(icon ?? ''),
          tooltip: label,
        );
      case 'text':
        child = TextButton.icon(
          onPressed: onPressed,
          icon: icon != null ? Text(icon) : const SizedBox.shrink(),
          label: label != null ? Text(label) : const SizedBox.shrink(),
        );
      case 'tonal':
      default:
        if (icon != null && label != null) {
          child = FilledButton.tonalIcon(onPressed: onPressed, icon: Text(icon), label: Text(label));
        } else if (label != null) {
          child = FilledButton.tonal(onPressed: onPressed, child: Text(label));
        } else if (icon != null) {
          child = FilledButton.tonalIcon(onPressed: onPressed, icon: Text(icon), label: const Text(''));
        } else {
          return null;
        }
    }
    return child;
  }

  List<Widget> _interleave(List<Widget> items, Widget separator) {
    if (items.length <= 1) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) result.add(separator);
      result.add(items[i]);
    }
    return result;
  }
}

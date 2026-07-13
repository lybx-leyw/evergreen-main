/// 画布上的 Slot 框架组件。
///
/// 封装 Slot 的视觉呈现——虚线边框、标签、拖拽手柄。
/// 由 [SlotPainter] 提供渲染数据，本组件负责交互（选中、拖拽、删除）。
library;

import 'package:flutter/material.dart';

/// Slot 框架数据。
class SlotFrameData {
  final String id;
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isSelected;
  final String? componentType;

  const SlotFrameData({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isSelected = false,
    this.componentType,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);
}

/// Slot 框架回调。
class SlotFrameCallbacks {
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDelete;

  const SlotFrameCallbacks({this.onTap, this.onDragUpdate, this.onDelete});
}

/// 画布上的 Slot 可交互框架。
///
/// 绘制虚线边框 + 标签 + 组件图标，
/// 支持点击选中和拖拽移动。
class SlotFrame extends StatelessWidget {
  final SlotFrameData data;
  final SlotFrameCallbacks callbacks;

  const SlotFrame({super.key, required this.data, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = data.isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    return Positioned(
      left: data.x,
      top: data.y,
      width: data.width,
      height: data.height,
      child: GestureDetector(
        onTap: callbacks.onTap,
        onPanUpdate: callbacks.onDragUpdate != null
            ? (d) => callbacks.onDragUpdate!(d.delta)
            : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: color,
              width: data.isSelected ? 2.0 : 1.0,
              // 虚线效果用 CustomPaint 模拟
            ),
            borderRadius: BorderRadius.circular(6),
            color: data.isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 组件图标
              if (data.componentType != null)
                Icon(
                  _componentIcon(data.componentType!),
                  size: 28,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                )
              else
                Icon(
                  Icons.crop_free,
                  size: 28,
                  color: theme.disabledColor,
                ),
              const SizedBox(height: 4),
              // 标签
              Text(
                data.label.isNotEmpty ? data.label : data.id,
                style: TextStyle(
                  fontSize: 11,
                  color: data.isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight:
                      data.isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (data.componentType != null) ...[
                const SizedBox(height: 2),
                Text(
                  data.componentType!,
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.disabledColor,
                  ),
                ),
              ],
              // 删除按钮（选中时显示）
              if (data.isSelected && callbacks.onDelete != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: callbacks.onDelete,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline,
                            size: 12,
                            color: theme.colorScheme.onErrorContainer),
                        const SizedBox(width: 2),
                        Text('删除',
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onErrorContainer)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _componentIcon(String type) {
    switch (type) {
      case 'ai-assistant': return Icons.psychology;
      case 'data-table': return Icons.table_chart;
      case 'chart': return Icons.bar_chart;
      case 'card-list': return Icons.view_list;
      case 'markdown': return Icons.description;
      case 'code-editor': return Icons.code;
      case 'map': return Icons.map;
      case 'calendar': return Icons.calendar_month;
      case 'kanban': return Icons.view_kanban;
      case 'timeline': return Icons.timeline;
      case 'video-player': return Icons.videocam;
      case 'audio-player': return Icons.headphones;
      case 'webview': return Icons.language;
      case 'spreadsheet': return Icons.grid_on;
      case 'whiteboard': return Icons.draw;
      case 'mindmap': return Icons.account_tree;
      case 'terminal': return Icons.terminal;
      case 'divider': return Icons.horizontal_rule;
      case 'lottery-wheel': return Icons.casino;
      case 'marketplace': return Icons.store;
      default:
        return Icons.widgets;
    }
  }
}

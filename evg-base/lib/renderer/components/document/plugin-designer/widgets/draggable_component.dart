/// 可拖拽组件卡片 —— 从组件面板拖到画布上的 DragSource。
///
/// 配合 [DragTarget] 使用，onDragStarted 提供组件类型和拖拽偏移。
library;

import 'package:flutter/material.dart';

/// 可拖拽组件数据。
class DraggableComponentData {
  final String type;
  final String label;
  final IconData icon;
  final String group;

  const DraggableComponentData({
    required this.type,
    required this.label,
    required this.icon,
    this.group = '',
  });
}

/// 可拖拽组件卡片。
///
/// 在组件面板中使用：`DraggableComponentCard` 包裹每个组件项，
/// 拖拽时携带 [DraggableComponentData] 到画布。
class DraggableComponentCard extends StatelessWidget {
  final DraggableComponentData component;

  const DraggableComponentCard({super.key, required this.component});

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<DraggableComponentData>(
      data: component,
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(component.icon, size: 20),
              const SizedBox(width: 8),
              Text(component.label,
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCard(context),
      ),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(component.icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                component.label,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

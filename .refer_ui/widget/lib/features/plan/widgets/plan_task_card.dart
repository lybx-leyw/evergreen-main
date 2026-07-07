/// 计划任务卡片组件。
library;

import 'package:flutter/material.dart';
import '../models/plan_task.dart';

class PlanTaskCard extends StatelessWidget {
  final PlanTask task;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  const PlanTaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.onToggle,
    this.onDelete,
  });

  static const _priorityColors = [
    Colors.grey,   // 0: completed
    Colors.blue,   // 1: normal
    Colors.orange, // 2: within 3 days
    Colors.red,    // 3: within 1 day
    Colors.red,    // 4: expired
  ];

  @override
  Widget build(BuildContext context) {
    final color = _priorityColors[task.priority.clamp(0, 4)];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              // 优先级颜色条
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 复选框
              Checkbox(
                value: task.completed,
                onChanged: (_) => onToggle?.call(),
                activeColor: Colors.green,
              ),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: task.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: task.completed ? Colors.grey : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (task.deadline != null) ...[
                          Icon(Icons.access_time, size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(
                            task.statusLabel,
                            style: TextStyle(fontSize: 12, color: color),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: task.source == 'imported'
                                ? Colors.green.shade50
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.sourceLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: task.source == 'imported'
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 删除
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Colors.grey,
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

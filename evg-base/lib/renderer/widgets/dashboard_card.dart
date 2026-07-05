/// Dashboard 卡片——KPI 指标卡片。
///
/// 公开类：[DashboardCard]
import 'package:flutter/material.dart';

/// 仪表盘 KPI 卡片。
///
/// 显示标题、数值、趋势图标、副标题。
class DashboardCard extends StatelessWidget {
  final String title;
  final String? value;
  final String? trend; // up | down | neutral
  final String? subtitle;
  final String display;
  final VoidCallback? onTap;

  const DashboardCard({
    super.key,
    required this.title,
    this.value,
    this.trend,
    this.subtitle,
    this.display = 'card',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),

              // 数值 + 趋势
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value ?? '--',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  if (trend != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      trend == 'up'
                          ? Icons.trending_up
                          : trend == 'down'
                              ? Icons.trending_down
                              : Icons.trending_flat,
                      size: 20,
                      color: trend == 'up'
                          ? Colors.green
                          : trend == 'down'
                              ? Theme.of(context).colorScheme.error
                              : Colors.grey,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),

              // 副标题
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

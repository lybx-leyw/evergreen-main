/// 时间线组件——根据 [TimelineDescriptor] 渲染时间线/日历视图。
///
/// 公开类：[TimelineWidget]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 时间线渲染组件。
///
/// 读取 [TimelineDescriptor] 配置：
/// - mode: list | calendar | gantt
/// - view: day | week | month | year
class TimelineWidget extends StatelessWidget {
  final TimelineDescriptor timeline;

  const TimelineWidget({super.key, required this.timeline});

  @override
  Widget build(BuildContext context) {
    return switch (timeline.mode) {
      'calendar' => _buildCalendar(context),
      'gantt' => _buildGantt(context),
      _ => _buildListTimeline(context), // 'list' + 未知
    };
  }

  Widget _buildListTimeline(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TimelineEntry(
          date: '2026-07-01',
          title: '时间线占位条目',
          subtitle: '时间线数据将从数据源加载',
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_month,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            '日历视图',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '当前: ${timeline.view}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildGantt(BuildContext context) {
    return Center(
      child: Text(
        '甘特图视图',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// 单条时间线条目。
class _TimelineEntry extends StatelessWidget {
  final String date;
  final String title;
  final String? subtitle;
  final bool isLast;

  const _TimelineEntry({
    required this.date,
    required this.title,
    this.subtitle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间线指示器
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Text(
                  date,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          // 连接线 + 内容
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          // 内容卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

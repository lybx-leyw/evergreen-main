/// Dashboard 卡片——KPI 指标卡片（现代化设计）。
///
/// 公开类：[DashboardCard]
///
/// 特性：
/// - 渐变色背景（可配置颜色主题）
/// - 大数字 + 趋势图标
/// - 标题/数值/副标题/趋势四层信息
/// - 点击回调支持
library;

import 'package:flutter/material.dart';

/// KPI 卡片颜色主题。
enum DashboardCardTheme {
  blue,
  green,
  orange,
  purple,
  teal,
  red,
}

/// 仪表盘 KPI 卡片。
///
/// 显示标题、数值、趋势图标、副标题。
/// 支持渐变色背景，视觉冲击力强。
class DashboardCard extends StatelessWidget {
  final String title;
  final String? value;
  final String? trend; // up | down | neutral
  final String? subtitle;
  final String display;
  final VoidCallback? onTap;
  final DashboardCardTheme cardTheme;

  const DashboardCard({
    super.key,
    required this.title,
    this.value,
    this.trend,
    this.subtitle,
    this.display = 'card',
    this.onTap,
    this.cardTheme = DashboardCardTheme.blue,
  });

  /// 根据主题获取渐变色。
  static List<Color> _gradientFor(DashboardCardTheme theme) {
    return switch (theme) {
      DashboardCardTheme.blue   => [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
      DashboardCardTheme.green  => [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
      DashboardCardTheme.orange => [const Color(0xFFE65100), const Color(0xFFFFA726)],
      DashboardCardTheme.purple => [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
      DashboardCardTheme.teal   => [const Color(0xFF00695C), const Color(0xFF26A69A)],
      DashboardCardTheme.red    => [const Color(0xFFC62828), const Color(0xFFEF5350)],
    };
  }

  /// 根据主题获取图标。
  static IconData _iconFor(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('用户') || lower.contains('user') || lower.contains('member')) {
      return Icons.people_alt_rounded;
    }
    if (lower.contains('收入') || lower.contains('revenue') || lower.contains('sales')) {
      return Icons.trending_up_rounded;
    }
    if (lower.contains('订单') || lower.contains('order')) {
      return Icons.receipt_long_rounded;
    }
    if (lower.contains('访问') || lower.contains('visit') || lower.contains('traffic')) {
      return Icons.visibility_rounded;
    }
    if (lower.contains('转化') || lower.contains('conversion') || lower.contains('rate')) {
      return Icons.analytics_rounded;
    }
    if (lower.contains('任务') || lower.contains('task')) {
      return Icons.task_alt_rounded;
    }
    if (lower.contains('消息') || lower.contains('message') || lower.contains('notification')) {
      return Icons.notifications_rounded;
    }
    return Icons.dashboard_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradients = _gradientFor(cardTheme);
    final icon = _iconFor(title);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: gradients[0].withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradients,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              // 背景装饰图标
              Positioned(
                right: -12,
                bottom: -16,
                child: Icon(
                  icon,
                  size: 96,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),

              // 内容
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 图标 + 标题
                    Row(
                      children: [
                        Icon(icon, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // 数值 + 趋势
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          value ?? '--',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            fontSize: 28,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (trend != null) ...[
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: _TrendBadge(trend: trend!),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 2),

                    // 副标题
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 趋势徽章组件。
class _TrendBadge extends StatelessWidget {
  final String trend;

  const _TrendBadge({required this.trend});

  @override
  Widget build(BuildContext context) {
    final isUp = trend == 'up';
    final isDown = trend == 'down';
    final isNeutral = trend == 'neutral' || trend == 'flat' || trend == 'stable';
    final isCustom = !isUp && !isDown && !isNeutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isUp ? Colors.green : isDown ? Colors.red : Colors.grey)
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp
                ? Icons.trending_up_rounded
                : isDown
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
            size: 14,
            color: isUp
                ? Colors.greenAccent
                : isDown
                    ? Colors.redAccent
                    : Colors.grey.shade300,
          ),
          const SizedBox(width: 2),
          Text(
            isCustom ? trend : (isUp ? '+' : isDown ? '-' : ''),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

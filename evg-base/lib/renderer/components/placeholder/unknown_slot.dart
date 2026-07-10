/// 未知组件类型的占位卡片——按分组提供有意义的提示。
import 'package:flutter/material.dart';
import '../../slot/service/slot_scale.dart';

class UnknownSlot extends StatelessWidget {
  final String type;
  final Map<String, dynamic> config;
  final String group;

  const UnknownSlot({
    required this.type,
    required this.config,
    required this.group,
  });

  /// 各分组对应的 Material Icon。
  static final Map<String, IconData> _groupIcons = {
    '智能交互': Icons.psychology,
    '数据展示': Icons.analytics,
    '文档与媒体': Icons.description,
    '创作与工具': Icons.build,
    '学习专用': Icons.school,
    '特殊': Icons.extension,
    '预留扩展': Icons.more_horiz,
    '未知': Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SlotScale.of(context).scale;
    final icon = _groupIcons[group] ?? Icons.help_outline;
    final color = _groupColor(group, theme);

    return Container(
      padding: EdgeInsets.all(24 * s),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20 * s, color: color),
              SizedBox(width: 8 * s),
              Expanded(
                child: Text(
                  type,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) * s,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2 * s),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4 * s),
                ),
                child: Text(
                  group,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: (theme.textTheme.labelSmall?.fontSize ?? 11) * s,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * s),
          Text(
            '组件 "$type" 尚未实现渲染',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: (theme.textTheme.bodySmall?.fontSize ?? 12) * s,
            ),
          ),
          if (config.isNotEmpty) ...[
            SizedBox(height: 8 * s),
            Text(
              'config: $_truncateConfig(config)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontFamily: 'monospace',
                fontSize: (theme.textTheme.labelSmall?.fontSize ?? 11) * s,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _groupColor(String group, ThemeData theme) {
    return switch (group) {
      '智能交互' => Colors.indigo,
      '数据展示' => Colors.teal,
      '文档与媒体' => Colors.blue,
      '创作与工具' => Colors.orange,
      '学习专用' => Colors.green,
      '特殊' => Colors.purple,
      '预留扩展' => theme.colorScheme.outline,
      _          => theme.colorScheme.onSurfaceVariant,
    };
  }

  String _truncateConfig(Map<String, dynamic> cfg) {
    final s = cfg.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }
}

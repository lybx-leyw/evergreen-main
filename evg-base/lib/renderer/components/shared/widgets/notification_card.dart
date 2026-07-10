/// 通知卡片——本地通知展示组件。
///
/// 对应 R-S2-8：通知权限弹窗 + 基础本地通知展示。
import 'package:flutter/material.dart';

/// 通知类型。
enum NotificationType { info, success, warning, error, update }

/// 通知数据。
class AppNotification {
  final String title;
  final String message;
  final NotificationType type;
  final DateTime time;
  final void Function()? onTap;

  AppNotification({
    required this.title,
    required this.message,
    this.type = NotificationType.info,
    DateTime? time,
    this.onTap,
  }) : time = time ?? DateTime.now();
}

/// 通知卡片——在列表中展示单条通知。
class NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const NotificationCard({super.key, required this.notification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconData = _iconForType(notification.type);
    final iconColor = _colorForType(notification.type, scheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: notification.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notification.message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(notification.time),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.info:
        return Icons.info_outline;
      case NotificationType.success:
        return Icons.check_circle_outline;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.update:
        return Icons.system_update_alt;
    }
  }

  Color _colorForType(NotificationType type, ColorScheme scheme) {
    switch (type) {
      case NotificationType.info:
        return scheme.primary;
      case NotificationType.success:
        return const Color(0xFF2DA44E);
      case NotificationType.warning:
        return const Color(0xFFFA8C16);
      case NotificationType.error:
        return scheme.error;
      case NotificationType.update:
        return const Color(0xFF722ED1);
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

/// 通知权限请求弹窗。
///
/// 用法：
/// ```dart
/// final granted = await showNotificationPermissionDialog(context);
/// ```
Future<bool?> showNotificationPermissionDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.notifications_active, size: 28, color: Color(0xFF1677FF)),
      title: const Text('开启通知'),
      content: const Text(
        '允许 Evergreen 向你发送插件更新、安装完成等通知？'
        '你可以在设置中随时更改此选项。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('暂不开启'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('允许'),
        ),
      ],
    ),
  );
}

/// 通知列表——展示一组通知。
class NotificationList extends StatelessWidget {
  final List<AppNotification> notifications;
  final Widget? emptyWidget;

  const NotificationList({
    super.key,
    required this.notifications,
    this.emptyWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return emptyWidget ??
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  '暂无通知',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                ),
              ],
            ),
          );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length,
      itemBuilder: (ctx, i) => NotificationCard(notification: notifications[i]),
    );
  }
}

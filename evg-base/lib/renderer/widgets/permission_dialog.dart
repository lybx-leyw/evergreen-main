/// 权限对话框——安装前权限确认，展示权限分级列表。
///
/// 对应 R-S2-9：安装时权限弹窗。
import 'package:flutter/material.dart';
import 'models.dart';

/// 权限确认弹窗。
///
/// 用法：
/// ```dart
/// final ok = await showPermissionDialog(context, pluginName: 'AI 代码助手', permissions: [...]);
/// ```
Future<bool?> showPermissionDialog(
  BuildContext context, {
  required String pluginName,
  required List<PluginPermission> permissions,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _PermissionDialog(
      pluginName: pluginName,
      permissions: permissions,
    ),
  );
}

class _PermissionDialog extends StatelessWidget {
  final String pluginName;
  final List<PluginPermission> permissions;

  const _PermissionDialog({
    required this.pluginName,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.security, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text('权限确认 — $pluginName'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '此插件需要以下权限：',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ...permissions.map((p) => _PermissionRow(permission: p)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: scheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '高危权限可能影响系统安全，请谨慎授权',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认安装'),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final PluginPermission permission;

  const _PermissionRow({required this.permission});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color dotColor;
    IconData icon;
    switch (permission.level) {
      case PermissionLevel.danger:
        dotColor = scheme.error;
        icon = Icons.warning_amber_rounded;
      case PermissionLevel.warning:
        dotColor = const Color(0xFFFA8C16);
        icon = Icons.info_outline;
      case PermissionLevel.safe:
        dotColor = const Color(0xFF2DA44E);
        icon = Icons.check_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: dotColor),
          const SizedBox(width: 8),
          Text(
            permission.name,
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              permission.levelLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: dotColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

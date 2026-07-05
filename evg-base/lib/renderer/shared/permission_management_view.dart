/// 权限管理页面——管理已安装插件的权限授予/撤销。
///
/// 对应 R-S2-9：权限管理页面。
import 'package:flutter/material.dart';
import '../widgets/models.dart';

/// 权限管理页面。
///
/// 接收 [snapshots]（已安装插件的权限快照列表）和 [onToggle]（权限变更回调）。
///
/// 用法：
/// ```dart
/// PermissionManagementView(
///   snapshots: [
///     PluginPermissionSnapshot(pluginId: 'p1', pluginName: 'AI 助手', permissions: [...]),
///   ],
///   onToggle: (pluginId, permissionName, granted) { ... },
/// )
/// ```
class PermissionManagementView extends StatefulWidget {
  final List<PluginPermissionSnapshot> snapshots;
  final void Function(String pluginId, String permissionName, bool granted)? onToggle;

  const PermissionManagementView({
    super.key,
    required this.snapshots,
    this.onToggle,
  });

  @override
  State<PermissionManagementView> createState() => _PermissionManagementViewState();
}

class _PermissionManagementViewState extends State<PermissionManagementView> {
  late List<PluginPermissionSnapshot> _snapshots;

  @override
  void initState() {
    super.initState();
    _snapshots = List.from(widget.snapshots);
  }

  @override
  void didUpdateWidget(PermissionManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshots != widget.snapshots) {
      _snapshots = List.from(widget.snapshots);
    }
  }

  void _togglePermission(int pluginIndex, int permIndex) {
    setState(() {
      final snap = _snapshots[pluginIndex];
      final perm = snap.permissions[permIndex];
      final newPerm = perm.copyWith(granted: !perm.granted);
      final newPerms = List<PluginPermission>.from(snap.permissions);
      newPerms[permIndex] = newPerm;
      _snapshots[pluginIndex] = PluginPermissionSnapshot(
        pluginId: snap.pluginId,
        pluginName: snap.pluginName,
        permissions: newPerms,
      );
    });

    final snap = _snapshots[pluginIndex];
    final perm = snap.permissions[permIndex];
    widget.onToggle?.call(snap.pluginId, perm.name, perm.granted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_snapshots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.security, size: 48, color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              '暂无已安装插件',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _snapshots.length,
      itemBuilder: (context, pluginIndex) {
        final snap = _snapshots[pluginIndex];
        return _PluginPermissionCard(
          snapshot: snap,
          onToggle: (permIndex) => _togglePermission(pluginIndex, permIndex),
        );
      },
    );
  }
}

class _PluginPermissionCard extends StatelessWidget {
  final PluginPermissionSnapshot snapshot;
  final void Function(int permIndex) onToggle;

  const _PluginPermissionCard({
    required this.snapshot,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.extension, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.pluginName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _SummaryChip(
                  label: '${snapshot.grantedCount}/${snapshot.permissions.length}',
                  color: scheme.primary,
                ),
              ],
            ),
          ),

          // Permission list
          ...List.generate(snapshot.permissions.length, (permIndex) {
            final perm = snapshot.permissions[permIndex];
            return _PermissionItem(
              permission: perm,
              onToggle: () => onToggle(permIndex),
            );
          }),

          // Danger warning
          if (snapshot.dangerCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: scheme.errorContainer.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此插件含 ${snapshot.dangerCount} 项高危权限，请谨慎授予',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final PluginPermission permission;
  final VoidCallback onToggle;

  const _PermissionItem({
    required this.permission,
    required this.onToggle,
  });

  Color _levelColor(ColorScheme scheme) {
    switch (permission.level) {
      case PermissionLevel.danger:
        return scheme.error;
      case PermissionLevel.warning:
        return const Color(0xFFFA8C16);
      case PermissionLevel.safe:
        return const Color(0xFF2DA44E);
    }
  }

  IconData _levelIcon() {
    switch (permission.level) {
      case PermissionLevel.danger:
        return Icons.warning_amber_rounded;
      case PermissionLevel.warning:
        return Icons.info_outline;
      case PermissionLevel.safe:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _levelColor(scheme);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(_levelIcon(), size: 18, color: permission.granted ? color : scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    permission.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: permission.granted ? null : scheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    permission.levelLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: permission.granted,
              onChanged: (_) => onToggle(),
              activeColor: scheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

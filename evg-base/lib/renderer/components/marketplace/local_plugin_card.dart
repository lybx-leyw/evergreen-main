/// 本地插件卡片 —— 市场列表中单个插件的卡片展示。
library;

import 'package:flutter/material.dart';

import '../../../core/module/module_descriptor.dart';
import '../document/plugin-designer/services/plugin_state_service.dart';

/// 单个本地插件的展示卡片。
///
/// 显示：icon + name + description + version + 开关按钮。
class LocalPluginCard extends StatelessWidget {
  final ModuleDescriptor manifest;
  final PluginStateRecord? state;
  final bool isModule;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleSidebar;
  final VoidCallback onUninstall;

  const LocalPluginCard({
    super.key,
    required this.manifest,
    this.state,
    required this.isModule,
    required this.onToggleEnabled,
    required this.onToggleSidebar,
    required this.onUninstall,
  });

  bool get _enabled => state?.enabled ?? true;
  bool get _sidebarVisible => state?.sidebarVisible ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconCode = manifest.icon;
    final icon = iconCode != null
        ? IconData(iconCode, fontFamily: 'MaterialIcons')
        : Icons.extension;
    final isDisabled = !_enabled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDisabled
              ? theme.disabledColor.withValues(alpha: 0.3)
              : theme.dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：图标 + 名称 + 开关
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? theme.disabledColor.withValues(alpha: 0.1)
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isDisabled
                        ? theme.disabledColor
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDisabled
                              ? theme.disabledColor
                              : theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${manifest.version} · ${manifest.id}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.disabledColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (_) => onToggleEnabled(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            // 描述
            if (manifest.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                manifest.description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDisabled
                      ? theme.disabledColor
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            // 底部：页码 + 侧边栏 + 操作按钮
            Row(
              children: [
                _InfoBadge(
                  label: '${manifest.pages.length} 页',
                  icon: Icons.tab,
                ),
                const SizedBox(width: 8),
                _InfoBadge(
                  label: manifest.hasSidebar ? '侧栏可见' : '无侧栏',
                  icon: manifest.hasSidebar ? Icons.visibility : Icons.visibility_off,
                ),
                const Spacer(),
                if (manifest.hasSidebar)
                  TextButton.icon(
                    onPressed: _enabled ? onToggleSidebar : null,
                    icon: Icon(
                      _sidebarVisible ? Icons.menu_open : Icons.menu,
                      size: 16,
                    ),
                    label: Text(
                      _sidebarVisible ? '隐藏侧栏' : '显示侧栏',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _enabled ? onUninstall : null,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('卸载', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 小型信息标签。
class _InfoBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Theme.of(context).disabledColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Theme.of(context).disabledColor),
          ),
        ],
      ),
    );
  }
}

/// 本地插件卡片 —— 市场列表中单个插件的卡片展示。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'marketplace_plugin_info.dart';

/// 单个本地插件的展示卡片。
///
/// 显示：icon + name + 类型标签 + description + 开关按钮。
/// 覆盖所有插件类型（module/agent/data-source/config/theme ...），
/// 而非仅 module。
class LocalPluginCard extends StatelessWidget {
  final PluginInfo plugin;
  final PluginStateRecord? state;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleSidebar;
  final VoidCallback onUninstall;

  const LocalPluginCard({
    super.key,
    required this.plugin,
    this.state,
    required this.onToggleEnabled,
    required this.onToggleSidebar,
    required this.onUninstall,
  });

  bool get _enabled => state?.enabled ?? true;
  bool get _sidebarVisible => state?.sidebarVisible ?? true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = plugin.iconCode != null
        ? IconData(plugin.iconCode!, fontFamily: 'MaterialIcons')
        : plugin.typeIcon;
    final isDisabled = !_enabled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDisabled
              ? theme.colorScheme.outlineVariant
              : theme.dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：图标 + 名称 + 类型标签 + 开关
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isDisabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDisabled
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55)
                              : theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${plugin.version ?? '0.0.0'} · ${plugin.id} · ${plugin.typeLabel}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // module / skill 类型有启用/停用开关
                // （module 影响侧边栏导航；skill 影响 Agent 是否加载该技能）。
                if (plugin.isModule || plugin.isSkill)
                  Switch(
                    value: _enabled,
                    onChanged: (_) => onToggleEnabled(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            // 描述
            if (plugin.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plugin.description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDisabled
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.45)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            // 底部：信息标签 + 操作按钮。
            // 窄屏（360px 手机）下 3 badge + 2 button 总宽 ~321px > 可用 ~312px，
            // 超 7-13px 导致 RenderFlex 右溢出。用 SingleChildScrollView 兜底。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _InfoBadge(
                    label: plugin.typeLabel,
                    icon: plugin.typeIcon,
                  ),
                  const SizedBox(width: 8),
                  // 内置模块（如 zju 校园模块）：随应用分发、不可卸载。
                  if (plugin.isBuiltin) ...[
                    _InfoBadge(
                      label: '内置',
                      icon: Icons.system_update_alt,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (plugin.isModule)
                    _InfoBadge(
                      label: plugin.hasSidebar ? '侧栏可见' : '无侧栏',
                      icon: plugin.hasSidebar
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  if (plugin.isModule && plugin.pageCount > 0) ...[
                    const SizedBox(width: 8),
                    _InfoBadge(
                      label: '${plugin.pageCount} 页',
                      icon: Icons.tab,
                    ),
                  ],
                  const SizedBox(width: 8),
                  // 侧栏隐藏/显示仅对 module 且启用时可用。
                  if (plugin.isModule && plugin.hasSidebar)
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
                  // 卸载按钮仅对磁盘插件显示；内置模块（isBuiltin）不可卸载。
                  // 停用/禁用不应阻止卸载：用户可能想直接移除一个不再使用的插件。
                  if (!plugin.isBuiltin)
                    TextButton.icon(
                      onPressed: onUninstall,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('卸载', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
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

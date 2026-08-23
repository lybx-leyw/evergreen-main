/// 顶部工具栏——新建面板 / 从内置复制 / 保存 / 导出插件 / AI 助手。
library;

import 'package:flutter/material.dart';

/// 主题创作中心工具栏。
class ThemeToolbar extends StatelessWidget {
  final VoidCallback onNew;
  final VoidCallback onCopyBuiltin;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback? onAiGenerate;
  final bool exportEnabled;
  final bool aiEnabled;
  final bool aiBusy;

  const ThemeToolbar({
    super.key,
    required this.onNew,
    required this.onCopyBuiltin,
    required this.onSave,
    required this.onExport,
    this.onAiGenerate,
    required this.exportEnabled,
    required this.aiEnabled,
    this.aiBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
            Text('主题创作中心',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            _tb(theme, Icons.add, '新建面板', onNew),
            const SizedBox(width: 4),
            _tb(theme, Icons.copy_all, '从内置复制', onCopyBuiltin),
            const SizedBox(width: 4),
            _tb(theme, Icons.save_outlined, '保存', onSave),
            const SizedBox(width: 12),
            if (onAiGenerate != null) ...[
              _tb(theme, aiBusy ? Icons.hourglass_top : Icons.auto_awesome,
                  aiBusy ? '生成中…' : 'AI 助手', onAiGenerate!,
                  enabled: !aiBusy),
              const SizedBox(width: 4),
            ],
            _tb(
              theme,
              Icons.publish_outlined,
              '导出插件',
              onExport,
              enabled: exportEnabled,
              emphasized: true,
            ),
        ],
      ),
    );
  }

  Widget _tb(ThemeData theme, IconData icon, String label, VoidCallback onTap,
      {bool enabled = true,
      bool emphasized = false,
      String? disabledTooltip}) {
    final scheme = theme.colorScheme;
    if (!enabled) {
      return Tooltip(
        message: disabledTooltip ?? label,
        child: Opacity(
          opacity: 0.4,
          child: _Inner(icon: icon, label: label, scheme: scheme, onTap: null),
        ),
      );
    }
    return Tooltip(
      message: label,
      child: _Inner(
        icon: icon,
        label: label,
        scheme: scheme,
        onTap: onTap,
        emphasized: emphasized,
      ),
    );
  }
}

class _Inner extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final VoidCallback? onTap;
  final bool emphasized;

  const _Inner({
    required this.icon,
    required this.label,
    required this.scheme,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: emphasized ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: emphasized ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: emphasized ? scheme.onPrimary : scheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}

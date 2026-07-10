/// 自定义组件槽位——从 [ComponentDescriptor.config] 读取 html/src 安全预览。
///
/// 出于安全考虑（避免任意 HTML 注入导致 XSS / 脚本执行），
/// 此处**不**直接把 `config.html` 渲染进组件树，而是展示原始源码预览
/// 与目标 src 链接占位，并给出安全提示。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 自定义组件——`custom` 组件。
class CustomSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const CustomSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final html = cfg['html'] as String?;
    final src = cfg['src'] as String?;
    final theme = Theme.of(context);

    final raw = (html ?? src ?? '');
    if (raw.isEmpty) {
      return _emptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
          child: Row(
            children: [
              Icon(Icons.security,
                  size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '自定义内容以只读源码预览展示，未执行注入',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              raw,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置自定义内容 (config.html / config.src)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

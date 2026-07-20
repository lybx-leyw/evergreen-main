/// 自定义组件槽位——从 [ComponentDescriptor.config] 读取 html/src 并真实渲染。
///
/// - `config.html`：作为 HTML 直接注入渲染（使用项目统一的 HtmlWidget）。
/// - `config.src`：展示外部资源链接占位（仍需用户主动跳转或内嵌 WebView）。
/// - 二者皆空：空态提示。
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

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

    if ((html == null || html.isEmpty) && (src == null || src.isEmpty)) {
      return _emptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (html != null && html.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: HtmlWidget(
                html,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        if (src != null && src.isNotEmpty)
          Expanded(
            child: _buildSrcPlaceholder(context, src),
          ),
      ],
    );
  }

  Widget _buildSrcPlaceholder(BuildContext context, String src) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('自定义外部资源',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          SelectableText(
            src,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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

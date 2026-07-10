/// WebView 槽位——从 [ComponentDescriptor.config] 读取 url 安全预览。
///
/// 出于构建与运行时安全的考虑（避免对桌面 webview 原生插件的强依赖），
/// 此处渲染一个只读预览卡片：展示目标 URL 与基本控件占位，
/// 不内嵌真实浏览器引擎。真实 webview 能力由 `webview` 类型后续升级接入。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// WebView——`webview` 组件。
class WebViewSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const WebViewSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final url = cfg['url'] as String? ?? '';
    final allowScripts = cfg['allowScripts'] as bool? ?? true;

    if (url.isEmpty) {
      return _emptyState(context);
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 模拟浏览器工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: () {},
                tooltip: '后退',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: () {},
                tooltip: '前进',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () {},
                tooltip: '刷新',
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(url,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            alignment: Alignment.center,
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.public, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text('网页预览（安全占位）',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  allowScripts ? '允许脚本：是' : '允许脚本：否',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
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
          Icon(Icons.public, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置网页地址 (config.url)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

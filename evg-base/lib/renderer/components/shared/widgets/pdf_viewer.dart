/// PDF 预览原子组件（M3 `pdf-viewer`）。
///
/// ⚠️ 2026-08-02：`pdfx` 依赖已移除——pdf-viewer 组件当前无任何插件使用，且
/// pdfx 的 Windows 原生构建需下载 pdfium（`DownloadProject.cmake` 最低要求
/// CMake 2.8.12，新版 CMake 直接报错），导致 CI 构建失败。
/// 本组件改为**硬编码占位**：保留工具条与标题渲染，正文提示"PDF 预览暂不可用"。
///
/// 日后需要恢复 PDF 查看时：
/// 1. `pubspec.yaml` 重新引入 `pdfx`；
/// 2. 把本组件改回真实实现（`PdfController` + `PdfView`，参考 git 历史）。
///
/// 设计（遵循 M3 规则 R4/R5）：
/// - [url] / [path] 皆空 → 空态提示（R5），绝不白屏/崩溃。
/// - 有源 → 工具条 + 占位正文（PDF 渲染已禁用）。
library;

import 'package:evergreen_base/renderer/components/shared/widgets/empty_state.dart';
import 'package:flutter/material.dart';

class PdfViewerWidget extends StatelessWidget {
  final String? url;
  final String? path;
  final String? title;
  final int initialPage;
  final bool showControls;

  const PdfViewerWidget({
    super.key,
    this.url,
    this.path,
    this.title,
    this.initialPage = 1,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasSource = (path?.isNotEmpty ?? false) || (url?.isNotEmpty ?? false);
    if (!hasSource) {
      return const EmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: '未提供 PDF 地址',
        subtitle: '请在 config 中设置 url 或 path',
      );
    }
    return Column(
      children: [
        if (showControls) _toolbar(context),
        const Expanded(
          child: EmptyState(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF 预览暂不可用',
            subtitle: 'pdfx 渲染已移除，如需查看请重新启用该依赖',
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf_outlined,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title ?? 'PDF 预览',
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

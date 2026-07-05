/// 文档查看器——根据 [DocumentOptions] 渲染 PDF/DOCX 等文档。
///
/// 公开类：[DocumentViewer]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 文档查看组件。
///
/// 基础实现——文档信息 + 占位预览。
/// 后续可接入 pdf_flutter / docx_template 等专业库。
class DocumentViewer extends StatefulWidget {
  final MediaDescriptor media;
  final String? fileUrl;

  const DocumentViewer({
    super.key,
    required this.media,
    this.fileUrl,
  });

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  int _currentPage = 1;
  final int _totalPages = 10; // TODO: 实际页数

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 工具栏
        if (widget.media.controls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_in, size: 18),
                  tooltip: '放大',
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_out, size: 18),
                  tooltip: '缩小',
                  onPressed: () {},
                ),
                const Spacer(),
                Text(
                  '$_currentPage / $_totalPages',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),

        // 文档预览区域
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.description,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.fileUrl?.split('/').last ?? '文档预览',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '第 $_currentPage 页',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),

        // 页面导航
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
              ),
              Text('第 $_currentPage 页'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

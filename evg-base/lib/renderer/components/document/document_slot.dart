/// Document 视图——富文本编辑器 + 修订模式 + 批注 + 目录 + 脚注 + 页眉页脚。
///
/// 公开类：[DocumentView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../shared/widgets/rich_text_editor.dart';
import '../shared/widgets/track_changes_gutter.dart';
import '../shared/widgets/comment_thread.dart';
import '../shared/widgets/empty_state.dart';

/// 文档编辑器范式完整视图。
///
/// V2: 选项从 [ComponentDescriptor.config] 中解析。
class DocumentView extends StatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor? component;

  const DocumentView({super.key, required this.descriptor, this.component});

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  bool _showToc = false;
  bool _showComments = false;

  DocEditorOptions get _opts {
    final raw = widget.component?.config['document'];
    if (raw is Map<String, dynamic>) return DocEditorOptions.fromJson(raw);
    return const DocEditorOptions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 目录面板
          if (_showToc && _opts.tableOfContents)
            SizedBox(
              width: 220,
              child: _buildTocPanel(context),
            ),

          // 主体编辑区（含修订栏）
          Expanded(
            child: Column(
              children: [
                _buildToolbar(context),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: RichTextEditor(
                          options: _opts,
                          // TODO: 绑定文档数据
                        ),
                      ),
                      // 修订栏
                      if (_opts.trackChanges) const TrackChangesGutter(),
                    ],
                  ),
                ),
                // 脚注 / 页眉页脚
                if (_opts.footnotes)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Text(
                      '脚注区域',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ),

          // 批注面板
          if (_showComments && _opts.comments)
            SizedBox(
              width: 260,
              child: const CommentThread(),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // 格式按钮
          IconButton(
            icon: const Icon(Icons.format_bold),
            tooltip: '加粗',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.format_italic),
            tooltip: '斜体',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.format_underlined),
            tooltip: '下划线',
            onPressed: () {},
          ),
          const VerticalDivider(),
          // 面板切换
          if (_opts.tableOfContents)
            IconButton(
              icon: const Icon(Icons.toc),
              tooltip: '目录',
              isSelected: _showToc,
              onPressed: () => setState(() => _showToc = !_showToc),
            ),
          if (_opts.comments)
            IconButton(
              icon: const Icon(Icons.comment),
              tooltip: '批注',
              isSelected: _showComments,
              onPressed: () =>
                  setState(() => _showComments = !_showComments),
            ),
        ],
      ),
    );
  }

  Widget _buildTocPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '目录',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: EmptyState(
              icon: Icons.toc,
              title: '自动生成中...',
            ),
          ),
        ],
      ),
    );
  }
}

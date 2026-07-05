/// 富文本编辑器——文档编辑核心组件。
///
/// 公开类：[RichTextEditor]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 富文本编辑区域。
///
/// 读取 [DocEditorOptions] 控制编辑功能。
/// 简化实现——使用 TextField 作为基础编辑面，
/// 后续可接入 flutter_quill 等专业富文本编辑器。
class RichTextEditor extends StatefulWidget {
  final DocEditorOptions options;
  final String? initialContent;

  const RichTextEditor({
    super.key,
    required this.options,
    this.initialContent,
  });

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialContent ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页眉
            if (widget.options.headersFooters)
              Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Text(
                  '页眉区域',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),

            // 编辑区域——TextField 自带内置滚动，无需外层 SingleChildScrollView
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintText: '开始输入文档内容...',
                ),
              ),
            ),

            // 页脚
            if (widget.options.headersFooters)
              Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Text(
                  '页脚区域',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

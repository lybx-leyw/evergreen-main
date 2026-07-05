/// 代码编辑器——语法高亮 + 行号。
///
/// 公开类：[CodeEditor]
import 'package:flutter/material.dart';

/// 代码/文本编辑器。
///
/// 基础实现——使用 TextField + monospace 字体。
/// 后续可接入 code_editor / flutter_code_editor 等专业编辑库。
class CodeEditor extends StatefulWidget {
  final String language;
  final String? initialContent;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  const CodeEditor({
    super.key,
    this.language = 'text',
    this.initialContent,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late TextEditingController _controller;
  final _lineScrollController = ScrollController();
  int _lineCount = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialContent ?? '');
    _lineCount = _controller.text.split('\n').length;
    _controller.addListener(_updateLineCount);
  }

  void _updateLineCount() {
    final count = _controller.text.split('\n').length;
    if (count != _lineCount) {
      setState(() => _lineCount = count);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateLineCount);
    _controller.dispose();
    _lineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 行号栏——跟随编辑器滚动
        _LineNumberGutter(
          lineCount: _lineCount,
          scrollController: _lineScrollController,
        ),

        // 编辑区域——TextField 自带内置滚动，无需外层 SingleChildScrollView
        Expanded(
          child: TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: widget.onChanged,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }
}

/// 行号栏。
class _LineNumberGutter extends StatelessWidget {
  final int lineCount;
  final ScrollController scrollController;

  const _LineNumberGutter({
    required this.lineCount,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(lineCount, (i) {
              return Container(
                height: 19.5,
                padding: const EdgeInsets.only(right: 8),
                alignment: Alignment.centerRight,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

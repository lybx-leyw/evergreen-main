/// Markdown 渲染面板——支持 $$ 数学公式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownPanel extends StatefulWidget {
  final String markdown;
  final String? translatedMarkdown;
  final bool showTranslated;

  const MarkdownPanel({
    super.key,
    required this.markdown,
    this.translatedMarkdown,
    this.showTranslated = false,
  });

  @override
  State<MarkdownPanel> createState() => _MarkdownPanelState();
}

class _MarkdownPanelState extends State<MarkdownPanel> {
  @override
  Widget build(BuildContext context) {
    final text = (widget.showTranslated &&
            widget.translatedMarkdown != null)
        ? widget.translatedMarkdown!
        : widget.markdown;

    return Container(
      color: const Color(0xFFFAF5EB),
      child: Markdown(
        data: text,
        selectable: true,
        padding: const EdgeInsets.all(16),
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(
              fontSize: 14, height: 1.7, color: Color(0xFF2D1B00)),
          h1: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4A2C00)),
          h2: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00)),
          h3: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF8B6914)),
          code: TextStyle(
              fontSize: 13, backgroundColor: Colors.grey[200],
              fontFamily: 'monospace'),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFFF5ECD7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF8B6914).withAlpha(30)),
          ),
          blockquote: TextStyle(
              fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey[600]),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(
                color: const Color(0xFF8B6914).withAlpha(80), width: 3)),
          ),
        ),
      ),
    );
  }
}

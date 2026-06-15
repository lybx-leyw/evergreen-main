import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/dom.dart' as htmldom;
import 'package:markdown/markdown.dart' as md;
import 'mindmap_widget.dart';

/// 统一的富文本渲染组件。
///
/// 不再使用 flutter_markdown（其 _inlines.isEmpty 断言易崩溃），
/// 改用 markdown→HTML→HtmlWidget 管线。
///
/// 支持：
/// - Markdown（转 HTML 后渲染）
/// - HTML 直通
/// - 思维导图 (` ```mindmap `)
/// - 数学公式 (` ```math ` / ` ```latex `)
/// - Mermaid 图表 (` ```mermaid `)
/// - 20+ 编程语言语法高亮 (` ```python `, ` ```c ` 等)
/// - 主题感知颜色
/// - 卡片式布局（可选）
class MarkdownRenderer extends StatelessWidget {
  final String text;
  final bool markdownFailed;
  final bool useCard;
  final EdgeInsets padding;

  const MarkdownRenderer({
    super.key,
    required this.text,
    this.markdownFailed = false,
    this.useCard = true,
    this.padding = const EdgeInsets.all(16),
  });

  /// 检测文本是否包含 HTML 标签（排除泛型 `<T>` 和比较符号 `<`）。
  static bool hasHtml(String text) {
    return text.contains(RegExp(r'<(/?[a-z][a-z0-9]*|[A-Z][a-zA-Z0-9]{2,})(\s[^>]*)?/?>'));
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = text
        .replaceAll('<br>', '\n')
        .replaceAll('<br/>', '\n')
        .replaceAll('<br />', '\n');

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (markdownFailed) {
      return _buildFallback(cleaned, colorScheme);
    }

    // 按 ```  fence 拆分为段落，分别渲染
    final segments = _parseSegments(cleaned, colorScheme);

    if (!useCard) return segments;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: segments,
      ),
    );
  }

  /// 将文本按 fence 拆分为段落，每段用对应引擎渲染。
  Widget _parseSegments(String text, ColorScheme colorScheme) {
    final children = <Widget>[];
    final buf = StringBuffer();
    var inFence = false;
    String? fenceLang;

    void flushText() {
      final section = buf.toString().trim();
      buf.clear();
      if (section.isEmpty) return;
      // 纯文本段落 → Markdown → HTML → HtmlWidget
      children.add(_buildHtmlSection(section, colorScheme));
    }

    for (final line in text.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```')) {
        if (!inFence) {
          flushText();
          inFence = true;
          fenceLang = trimmed.substring(3).trim().split(' ').first;
          fenceLang = fenceLang.isEmpty ? null : fenceLang;
        } else {
          // fence 闭合
          inFence = false;
          final code = buf.toString().trimRight();
          buf.clear();
          children.add(_buildCodeBlock(code, fenceLang, colorScheme));
          fenceLang = null;
        }
      } else if (inFence) {
        buf.writeln(line);
      } else {
        buf.writeln(line);
      }
    }

    // 处理末尾未闭合 fence 或剩余文本
    if (inFence) {
      final code = buf.toString().trimRight();
      buf.clear();
      children.add(_buildCodeBlock(code, fenceLang, colorScheme));
    } else {
      flushText();
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// 用 HtmlWidget 渲染一段 Markdown/HTML 文本。
  ///
  /// 统一走 markdownToHtml 转换，因为：
  /// - HTML 标签在 markdown 中会被保留（markdown 规范）
  /// - 纯 markdown 需要转换
  /// - 混合内容（markdown + HTML）同时支持
  Widget _buildHtmlSection(String text, ColorScheme colorScheme) {
    try {
      var html = md.markdownToHtml(text);
      // 后处理：HTML 块内残留的 **加粗** 转 <b>（markdownToHtml 不处理 HTML 内部的 markdown）
      html = html.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (m) => '<b>${m.group(1)}</b>',
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HtmlWidget(
          html,
          textStyle: GoogleFonts.maShanZheng(
            fontSize: 15, height: 1.7, letterSpacing: 0.3,
            color: colorScheme.onSurface,
          ),
          customStylesBuilder: _tableStyles,
        ),
      );
    } catch (_) {
      // 转换失败 → 直接尝试 HtmlWidget
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HtmlWidget(
          text,
          textStyle: GoogleFonts.maShanZheng(
            fontSize: 15, height: 1.7, letterSpacing: 0.3,
            color: colorScheme.onSurface,
          ),
        ),
      );
    }
  }

  /// 为 HTML 表格添加边框样式。
  static StylesMap? _tableStyles(htmldom.Element element) {
    final tag = element.localName;
    if (tag == 'table') {
      return {'border-collapse': 'collapse', 'width': '100%'};
    }
    if (tag == 'th' || tag == 'td') {
      return {
        'border': '1px solid #d0d0d0',
        'padding': '6px 10px',
      };
    }
    return null;
  }

  /// 渲染代码块：mindmap / math / mermaid / 语法高亮 / 普通。
  Widget _buildCodeBlock(String code, String? lang, ColorScheme colorScheme) {
    if (code.trim().isEmpty) return const SizedBox.shrink();

    // mindmap
    if (lang == 'mindmap') {
      try {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MindMapWidget(text: code),
        );
      } catch (_) {
        // fall through to plain code block
      }
    }

    // math / latex
    if (lang == 'math' || lang == 'latex') {
      try {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Math.tex(code, textStyle: GoogleFonts.maShanZheng(fontSize: 16)),
          ),
        );
      } catch (_) {
        // fall through to plain code block
      }
    }

    // mermaid
    if (lang == 'mermaid') {
      try {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MermaidDiagram(code: code),
        );
      } catch (_) {
        // fall through to plain code block
      }
    }

    // 已知编程语言 → 语法高亮（先映射别名，再检查）
    final known = _knownLanguages;
    if (lang != null) {
      final mapped = _langAliases[lang] ?? lang;
      if (known.contains(mapped)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                ),
                child: Text(
                  mapped,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: HighlightView(
                  code,
                  language: mapped,
                  theme: githubTheme,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      );
      }
    }

    // 普通代码块
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          code,
          style: GoogleFonts.sourceCodePro(
            fontSize: 13, height: 1.5,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback(String text, ColorScheme colorScheme) {
    final cleanText = text
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^>\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^[-\*]\s+', multiLine: true), '• ')
        .replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^---+$', multiLine: true), '———')
        .replaceAll(RegExp(r'\|', multiLine: true), ' ');

    final widget = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        cleanText,
        style: GoogleFonts.maShanZheng(
          fontSize: 15, height: 1.7, letterSpacing: 0.3,
          color: colorScheme.onSurface,
        ),
      ),
    );

    if (!useCard) return widget;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: widget,
    );
  }

  // ── 语言支持列表 ──────────────────────────────────────────────
  static const _knownLanguages = <String>{
    'python', 'c', 'cpp', 'csharp', 'java', 'javascript', 'typescript',
    'dart', 'go', 'rust', 'kotlin', 'swift', 'ruby', 'php', 'bash',
    'shell', 'sql', 'html', 'css', 'json', 'xml', 'yaml', 'markdown',
    'objectivec', 'r', 'scala', 'perl', 'lua', 'haskell',
  };

  static const _langAliases = <String, String>{
    'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'c++': 'cpp', 'c#': 'csharp', 'cs': 'csharp',
    'rb': 'ruby', 'rs': 'rust', 'kt': 'kotlin',
    'sh': 'bash', 'shell': 'bash', 'zsh': 'bash',
    'm': 'objectivec', 'h': 'objectivec', 'mm': 'objectivec',
  };
}

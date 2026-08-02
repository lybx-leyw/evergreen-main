/// 中栏 V3 — 当前段落译文 + 翻译按钮。
///   支持：AI 导语高亮样式、$$...$$ 显示公式渲染、$...$ 行内公式渲染。
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';
import '../services/paper_vision_service.dart';
import '../services/book_persistence.dart';

class CenterPanel extends ConsumerStatefulWidget {
  const CenterPanel({super.key});
  @override
  ConsumerState<CenterPanel> createState() => _CenterPanelState();
}

class _CenterPanelState extends ConsumerState<CenterPanel> {
  bool _translating = false;

  @override
  Widget build(BuildContext context) {
    final paragraph = currentParagraph(ref);

    return Container(
      color: const Color(0xFFFAF5EB),
      child: Column(children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFF0E8D5),
              border: Border(bottom: BorderSide(color: const Color(0xFF8B6914).withAlpha(40)))),
          child: Row(children: [
            const Text('🌐 译文', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4A2C00))),
            const Spacer(),
            if (paragraph != null)
              TextButton.icon(
                onPressed: _translating ? null : _translate,
                icon: Icon(_translating ? Icons.hourglass_empty : Icons.translate, size: 16),
                label: Text(_translating ? '翻译中...' : '翻译此段'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF8B6914)),
              ),
          ]),
        ),
        Expanded(child: paragraph != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: paragraph.translated.isNotEmpty
                    ? _TranslatedContent(text: paragraph.translated)
                    : const Center(child: Text('点击「翻译此段」获取译文',
                        style: TextStyle(color: Color(0xFFBB9944), fontSize: 13))))
            : const Center(child: Text('未找到论文', style: TextStyle(color: Color(0xFFBB9944)))),
        ),
      ]),
    );
  }

  // ═══════════════ 翻译逻辑 ═══════════════

  void _translate() async {
    final p = currentParagraph(ref);
    if (p == null) return;
    setState(() => _translating = true);

    String apiKey = '';
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY') ?? '';
    } catch (_) {}

    try {
      final svc = PaperVisionService(
          pythonPath: await resolvePythonExe() ?? 'python',
          scriptPath: p.join(greenixScriptsDir, 'paper_vision.py'),
          apiKey: apiKey);
      final result = await svc.translateText(p.content);
      svc.dispose();
      p.translated = result;
    } catch (e) {
      p.translated = '[翻译失败: $e]';
    }
    _persistTranslation();
    if (mounted) setState(() => _translating = false);
  }

  void _persistTranslation() {
    try {
      final chapters = ref.read(chaptersProvider);
      final fullTexts = ref.read(fullTextProvider);
      for (final type in [NotebookType.innovation, NotebookType.survey]) {
        final provider = type == NotebookType.innovation
            ? innovationNotebookProvider : surveyNotebookProvider;
        final nb = ref.read(provider);
        BookPersistence.saveNotebook(
          nb.copyWith(chaptersData: chapters, fullTextsData: fullTexts),
        ).catchError((e) => debugPrint('[CenterPanel] save failed: $e'));
      }
    } catch (e) {
      debugPrint('[CenterPanel] _persistTranslation error: $e');
    }
  }
}

// ═══════════════ 翻译内容渲染（AI 导语 + LaTeX 数学） ═══════════════

class _TranslatedContent extends StatelessWidget {
  final String text;
  const _TranslatedContent({required this.text});

  /// 匹配 $$...$$ 显示公式（支持跨行）。
  static final _displayMathRe = RegExp(r'\$\$\s*(.+?)\s*\$\$', dotAll: true);

  /// 匹配 $...$ 行内公式（不跨行，不匹配 $$）。
  static final _inlineMathRe = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)');

  @override
  Widget build(BuildContext context) {
    // ── 1. 分离 AI 导语 ──
    final hasGuide = text.trimLeft().startsWith('🤖 AI 导语');
    String? guideLine;
    String body = text;
    if (hasGuide) {
      final nl = text.indexOf('\n');
      if (nl > 0) {
        guideLine = text.substring(0, nl).trim();
        body = text.substring(nl + 1).trim();
      }
    }

    final children = <Widget>[];
    if (guideLine != null) {
      children.add(_GuideBanner(line: guideLine));
      children.add(const SizedBox(height: 12));
    }
    children.addAll(_parseDisplayMath(body));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// 按 $$...$$ 拆分，中间为 SelectableText（含行内公式），数学处为居中 Math.tex。
  List<Widget> _parseDisplayMath(String input) {
    final widgets = <Widget>[];
    int lastEnd = 0;
    for (final m in _displayMathRe.allMatches(input)) {
      if (m.start > lastEnd) {
        final chunk = input.substring(lastEnd, m.start).trim();
        if (chunk.isNotEmpty) widgets.add(_buildTextWithInlineMath(chunk));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _SafeMath(
          formula: (m.group(1) ?? '').trim(),
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 15, color: Color(0xFF2D1B00)),
          scrollable: true,
        ),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < input.length) {
      final chunk = input.substring(lastEnd).trim();
      if (chunk.isNotEmpty) widgets.add(_buildTextWithInlineMath(chunk));
    }
    return widgets;
  }

  /// 渲染含 $...$ 行内公式的文本段。
  Widget _buildTextWithInlineMath(String chunk) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final m in _inlineMathRe.allMatches(chunk)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: chunk.substring(lastEnd, m.start)));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _SafeMath(
          formula: (m.group(1) ?? '').trim(),
          mathStyle: MathStyle.text,
          textStyle: const TextStyle(fontSize: 13, color: Color(0xFF2D1B00)),
        ),
      ));
      lastEnd = m.end;
    }
    if (lastEnd < chunk.length) {
      spans.add(TextSpan(text: chunk.substring(lastEnd)));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF2D1B00)),
          children: spans,
        ),
      ),
    );
  }
}

// ═══════════════ AI 导语样式组件 ═══════════════

class _GuideBanner extends StatelessWidget {
  final String line;
  const _GuideBanner({required this.line});

  @override
  Widget build(BuildContext context) {
    // 去掉 "🤖 AI 导语：" 前缀，只保留内容
    final content = line.replaceFirst(RegExp(r'🤖\s*AI\s*导语[：:]?\s*'), '');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4A017).withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text('🤖', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:           SelectableText(
              content,
              style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Color(0xFF6B4C00), height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════ 安全数学渲染（KaTeX 不支持的命令 fallback 为纯文本） ═══════════════

class _SafeMath extends StatelessWidget {
  final String formula;
  final MathStyle mathStyle;
  final TextStyle textStyle;
  final bool scrollable;

  const _SafeMath({
    required this.formula,
    this.mathStyle = MathStyle.display,
    required this.textStyle,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget math;
    try {
      math = Math.tex(formula, mathStyle: mathStyle, textStyle: textStyle);
    } catch (_) {
      math = SelectableText(formula, style: textStyle);
    }
    if (scrollable) {
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: math);
    }
    return math;
  }
}

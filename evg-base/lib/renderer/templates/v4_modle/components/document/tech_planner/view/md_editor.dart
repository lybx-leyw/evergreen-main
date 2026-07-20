/// Markdown 编辑器——基于 re_editor，含语法高亮与格式化工具栏。
///
/// 使用 `re_highlight` 的 markdown 语言模式提供语法高亮。
/// 支持幽灵文本补全浮层（Phase 2）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart' as re;
import 'package:re_highlight/re_highlight.dart' as rh;
import 'package:re_highlight/languages/markdown.dart' as lang;
import 'package:re_highlight/styles/atom-one-dark.dart' as dark;

import 'ghost_text_overlay.dart';

/// Markdown 编辑器。
///
/// 基于 [re_editor]（Reqable 项目，v0.10.0），提供：
/// - Markdown 语法高亮（#标题、**粗体**、*斜体*、`代码`、```代码块```）
/// - 格式化工具栏（标题/粗体/斜体/代码/链接/列表）
/// - 幽灵文本补全浮层（Phase 2，通过 [ghostState] 控制）
class MdEditor extends StatefulWidget {
  final String initialContent;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onAiTriggered;

  /// 幽灵文本状态（Phase 2）。
  ///
  /// 非 null 时在光标后方显示补全建议。
  final GhostTextState? ghostState;

  /// Tab 键采纳幽灵文本回调。
  final VoidCallback? onGhostAccept;

  /// 继续输入使幽灵文本消失回调。
  final VoidCallback? onGhostDismiss;

  const MdEditor({
    super.key,
    this.initialContent = '',
    this.onChanged,
    this.onAiTriggered,
    this.ghostState,
    this.onGhostAccept,
    this.onGhostDismiss,
  });

  @override
  State<MdEditor> createState() => _MdEditorState();
}

class _MdEditorState extends State<MdEditor> {
  late re.CodeLineEditingController _controller;
  final _scrollController = re.CodeScrollController();
  final _focusNode = FocusNode();
  String _lastContent = '';
  bool _suppressNotify = false;

  @override
  void initState() {
    super.initState();
    _controller = re.CodeLineEditingController.fromText(widget.initialContent);
    _lastContent = widget.initialContent;
    _controller.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onContentChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MdEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialContent != widget.initialContent &&
        widget.initialContent != _controller.text) {
      _suppressNotify = true;
      _controller.text = widget.initialContent;
      _lastContent = widget.initialContent;
      _suppressNotify = false;
    }
  }

  void _onContentChanged() {
    if (_suppressNotify) return;
    final text = _controller.text;
    if (text != _lastContent) {
      _lastContent = text;
      widget.onChanged?.call(text);
    }
  }

  // ═══════ 格式化方法 ═══════

  void _wrapSelection(String before, String after, {String? defaultText}) {
    final selection = _controller.selection;
    final text = _controller.text;

    if (!selection.isCollapsed) {
      // 有选中文本 → 包裹
      final selText = text.substring(
        _selectionStartOffset(selection),
        _selectionEndOffset(selection),
      );
      _controller.replaceSelection('$before$selText$after');
    } else {
      // 无选中 → 插入占位 + 选中占位
      final placeholder = defaultText ?? 'text';
      _controller.replaceSelection('$before$placeholder$after');
      // 选中占位文本
      final pos = selection.startOffset + before.length;
      final lineIndex = selection.startIndex;
      _controller.selection = re.CodeLineSelection(
        baseIndex: lineIndex,
        baseOffset: pos,
        extentIndex: lineIndex,
        extentOffset: pos + placeholder.length,
      );
    }
    _focusNode.requestFocus();
  }

  void _insertHeading(int level) {
    final prefix = '${'#' * level} ';
    final selection = _controller.selection;
    final lineIndex = selection.startIndex;

    // 获取当前行文本
    final codeLines = _controller.codeLines;
    final line = codeLines[lineIndex];

    // 在当前行首插入 # 标记
    final replaceLen = prefix.length;
    _controller.replaceSelection(prefix);
    _focusNode.requestFocus();
  }

  void _insertList(String marker) {
    final selection = _controller.selection;
    final lineIndex = selection.startIndex;

    // 在当前行首插入列表标记
    _controller.replaceSelection('$marker ');
    _focusNode.requestFocus();
  }

  Future<void> _checkAiTrigger() async {
    final text = _controller.text;
    final atAiIndex = text.lastIndexOf('@ai');
    if (atAiIndex >= 0) {
      // 提取 @ai 后的查询文本
      final queryAfter = text.substring(atAiIndex + 3).trim();

      // 移除 @ai 标记
      _suppressNotify = true;
      _controller.text = text.substring(0, atAiIndex);
      _lastContent = _controller.text;
      _suppressNotify = false;

      widget.onChanged?.call(_controller.text);
      widget.onAiTriggered?.call(queryAfter);
    }
  }

  // ═══════ 选择偏移工具 ═══════

  int _selectionStartOffset(re.CodeLineSelection sel) {
    // 计算从文档开头的绝对字符偏移
    int offset = 0;
    for (int i = 0; i < sel.startIndex; i++) {
      offset += _controller.codeLines[i].text.length + 1; // +1 for \n
    }
    offset += sel.startOffset;
    return offset;
  }

  int _selectionEndOffset(re.CodeLineSelection sel) {
    int offset = 0;
    for (int i = 0; i < sel.endIndex; i++) {
      offset += _controller.codeLines[i].text.length + 1;
    }
    offset += sel.endOffset;
    return offset;
  }

  // ═══════ 键盘快捷键 ═══════

  /// 自定义快捷键构建器。
  ///
  /// 包含 Markdown 格式化快捷键 + 幽灵文本 Tab 键采纳。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // ── 幽灵文本：Tab 采纳 / 输入消失 ──
    final ghost = widget.ghostState;
    if (ghost != null && ghost.hasCompletion) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.tab) {
          widget.onGhostAccept?.call();
          return KeyEventResult.handled;
        }
        // 非修饰键可打印字符 → 结束幽灵文本
        if (event is !KeyRepeatEvent &&
            event.character != null &&
            event.character!.isNotEmpty &&
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isAltPressed &&
            !HardwareKeyboard.instance.isMetaPressed) {
          // 延迟检查，确保编辑器已更新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onGhostDismiss?.call();
          });
        }
      }
    }

    // ── Markdown 格式化快捷键 ──
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      final logicalKey = event.logicalKey;
      if (logicalKey == LogicalKeyboardKey.keyB) {
        _wrapSelection('**', '**', defaultText: '粗体');
        return KeyEventResult.handled;
      }
      if (logicalKey == LogicalKeyboardKey.keyI) {
        _wrapSelection('*', '*', defaultText: '斜体');
        return KeyEventResult.handled;
      }
      if (logicalKey == LogicalKeyboardKey.keyK) {
        _wrapSelection('[', '](url)', defaultText: '链接文本');
        return KeyEventResult.handled;
      }
      for (int i = 1; i <= 6; i++) {
        if (logicalKey == LogicalKeyboardKey(int.parse('0x30$i'))) {
          _insertHeading(i);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Focus(
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          // ── 格式化工具栏 ──
          _buildToolbar(theme, colorScheme, isDark),

          // ── 编辑器主体（含幽灵文本浮层） ──
          Expanded(
            child: Container(
              color: isDark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFFAFAFA),
              child: Stack(
                children: [
                  // 底层：CodeEditor
                  re.CodeEditor(
                    controller: _controller,
                    focusNode: _focusNode,
                    scrollController: _scrollController,
                    style: re.CodeEditorStyle(
                      fontSize: 15,
                      fontHeight: 1.6,
                      fontFamily:
                          'Cascadia Code, Fira Code, JetBrains Mono, Consolas, monospace',
                      cursorColor: colorScheme.primary,
                      cursorLineColor:
                          colorScheme.primary.withValues(alpha: 0.08),
                      selectionColor:
                          colorScheme.primary.withValues(alpha: 0.25),
                      codeTheme: re.CodeHighlightTheme(
                        languages: {
                          'markdown': re.CodeHighlightThemeMode(
                            mode: lang.langMarkdown,
                          ),
                        },
                        theme: dark.atomOneDarkTheme,
                      ),
                    ),
                    indicatorBuilder: _buildIndicator,
                  ),

                  // 顶层：幽灵文本浮层（Phase 2）
                  if (widget.ghostState != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: GhostTextOverlay(
                          editingController: _controller,
                          ghostState: widget.ghostState!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── 状态栏 ──
          _buildStatusBar(theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildIndicator(
    BuildContext context,
    re.CodeLineEditingController editingController,
    re.CodeChunkController chunkController,
    ValueNotifier<re.CodeIndicatorValue?> notifier,
  ) {
    return Row(
      children: [
        re.DefaultCodeLineNumber(
          controller: editingController,
          notifier: notifier,
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF252526)
            : colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _toolbarButton(Icons.title, '标题1', () => _insertHeading(1)),
            _toolbarButton(
                Icons.text_fields, '标题2', () => _insertHeading(2)),
            _toolbarButton(Icons.format_bold, '粗体 (Ctrl+B)',
                () => _wrapSelection('**', '**', defaultText: '粗体')),
            _toolbarButton(Icons.format_italic, '斜体 (Ctrl+I)',
                () => _wrapSelection('*', '*', defaultText: '斜体')),
            _toolbarButton(
                Icons.code, '行内代码', () => _wrapSelection('`', '`', defaultText: 'code')),
            _divider(),
            _toolbarButton(Icons.code_off, '代码块',
                () => _wrapSelection('\n```\n', '\n```\n', defaultText: 'language\ncode')),
            _toolbarButton(Icons.link, '链接 (Ctrl+K)',
                () => _wrapSelection('[', '](url)', defaultText: '链接文本')),
            _toolbarButton(Icons.format_list_bulleted, '无序列表', () => _insertList('-')),
            _toolbarButton(Icons.format_list_numbered, '有序列表', () => _insertList('1.')),
            _toolbarButton(Icons.horizontal_rule, '分隔线', () => _wrapSelection('\n\n---\n\n', '')),
            const SizedBox(width: 16),
            _toolbarButton(Icons.smart_toy_outlined, '触发 @ai 分析', _checkAiTrigger,
                color: colorScheme.tertiary),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback onTap,
      {Color? color}) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              size: 20, color: color ?? theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _divider() {
    final theme = Theme.of(context);
    return Container(
      width: 1,
      height: 20,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }

  Widget _buildStatusBar(ThemeData theme, ColorScheme colorScheme) {
    final lines = _controller.lineCount;
    final chars = _controller.text.length;
    final selection = _controller.selection;
    final lineInfo = selection.isCollapsed
        ? 'L${selection.startIndex + 1}, C${selection.startOffset + 1}'
        : 'L${selection.startIndex + 1}-${selection.endIndex + 1}';

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Text('Markdown',
              style:
                  TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Text('$lines 行',
              style: const TextStyle(fontSize: 11, color: Colors.white30)),
          const SizedBox(width: 12),
          Text('$chars 字符',
              style: const TextStyle(fontSize: 11, color: Colors.white30)),
          const Spacer(),
          Text(lineInfo,
              style: const TextStyle(fontSize: 11, color: Colors.white30)),
        ],
      ),
    );
  }
}

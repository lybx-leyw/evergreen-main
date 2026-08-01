/// 代码编辑器——基于 re_editor (Reqable)，VSCode 级别的编辑体验。
///
/// 替换了旧的 flutter_highlight + TextField 方案。
/// re_editor 自研布局/绘制/事件引擎，非 TextField 二次封装，
/// 提供语法高亮、代码折叠、VSCode 风格快捷键。
library;

import 'dart:math' show min, max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:re_editor/re_editor.dart' as re;
import 'package:re_highlight/re_highlight.dart' as rh;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark.dart' as dark;
import 'package:re_highlight/styles/atom-one-light.dart' as light;

/// 代码/文本编辑器。
///
/// 使用 [re_editor](https://pub.dev/packages/re_editor) (Reqable 项目) 提供：
/// - 语法高亮（20+ 语言）
/// - 代码折叠
/// - VSCode 风格快捷键
/// - 自研高性能渲染引擎
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
  late re.CodeLineEditingController _controller;
  final _scrollController = re.CodeScrollController();

  /// 翻页行数——re_editor v0.10.0 的 moveCursorToPageUp/Down 是空 TODO，
  /// 所以我们在 Actions 层拦截 PageUp/PageDown 并自行移动光标。
  static const int _kPageSize = 24;

  /// 语言名 → re_highlight Mode 映射。
  static final Map<String, rh.Mode> _modeForLang = {
    'dart': langDart,
    'python': langPython, 'py': langPython,
    'javascript': langJavascript, 'js': langJavascript,
    'typescript': langTypescript, 'ts': langTypescript,
    'json': langJson,
    'yaml': langYaml, 'yml': langYaml,
    'xml': langXml, 'html': langXml,
    'css': langCss, 'scss': langScss,
    'sql': langSql,
    'java': langJava,
    'kotlin': langKotlin,
    'swift': langSwift,
    'c': langC, 'cpp': langCpp, 'csharp': langCsharp,
    'go': langGo, 'rust': langRust,
    'ruby': langRuby,
    'php': langPhp,
    'bash': langBash, 'shell': langShell,
    'powershell': langPowershell,
    'markdown': langMarkdown, 'md': langMarkdown,
  };

  @override
  void initState() {
    super.initState();
    _controller = re.CodeLineEditingController.fromText(
      widget.initialContent ?? '',
    );
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    widget.onChanged?.call(_controller.text);
  }

  @override
  void didUpdateWidget(CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialContent != null &&
        widget.initialContent != oldWidget.initialContent &&
        widget.initialContent != _controller.text) {
      _controller.text = widget.initialContent!;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 翻页光标移动——替代 re_editor 的空 TODO 实现。
  void _moveCursorPage(bool forward) {
    final codeLines = _controller.codeLines;
    final current = _controller.selection.extent;
    final int lineCount = codeLines.length;

    int targetIndex;
    if (forward) {
      targetIndex = min(lineCount - 1, current.index + _kPageSize);
    } else {
      targetIndex = max(0, current.index - _kPageSize);
    }

    if (targetIndex == current.index) return; // 已在头/尾

    _controller.selection = re.CodeLineSelection.collapsed(
      index: targetIndex,
      offset: min(codeLines[targetIndex].length, current.offset),
    );

    debugPrint('[CodeEditor:PAGE] forward=$forward'
        ' from=${current.index} to=$targetIndex pageSize=$_kPageSize');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = widget.language.toLowerCase();
    final mode = _modeForLang[lang];
    debugPrint('[CodeEditor:BUILD] lang=$lang readOnly=${widget.readOnly}'
        ' hasMode=${mode != null} contentLen=${widget.initialContent?.length ?? 0}');

    // 构建语法高亮主题（如果该语言被支持）
    final codeTheme = mode != null
        ? re.CodeHighlightTheme(
            languages: {
              lang: re.CodeHighlightThemeMode(mode: mode),
            },
            theme: isDark ? dark.atomOneDarkTheme : light.atomOneLightTheme,
          )
        : null;

    debugPrint('[CodeEditor:BUILD] creating re.CodeEditor with shortcutsActivatorsBuilder=_AppShortcuts');
    final editor = re.CodeEditor(
      controller: _controller,
      scrollController: _scrollController,
      readOnly: widget.readOnly,
      style: re.CodeEditorStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        fontHeight: 1.5,
        codeTheme: codeTheme,
      ),
      indicatorBuilder: _buildIndicator,
      chunkAnalyzer: const re.DefaultCodeChunkAnalyzer(),
      // 补上 re_editor 默认遗漏的 Page Up / Page Down 快捷键
      shortcutsActivatorsBuilder: _AppShortcuts(),
    );

    // Actions 拦截 PageUp/PageDown：re_editor v0.10.0
    // moveCursorToPageUp/Down 是空 TODO，在此层替代实现。
    final body = Actions(
      actions: {
        re.CodeShortcutCursorMovePageIntent: _PageMoveAction(
          controller: _controller,
          onInvoke: (intent) {
            _moveCursorPage(intent.forward);
            return null;
          },
        ),
      },
      child: editor,
    );

    // re_editor 内部 CodeField 要求显式宽度约束，键盘弹出/收起时约束可能
    // 临时无界；用 LayoutBuilder 检测并兜底为屏幕宽度。
    return LayoutBuilder(
      builder: (context, constraints) {
        debugPrint('[CodeEditor:BUILD] maxWidth=${constraints.maxWidth} bounded=${constraints.hasBoundedWidth}');
        if (constraints.hasBoundedWidth) return body;
        final fallbackWidth = MediaQuery.of(context).size.width;
        debugPrint('[CodeEditor:BUILD] width is unbounded → fallback to $fallbackWidth');
        return SizedBox(width: fallbackWidth, child: body);
      },
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
        re.DefaultCodeChunkIndicator(
          width: 20,
          controller: chunkController,
          notifier: notifier,
        ),
      ],
    );
  }
}

/// 自定义快捷键构建器——补上 re_editor 默认遗漏的 Page Up/Down。
class _AppShortcuts extends re.CodeShortcutsActivatorsBuilder {
  _AppShortcuts() {
    debugPrint('[AppShortcuts:INIT] _AppShortcuts instance created'
        ' pageUp=$LogicalKeyboardKey.pageUp pageDown=$LogicalKeyboardKey.pageDown');
  }

  static final _defaultShortcuts = {
    re.CodeShortcutType.cursorMovePageUp: <ShortcutActivator>[
      const SingleActivator(LogicalKeyboardKey.pageUp),
    ],
    re.CodeShortcutType.cursorMovePageDown: <ShortcutActivator>[
      const SingleActivator(LogicalKeyboardKey.pageDown),
    ],
    re.CodeShortcutType.selectionExtendPageStart: <ShortcutActivator>[
      const SingleActivator(LogicalKeyboardKey.pageUp, shift: true),
    ],
    re.CodeShortcutType.selectionExtendPageEnd: <ShortcutActivator>[
      const SingleActivator(LogicalKeyboardKey.pageDown, shift: true),
    ],
  };

  @override
  List<ShortcutActivator>? build(re.CodeShortcutType type) {
    final result = _defaultShortcuts[type];
    if (result != null) {
      debugPrint('[AppShortcuts:BUILD] type=$type → CUSTOM (${result.length} activators)');
    } else {
      final fallback = re.DefaultCodeShortcutsActivatorsBuilder().build(type);
      debugPrint('[AppShortcuts:BUILD] type=$type → DEFAULT (${fallback?.length ?? 0} activators)');
      return fallback;
    }
    return result;
  }
}

/// 拦截 re_editor 的 PageUp/PageDown Intent，在 Actions 层替代空 TODO 实现。
///
/// re_editor v0.10.0 的 [CodeLineEditingValue.moveCursorToPageUp] /
/// [CodeLineEditingValue.moveCursorToPageDown] 是空 // TODO 实现。
/// 通过祖先 Actions widget 拦截，在空的 controller 方法被调用前自行移动光标。
class _PageMoveAction extends CallbackAction<re.CodeShortcutCursorMovePageIntent> {
  final re.CodeLineEditingController controller;

  _PageMoveAction({
    required this.controller,
    required super.onInvoke,
  });

  @override
  bool consumesKey(re.CodeShortcutCursorMovePageIntent intent) {
    // IME 组合态时不消费，让按键传递给 IME
    return !controller.isComposing;
  }
}

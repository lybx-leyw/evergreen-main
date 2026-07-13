/// 幽灵文本补全浮层（Phase 2）。
///
/// 在 re_editor 光标后方显示浅灰色补全建议文本。
/// Tab 键采纳，继续输入自动消失。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

/// 幽灵文本配置。
class GhostTextConfig {
  /// 幽灵文本颜色。
  final Color color;

  /// 幽灵文本字号。
  final double fontSize;

  const GhostTextConfig({
    this.color = Colors.white38,
    this.fontSize = 14,
  });
}

/// 幽灵文本状态。
class GhostTextState {
  /// 当前补全文本（null 表示无补全）。
  final String? completionText;

  /// 是否正在加载补全。
  final bool isLoading;

  const GhostTextState({
    this.completionText,
    this.isLoading = false,
  });

  bool get hasCompletion =>
      completionText != null && completionText!.isNotEmpty;

  static const empty = GhostTextState();
}

/// 幽灵文本覆盖层。
///
/// 通过 [Stack] 叠加在编辑器上层，在光标后方显示补全建议。
///
/// 使用方式：
/// ```dart
/// Stack(
///   children: [
///     CodeEditor(...),
///     Positioned.fill(
///       child: IgnorePointer(
///         child: GhostTextOverlay(
///           editingController: _controller,
///           ghostState: _ghostState,
///         ),
///       ),
///     ),
///   ],
/// )
/// ```
class GhostTextOverlay extends StatelessWidget {
  /// re_editor 的编辑控制器。
  final CodeLineEditingController editingController;

  /// 当前幽灵文本状态。
  final GhostTextState ghostState;

  /// 显示配置。
  final GhostTextConfig config;

  const GhostTextOverlay({
    super.key,
    required this.editingController,
    required this.ghostState,
    this.config = const GhostTextConfig(),
  });

  @override
  Widget build(BuildContext context) {
    if (!ghostState.hasCompletion) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<CodeLineEditingValue>(
      valueListenable: editingController,
      builder: (context, value, child) {
        final sel = value.selection;
        if (!sel.isCollapsed) {
          // 有选中文本时不显示幽灵文本
          return const SizedBox.shrink();
        }

        // 获取当前行索引和偏移
        final lineIndex = sel.startIndex;
        if (lineIndex >= value.codeLines.length) {
          return const SizedBox.shrink();
        }

        final codeLines = value.codeLines;
        final lineText = codeLines[lineIndex].text;
        final columnOffset = sel.startOffset;

        return _buildGhostWidget(context, lineText, columnOffset, lineIndex);
      },
    );
  }

  Widget _buildGhostWidget(
    BuildContext context,
    String lineText,
    int columnOffset,
    int lineIndex,
  ) {
    final textStyle = TextStyle(
      color: config.color,
      fontSize: config.fontSize,
      fontFamily: 'monospace',
    );

    // 光标前文本（透明占位）
    final beforeCursor = columnOffset <= lineText.length
        ? lineText.substring(0, columnOffset)
        : lineText;

    // 光标后已有文本 + AI 补全
    final afterCursor = columnOffset < lineText.length
        ? lineText.substring(columnOffset)
        : '';
    final ghostText = '$afterCursor${ghostState.completionText ?? ''}';

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          text: TextSpan(
            children: [
              // 光标前文本（透明占位，保持对齐）
              TextSpan(
                text: beforeCursor,
                style: textStyle.copyWith(color: Colors.transparent),
              ),
              // 幽灵文本
              TextSpan(text: ghostText, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// 幽灵文本键盘交互包装器。
///
/// 监听 Tab 键和其他输入事件，实现采纳/消失逻辑。
///
/// ```dart
/// GhostTextKeyboardHandler(
///   editingController: _controller,
///   ghostState: _ghostState,
///   onAccept: _onGhostAccept,
///   onDismiss: _onGhostDismiss,
///   child: CodeEditor(...),
/// )
/// ```
class GhostTextKeyboardHandler extends StatefulWidget {
  final Widget child;
  final CodeLineEditingController editingController;
  final GhostTextState ghostState;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  const GhostTextKeyboardHandler({
    super.key,
    required this.child,
    required this.editingController,
    required this.ghostState,
    this.onAccept,
    this.onDismiss,
  });

  @override
  State<GhostTextKeyboardHandler> createState() =>
      _GhostTextKeyboardHandlerState();
}

class _GhostTextKeyboardHandlerState
    extends State<GhostTextKeyboardHandler> {
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _lastText = widget.editingController.text;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (!widget.ghostState.hasCompletion) {
          return KeyEventResult.ignored;
        }

        if (event is KeyDownEvent) {
          // Tab → 采纳
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            widget.onAccept?.call();
            return KeyEventResult.handled;
          }

          // 非修饰键 → 继续输入 → 消失
          if (event is KeyRepeatEvent ||
              event.character != null && event.character!.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkContentChanged();
            });
          }
        }

        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }

  void _checkContentChanged() {
    if (!mounted) return;
    final current = widget.editingController.text;
    if (current != _lastText && widget.ghostState.hasCompletion) {
      widget.onDismiss?.call();
    }
    _lastText = current;
  }
}

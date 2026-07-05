/// 流式光标——根据 [StreamOptions] 渲染打字机/淡入/闪烁光标效果。
///
/// 公开类：[StreamingCursor]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 流式文本 + 光标组件。
///
/// 读取 [StreamOptions] 控制：
/// - animation: typewriter | fade | none
/// - cursorStyle: blinking | static | none
class StreamingCursor extends StatefulWidget {
  final String text;
  final StreamOptions options;

  const StreamingCursor({
    super.key,
    required this.text,
    required this.options,
  });

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    if (widget.options.cursorStyle == 'blinking') {
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant StreamingCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[Cursor] didUpdateWidget oldTextLen=${oldWidget.text.length} newTextLen=${widget.text.length} hashCode=${identityHashCode(this)}');
    if (oldWidget.text != widget.text) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.text.length > 80 ? '${widget.text.substring(0, 80)}...' : widget.text;
    debugPrint('[Cursor] BUILD textLen=${widget.text.length} preview="$preview" hashCode=${identityHashCode(this)}');
    final showCursor = widget.options.cursorStyle != 'none';
    final animation = widget.options.animation;

    Widget textWidget = Text(
      widget.text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            height: 1.6,
          ),
    );

    // 动画包装
    if (animation == 'fade') {
      textWidget = AnimatedOpacity(
        opacity: widget.text.isNotEmpty ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: textWidget,
      );
    }

    if (!showCursor) return textWidget;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: textWidget),
        if (widget.options.cursorStyle == 'static')
          Container(
            width: 2,
            height: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        if (widget.options.cursorStyle == 'blinking')
          AnimatedBuilder(
            animation: _cursorController,
            builder: (context, child) {
              return Opacity(
                opacity: _cursorController.value > 0.5 ? 1.0 : 0.0,
                child: Container(
                  width: 2,
                  height: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 消息气泡——根据 [BubbleOptions] 渲染单条聊天气泡。
///
/// 公开类：[MessageBubble]
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/app/service/theme/theme_provider.dart';
import 'models.dart';
import 'thinking_block.dart';
import 'tool_call_card.dart';
import 'streaming_cursor.dart';
import 'markdown_renderer.dart';

/// 单条消息气泡。
///
/// 读取 [BubbleOptions] 控制：
/// - style: rounded(16px) | flat(4px) | minimal(0px)
/// - avatarPosition: left | none
/// - showTimestamp: bool
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final BubbleOptions bubble;
  final StreamOptions stream;
  final bool isLast;
  final ThinkingOptions? thinking;
  final ToolCallOptions? toolCalls;

  /// 是否显示内联思考块。
  /// 当统一思考面板已收集所有思考时设为 false。
  final bool showThinking;

  const MessageBubble({
    super.key,
    required this.message,
    required this.bubble,
    required this.stream,
    this.isLast = false,
    this.thinking,
    this.toolCalls,
    this.showThinking = true,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showActions = false;
  bool _copied = false;

  ChatMessage get _message => widget.message;
  bool get _isUser => _message.isUser;
  bool get _isLast => widget.isLast;
  BubbleOptions get _bubble => widget.bubble;
  StreamOptions get _stream => widget.stream;
  ThinkingOptions? get _thinking => widget.thinking;
  ToolCallOptions? get _toolCalls => widget.toolCalls;

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[Bubble] didUpdateWidget oldContentLen=${oldWidget.message.content.length} newContentLen=${widget.message.content.length} hashCode=${identityHashCode(this)}');
    // 当消息内容或思考内容变化时，强制重建
    if (oldWidget.message.content != widget.message.content ||
        oldWidget.message.thinkingContent != widget.message.thinkingContent ||
        oldWidget.isLast != widget.isLast ||
        oldWidget.showThinking != widget.showThinking) {
      setState(() {});
    }
  }

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: _message.content));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUser = _isUser;
    debugPrint('[Bubble] BUILD role=${_message.role} contentLen=${_message.content.length} isLast=$_isLast showThinking=${widget.showThinking} stream=${_stream.enabled} hashCode=${identityHashCode(this)}');
    debugPrint('[Bubble]   content preview="${_message.content.length > 60 ? '${_message.content.substring(0, 60)}...' : _message.content}"');
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isUser
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    // 获取组件 token 覆盖（key 与 theme.json 一致）
    final tokenBg = context.componentColor('bubble', isUser ? 'user' : 'assistant');
    final tokenText = context.componentColor('bubble', 'text');

    // 气泡圆角
    final r = switch (_bubble.style) {
      'rounded' => 16.0,
      'flat' => 4.0,
      'minimal' => 0.0,
      _ => 16.0,
    };

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 48 : 12,
        right: isUser ? 12 : 48,
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // 思考块（仅助手消息，且 showThinking 为 true）
          if (!isUser &&
              widget.showThinking &&
              _thinking != null &&
              _thinking!.visible &&
              _message.thinkingContent != null)
            ThinkingBlock(
              content: _message.thinkingContent!,
              options: _thinking!,
            ),

          // 工具调用卡片（仅助手消息）
          if (!isUser &&
              _toolCalls != null &&
              _toolCalls!.visible &&
              _message.toolCalls.isNotEmpty)
            ..._message.toolCalls.map((tc) => ToolCallCard(
                  call: tc,
                  options: _toolCalls!,
                )),

          // 消息气泡 — 长按或悬停显示操作栏
          MouseRegion(
            onEnter: (_) => setState(() => _showActions = true),
            onExit: (_) => setState(() => _showActions = false),
            child: GestureDetector(
              onLongPress: () => setState(() => _showActions = !_showActions),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 头像（非用户侧 + avatarPosition=left）
                      if (!isUser && _bubble.avatarPosition == 'left')
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: const Icon(Icons.eco, size: 16, color: Colors.white),
                          ),
                        ),

                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: isUser ? 10 : 14,
                            vertical: isUser ? 6 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: tokenBg ?? bgColor,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(r),
                              topRight: Radius.circular(r),
                              bottomLeft: Radius.circular(isUser ? r : 4),
                              bottomRight: Radius.circular(isUser ? 4 : r),
                            ),
                            border: isUser
                                ? Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.15),
                                  )
                                : null,
                          ),
                          child: _message.content.isNotEmpty
                              ? _isLast && _stream.enabled && !isUser
                                  ? StreamingCursor(
                                      text: _message.content,
                                      options: _stream,
                                    )
                                  : MarkdownRenderer(
                                      text: _message.content,
                                      useCard: false,
                                      padding: EdgeInsets.zero,
                                    )
                              : const SizedBox(),
                        ),
                      ),

                      // 头像（用户侧）
                      if (isUser && _bubble.avatarPosition == 'left')
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            child: const Icon(Icons.person, size: 16, color: Colors.white),
                          ),
                        ),
                    ],
                  ),

                  // ── 操作栏：仅助手消息 + 有内容 + 不在流式中 ──
                  if (!isUser &&
                      _message.content.isNotEmpty &&
                      _showActions &&
                      !(_isLast && _stream.enabled))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 复制按钮
                          _ActionChip(
                            icon: _copied ? Icons.check : Icons.content_copy,
                            label: _copied ? '已复制' : '复制',
                            color: _copied
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            onTap: _copyContent,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ _ActionChip ═══════

/// 气泡底部操作按钮——复制、重新生成等。
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fgColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fgColor),
              const SizedBox(width: 3),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: fgColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

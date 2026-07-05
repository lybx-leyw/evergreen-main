/// 聊天输入栏——根据 [InputOptions] + [ChatOptions] 渲染输入区域。
///
/// 公开类：[ChatInputBar]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart' show webSearchEnabledProvider, deepThinkingEnabledProvider;
import '../shared/theme_provider.dart';

/// 聊天输入栏。
///
/// 读取 [InputOptions] 配置输入模式（free-text / type-check / code / select）。
/// 在 chat 模式下固定使用 free-text。
class ChatInputBar extends ConsumerStatefulWidget {
  final InputOptions? input;
  final ChatOptions chatOptions;
  final WorkspaceDescriptor? workspace;
  final void Function(String text)? onSend;
  final void Function()? onAttach;
  final void Function()? onWorkspace;

  const ChatInputBar({
    super.key,
    this.input,
    required this.chatOptions,
    this.workspace,
    this.onSend,
    this.onAttach,
    this.onWorkspace,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _multiline = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.chatOptions.placeholder;
    final hasAttach = widget.input?.attachments?.enabled ?? false;
    final maxLength = widget.input?.maxLength;
    final theme = Theme.of(context);
    final fgColor = theme.colorScheme.onSurfaceVariant;

    // 从 provider 读取开关状态，确保 UI 与后端同步
    final webSearch = ref.watch(webSearchEnabledProvider);
    final deepThink = ref.watch(deepThinkingEnabledProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.componentColor('input', 'bg') ??
            theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: context.componentColor('input', 'border') ??
                theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 工具栏 ──
            Row(
              children: [
                // 工作区按钮
                _ToolbarButton(
                  icon: Icons.folder_outlined,
                  label: '工作区',
                  active: false,
                  onTap: widget.onWorkspace,
                ),
                const SizedBox(width: 4),
                // 联网搜索 — 直接读写 provider，同步 registry enable/disable
                _ToolbarButton(
                  icon: Icons.language,
                  label: '联网',
                  active: webSearch,
                  onTap: () => ref.read(webSearchEnabledProvider.notifier).state = !webSearch,
                ),
                const SizedBox(width: 4),
                // 深度思考 — 直接读写 provider，同步 reasoning_effort
                _ToolbarButton(
                  icon: Icons.psychology_outlined,
                  label: '深度思考',
                  active: deepThink,
                  onTap: () => ref.read(deepThinkingEnabledProvider.notifier).state = !deepThink,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // ── 输入行 ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 附件按钮
                if (hasAttach)
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: '添加附件',
                    onPressed: widget.onAttach,
                    style: IconButton.styleFrom(foregroundColor: fgColor),
                  ),

                // 文本输入
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: _multiline ? 5 : 1,
                    minLines: 1,
                    maxLength: maxLength,
                    decoration: InputDecoration(
                      hintText: placeholder,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      isDense: true,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),

                const SizedBox(width: 8),

                // 发送按钮
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: '发送',
                  onPressed: _send,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════ _ToolbarButton ═══════

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: active
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

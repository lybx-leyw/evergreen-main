/// 聊天输入栏——根据 [InputOptions] + [ChatOptions] 渲染输入区域。
///
/// 公开类：[ChatInputBar]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart' show webSearchEnabledProvider, reasoningEffortProvider, validReasoningEfforts;
import 'package:evergreen_base/providers.dart' show agentProviderProvider;

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
    final effort = ref.watch(reasoningEffortProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
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
                _EffortButton(
                  effort: effort,
                  onChanged: (v) {
                    ref.read(reasoningEffortProvider.notifier).state = v;
                    // A5 断链①接线：运行期同步主 provider（app_bootstrap 注入的
                    // agentProviderProvider，类型即 DeepSeekProvider），使档位
                    // 真实作用于请求参数。
                    final p = ref.read(agentProviderProvider);
                    if (v == 'off') {
                      p.setThinking('disabled');
                      p.setReasoningEffort('off');
                    } else {
                      p.setThinking('enabled');
                      p.setReasoningEffort(v);
                    }
                  },
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

/// 深度思考档位按钮—— chat_input_bar 用。
class _EffortButton extends StatelessWidget {
  final String effort;
  final ValueChanged<String> onChanged;

  const _EffortButton({required this.effort, required this.onChanged});

  static const _labels = <String, String>{
    'off': '深度思考: 关',
    'low': '深度思考: 低',
    'medium': '深度思考: 中',
    'high': '深度思考: 高',
    'max': '深度思考: 最强',
  };
  static const _levelColor = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    final isOn = effort != 'off';
    return _ToolbarButton(
      icon: Icons.psychology_outlined,
      label: _labels[effort] ?? '深度思考',
      active: isOn,
      onTap: () => _showMenu(context),
    );
  }

  void _showMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 4,
        offset.dx + renderBox.size.width, offset.dy + renderBox.size.height + 4,
      ),
      items: validReasoningEfforts.map((level) => PopupMenuItem<String>(
        value: level,
        child: Text(
          _labels[level] ?? level,
          style: TextStyle(
            fontWeight: level == effort ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      )).toList(),
    ).then((selected) {
      if (selected != null) onChanged(selected);
    });
  }
}

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

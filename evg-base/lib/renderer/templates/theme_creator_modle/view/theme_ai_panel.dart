/// 主题创作 AI 面板 —— 显式历史面板 + 绑定态徽标 + 断点续做。
///
/// 参考 html-creator `AiPanel`：输入框 + 发送；消息列表（用户/AI/错误）；
/// 取消/重置；顶部绑定态徽标（当前实例名 · 实例 ID · 消息数 · 断点续作）。
///
/// 历史一致性（关键约定）：面板**不持有自己的消息副本**，直接渲染
/// [ThemeAiService.uiMessages]。切换面板时服务层先清空旧消息、再恢复新实例
/// 历史（[ThemeAiService.switchPanel]），因此本面板天然「先清空再恢复」，
/// 绝不出现历史混杂。
library;

import 'package:flutter/material.dart';

import '../services/theme_ai_service.dart';

/// 主题创作 AI 面板。
class ThemeAiPanel extends StatefulWidget {
  final ThemeAiService aiService;

  /// 当前实例名（绑定态 UI：AI 会话归属哪个实例）。
  final String? instanceName;

  /// 当前实例 ID（只读展示；实例 ID == 主题 ID）。
  final String? instanceId;

  /// 外部聚焦输入框（工具栏「AI 助手」按钮用）。
  final FocusNode? focusNode;

  const ThemeAiPanel({
    super.key,
    required this.aiService,
    this.instanceName,
    this.instanceId,
    this.focusNode,
  });

  @override
  State<ThemeAiPanel> createState() => _ThemeAiPanelState();
}

class _ThemeAiPanelState extends State<ThemeAiPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty || widget.aiService.busy) return;
    _inputController.clear();
    // 服务层负责：追加历史 → 生成 → 更新 uiMessages + 落盘会话。
    widget.aiService.generate(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.aiService,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            children: [
              _buildHeader(theme),
              Expanded(child: _buildMessages(theme)),
              _buildInput(theme),
            ],
          ),
        );
      },
    );
  }

  // ═══════ 头部（状态 + 绑定态徽标） ═══════

  Widget _buildHeader(ThemeData theme) {
    final status = widget.aiService.status;
    final (icon, label) = switch (status) {
      ThemeAiStatus.thinking => (Icons.psychology, 'AI 思考中...'),
      ThemeAiStatus.error => (Icons.error, 'AI 出错'),
      ThemeAiStatus.done => (Icons.auto_awesome, 'AI 助手'),
      ThemeAiStatus.idle => (Icons.auto_awesome, 'AI 助手'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: status == ThemeAiStatus.thinking
                  ? Colors.deepPurple
                  : null),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 8),
          _buildBindingBadge(theme),
          const Spacer(),
          if (widget.aiService.busy)
            TextButton(
                onPressed: () => widget.aiService.cancel(),
                child: const Text('取消', style: TextStyle(fontSize: 11))),
          TextButton(
            onPressed: () {
              widget.aiService.reset();
            },
            child: const Text('重置', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// 当前实例绑定态徽标：实例名 · 实例 id（只读）· N 条消息 · 断点续作。
  Widget _buildBindingBadge(ThemeData theme) {
    final name = widget.instanceName;
    final iid = widget.instanceId;
    final count = widget.aiService.sessionMessageCount;
    final resumed = widget.aiService.restoredFromSession;
    final chips = <Widget>[];
    if (name != null && name.isNotEmpty) {
      chips.add(_badgeChip(theme, Icons.palette_outlined, name,
          tooltip: 'AI 会话绑定实例（名字可改）'));
    }
    if (iid != null && iid.isNotEmpty) {
      final short = iid.length > 14 ? '…${iid.substring(iid.length - 10)}' : iid;
      chips.add(_badgeChip(theme, Icons.tag, '#$short',
          tooltip: '实例 ID（=主题 ID）: $iid'));
    }
    if (resumed) {
      chips.add(_badgeChip(theme, Icons.history, '$count 条 · 续作',
          tooltip: '已恢复该实例历史会话，AI 将断点续作'));
    } else if (count > 0) {
      chips.add(_badgeChip(theme, Icons.forum_outlined, '$count 条',
          tooltip: '当前实例会话消息数'));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          chips[i],
        ],
      ],
    );
  }

  Widget _badgeChip(ThemeData theme, IconData icon, String text,
      {required String tooltip}) {
    final resumed = text.contains('续作');
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: resumed
              ? Colors.amber.withValues(alpha: 0.18)
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 11,
                color: resumed ? Colors.amber.shade800 : theme.colorScheme.primary),
            const SizedBox(width: 3),
            Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: resumed
                    ? Colors.amber.shade900
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════ 消息列表 ═══════

  Widget _buildMessages(ThemeData theme) {
    final msgs = widget.aiService.uiMessages;
    if (msgs.isEmpty) {
      return Center(
        child: Text(
          '告诉 AI 你想要的主题，例如：\n「温暖的学习书房，柔和的暖黄灯光」',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: msgs.length,
      itemBuilder: (ctx, i) => _buildBubble(theme, msgs[i]),
    );
  }

  Widget _buildBubble(ThemeData theme, Map<String, dynamic> m) {
    final role = m['role'] as String? ?? 'ai';
    final text = m['text'] as String? ?? '';
    final isUser = role == 'user';
    final isError = role == 'error';

    if (isError) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text.isEmpty ? '...' : text,
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }

  // ═══════ 输入区 ═══════

  Widget _buildInput(ThemeData theme) {
    final busy = widget.aiService.busy;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI 正在生成主题，请稍候...',
                      style: TextStyle(fontSize: 11, color: Colors.deepPurple),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.aiService.cancel(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: widget.focusNode,
                  enabled: !busy,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: busy
                        ? 'AI 正在生成中，请等待当前任务完成...'
                        : '描述你的主题... (如: 温暖的暖黄灯光书房)',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                    filled: busy,
                    fillColor: busy ? Colors.grey.shade100 : null,
                  ),
                  onSubmitted: (_) {
                    if (!busy) _send();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: busy ? null : _send,
                color: busy ? Colors.grey : theme.colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

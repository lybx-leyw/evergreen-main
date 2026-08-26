/// 会话选择栏——嵌入 ai-assistant 组件内部顶部。
///
/// 当 manifest.json 中 `multi_session: true` 时，ChatView 顶部显示此栏。
/// 用户可以新建/切换/删除/重命名会话，不影响侧边栏结构。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/session_manager.dart';

/// 会话选择栏——显示在 ChatView 顶部，替代侧边栏中的会话列表。
///
/// 用法：
/// ```dart
/// if (descriptor.chat?.multiSession == true)
///   SessionListBar(),
/// ```
class SessionListBar extends ConsumerWidget {
  const SessionListBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final theme = Theme.of(context);

    return sessionsAsync.when(
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              // 会话下拉选择器
              Expanded(
                child: _SessionDropdown(
                  sessions: sessions,
                  activeId: activeId,
                  onCreate: () => ref.read(createSessionProvider)(null),
                  onSwitch: (id) => ref.read(switchSessionProvider)(id),
                  onRename: (id, title) => ref.read(renameSessionProvider)(id, title),
                  onDelete: (id) => _confirmDelete(context, ref, id, sessions),
                ),
              ),
              // 新建按钮
              _MiniButton(
                icon: Icons.add,
                tooltip: '新建会话',
                onTap: () => ref.read(createSessionProvider)(null),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String id, List<agent.Session> sessions) {
    final session = sessions.where((s) => s.id == id).firstOrNull;
    final title = session?.title ?? '新对话';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除「$title」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(deleteSessionProvider)(id);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 会话下拉选择器——点击展开 PopupMenu。
class _SessionDropdown extends StatelessWidget {
  final List<agent.Session> sessions;
  final String? activeId;
  final VoidCallback onCreate;
  final void Function(String id) onSwitch;
  final void Function(String id, String title) onRename;
  final void Function(String id) onDelete;

  const _SessionDropdown({
    required this.sessions,
    required this.activeId,
    required this.onCreate,
    required this.onSwitch,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final active = sessions.where((s) => s.id == activeId).firstOrNull;
    final title = active?.title ?? '新对话';
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      offset: const Offset(0, 42),
      color: theme.colorScheme.surfaceContainerHigh,
      onSelected: (value) {
        if (value == '__create__') {
          onCreate();
        } else {
          onSwitch(value);
        }
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[
          // 标题行
          PopupMenuItem<String>(
            enabled: false,
            child: Row(
              children: [
                Text('会话列表', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                _PopupMiniButton(
                  icon: Icons.add,
                  tooltip: '新建',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onCreate();
                  },
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ];

        if (sessions.isEmpty) {
          items.add(PopupMenuItem<String>(
            enabled: false,
            child: Text('暂无会话',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant)),
          ));
        } else {
          for (final s in sessions) {
            final isActive = s.id == activeId;
            final msgCount = s.messages
                .where((m) => m.role == agent.Role.user || m.role == agent.Role.assistant)
                .length;
            items.add(PopupMenuItem<String>(
              value: s.id,
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    size: 16,
                    color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.title.isEmpty ? '新对话' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal),
                        ),
                        Text('$msgCount 条消息', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  // 重命名
                  _PopupMiniButton(
                    icon: Icons.edit,
                    tooltip: '重命名',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showRenameDialog(context, s);
                    },
                  ),
                  // 删除
                  _PopupMiniButton(
                    icon: Icons.delete_outline,
                    tooltip: '删除',
                    color: theme.colorScheme.error,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onDelete(s.id);
                    },
                  ),
                ],
              ),
            ));
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        height: 40,
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, agent.Session session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty) onRename(session.id, t);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 迷你图标按钮。
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// PopupMenu 内的迷你按钮。
class _PopupMiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _PopupMiniButton({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

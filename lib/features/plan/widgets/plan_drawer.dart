/// 计划抽屉 — 参照 _SessionDrawer，管理多个计划。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/plan_provider.dart';
import '../models/plan.dart';

class PlanDrawer extends ConsumerWidget {
  const PlanDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planListProvider);
    final activeId = ref.watch(activePlanIdProvider);

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              children: [
                Expanded(
                  child: Text('计划列表',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_comment),
                  tooltip: '新建计划',
                  onPressed: () => _showCreateDialog(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: plansAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (plans) {
                if (plans.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('暂无计划',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => _showCreateDialog(context, ref),
                          child: const Text('创建第一个计划'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: plans.length,
                  itemBuilder: (_, i) {
                    final p = plans[i];
                    final isActive = p.id == activeId;
                    return ListTile(
                      selected: isActive,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.4),
                      leading: Icon(isActive ? Icons.assignment_turned_in : Icons.assignment,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : null),
                      title: Text(p.name.isEmpty ? '未命名计划' : p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: isActive ? FontWeight.w600 : null)),
                      subtitle: Text(
                        '${p.outline.length} 项任务 · ${_formatDate(p.updatedAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        if (!isActive) {
                          ref.read(switchPlanProvider)(p.id);
                        }
                        Navigator.of(context).pop();
                      },
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onSelected: (action) {
                          if (action == 'rename') {
                            _showRenameDialog(context, ref, p);
                          } else if (action == 'delete') {
                            ref.read(deletePlanProvider)(p.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: Text('重命名')),
                          const PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    String? copyFromId;
    final plans = ref.read(planListProvider).valueOrNull ?? [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建计划'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '计划名称',
                  hintText: '例如：期末复习计划',
                  border: OutlineInputBorder(),
                ),
              ),
              if (plans.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: copyFromId,
                  decoration: const InputDecoration(
                    labelText: '从旧计划复制(可选)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不复制，创建空计划')),
                    for (final p in plans)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setDialogState(() => copyFromId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                ref.read(createPlanProvider)(nameCtrl.text.trim(), copyFromId: copyFromId);
                Navigator.pop(ctx);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Plan plan) {
    final ctrl = TextEditingController(text: plan.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名计划'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) ref.read(renamePlanProvider)(plan.id, t);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }
}

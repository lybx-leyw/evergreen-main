/// 树形视图槽位——从 [ComponentDescriptor.config] 读取 root 递归渲染。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 树形视图——`tree` 组件。
class TreeSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const TreeSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final root = cfg['root'] as Map<String, dynamic>?;
    final title = cfg['title'] as String? ?? '树形视图';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600)),
        ),
        if (root == null)
          Expanded(child: _emptyState(context))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [_TreeBranch(node: root, depth: 0)],
            ),
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置树结构 (config.root)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 递归树节点。
class _TreeBranch extends StatelessWidget {
  final Map<String, dynamic> node;
  final int depth;

  const _TreeBranch({required this.node, this.depth = 0});

  @override
  Widget build(BuildContext context) {
    final label = node['label'] as String? ?? '';
    final iconName = node['icon'] as String?;
    final children = (node['children'] as List<dynamic>?) ?? [];
    final expanded = node['expanded'] as bool? ?? true;
    final theme = Theme.of(context);

    final leadingIcon = iconName != null
        ? Text(iconName, style: const TextStyle(fontSize: 16))
        : Icon(
            children.isNotEmpty ? Icons.folder : Icons.description,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          );

    final indent = Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: const SizedBox.shrink(),
    );

    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            indent,
            leadingIcon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        tilePadding: EdgeInsets.zero,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [indent, leadingIcon],
        ),
        title: Text(label, style: theme.textTheme.bodyMedium),
        children: children.whereType<Map<String, dynamic>>().map((c) {
          return _TreeBranch(node: c, depth: depth + 1);
        }).toList(),
      ),
    );
  }
}

/// 左栏草稿列表——列出工作区全部主题草稿，支持选择与删除。
library;

import 'package:flutter/material.dart';

import '../models/theme_draft.dart';

/// 主题草稿列表。
class ThemeDraftList extends StatelessWidget {
  final List<ThemeDraft> drafts;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  const ThemeDraftList({
    super.key,
    required this.drafts,
    required this.selectedId,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (drafts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('暂无草稿\n点击顶部「新建」开始',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: drafts.length,
      itemBuilder: (ctx, i) {
        final d = drafts[i];
        final selected = d.id == selectedId;
        return Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(d.id),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // 主题色条（5 色预览）
                  _ColorBar(colors: d.colors),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600)),
                        Text(d.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: '删除草稿',
                    onPressed: () => onDelete(d.id),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 主题色条——横向堆叠展示草稿的关键色。
class _ColorBar extends StatelessWidget {
  final Map<String, String> colors;

  const _ColorBar({required this.colors});

  @override
  Widget build(BuildContext context) {
    const keys = ['background', 'surface', 'accent', 'text', 'error'];
    return Container(
      width: 36,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (final k in keys)
            Expanded(
              child: Container(
                color: _hex(colors[k]),
              ),
            ),
        ],
      ),
    );
  }

  Color? _hex(String? v) {
    if (v == null || v.isEmpty) return Colors.transparent;
    return Color(int.tryParse(v.replaceFirst('#', 'FF'), radix: 16) ?? 0);
  }
}

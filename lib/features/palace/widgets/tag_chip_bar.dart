/// Palace 标签 Chip 栏 —— 展示/选择/添加标签。
library;

import 'package:flutter/material.dart';

/// 标签 Chip 展示栏。
class TagChipBar extends StatelessWidget {
  final List<String> tags;
  final String? selectedTag;
  final bool showAdd;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onRemove;

  const TagChipBar({
    super.key,
    required this.tags,
    this.selectedTag,
    this.showAdd = false,
    this.onSelected,
    this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          if (onRemove != null)
            InputChip(
              label: Text(tag),
              selected: tag == selectedTag,
              onSelected: (_) => onSelected?.call(tag),
              onDeleted: () => onRemove!(tag),
            )
          else
            FilterChip(
              label: Text(tag),
              selected: tag == selectedTag,
              onSelected: (_) => onSelected?.call(tag),
            ),
        if (showAdd)
          ActionChip(
            label: const Icon(Icons.add, size: 16),
            onPressed: onAdd!,
          ),
      ],
    );
  }
}

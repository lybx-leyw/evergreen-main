/// 页面排序栏 —— 页面缩略图列表 + 增删操作。
///
/// P2 实现：水平滚动的页面缩略图，支持选中/新增/删除。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_page.dart';

/// 页面操作回调。
typedef PageSelectedCallback = void Function(int index);
typedef PageAddedCallback = void Function();
typedef PageDeletedCallback = void Function(int index);
typedef PageReorderedCallback = void Function(int oldIndex, int newIndex);

/// 页面排序栏 —— 顶部工具栏下方的 Page Tab 条。
class PageSorter extends StatelessWidget {
  final List<DesignPage> pages;
  final int selectedIndex;
  final PageSelectedCallback? onPageSelected;
  final PageAddedCallback? onPageAdded;
  final PageDeletedCallback? onPageDeleted;
  final PageReorderedCallback? onPageReordered;

  const PageSorter({
    super.key,
    required this.pages,
    this.selectedIndex = 0,
    this.onPageSelected,
    this.onPageAdded,
    this.onPageDeleted,
    this.onPageReordered,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onReorder: onPageReordered ?? (_, __) {},
              children: [
                for (var i = 0; i < pages.length; i++)
                  _buildPageTab(context, pages[i], i, key: ValueKey(pages[i].id)),
              ],
            ),
          ),
          // 新增页面按钮
          _ToolIcon(
            icon: Icons.add,
            tooltip: '新增页面',
            onTap: onPageAdded,
          ),
          // 删除页面按钮（至少保留 1 页）
          if (pages.length > 1)
            _ToolIcon(
              icon: Icons.delete_outline,
              tooltip: '删除当前页',
              onTap: onPageDeleted != null ? () => onPageDeleted!(selectedIndex) : null,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildPageTab(BuildContext context, DesignPage page, int index,
      {required Key key}) {
    final isSelected = index == selectedIndex;
    return GestureDetector(
      key: key,
      onTap: () => onPageSelected?.call(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽手柄
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_indicator,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              _layoutIcon(page.layoutPreset),
              size: 14,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              page.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${page.slots.length}S',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  IconData _layoutIcon(DesignPageLayout preset) {
    return switch (preset) {
      DesignPageLayout.fullscreen => Icons.crop_square,
      DesignPageLayout.grid => Icons.grid_view,
      DesignPageLayout.dock => Icons.dock,
      DesignPageLayout.flex => Icons.view_column,
      DesignPageLayout.absolute => Icons.move_down,
    };
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ToolIcon({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: onTap != null ? Colors.grey.shade600 : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
}

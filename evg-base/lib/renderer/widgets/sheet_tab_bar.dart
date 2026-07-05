/// Sheet 标签栏——多 Sheet 切换。
///
/// 公开类：[SheetTabBar]
import 'package:flutter/material.dart';

/// 多 Sheet 标签栏。
///
/// 显示 sheet 名称列表，点击切换活跃 sheet。
class SheetTabBar extends StatelessWidget {
  final List<String> sheets;
  final int activeIndex;
  final ValueChanged<int>? onSheetChanged;

  const SheetTabBar({
    super.key,
    required this.sheets,
    this.activeIndex = 0,
    this.onSheetChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          ListView.builder(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            itemCount: sheets.length,
            itemBuilder: (context, index) {
              final isActive = index == activeIndex;
              return InkWell(
                onTap: () => onSheetChanged?.call(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    sheets[index],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
          // 新增 Sheet 按钮
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: '新建 Sheet',
            onPressed: () {
              // TODO: 新建 Sheet
            },
          ),
        ],
      ),
    );
  }
}

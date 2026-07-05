/// 可排序列头——点击切换升序/降序。
import 'package:flutter/material.dart';

/// 排序方向。
enum SortDirection { asc, desc, none }

/// 排序状态。
class SortState {
  final String? field;
  final SortDirection direction;

  const SortState({this.field, this.direction = SortDirection.none});

  SortState toggle(String field) {
    if (this.field != field) return SortState(field: field, direction: SortDirection.asc);
    return switch (direction) {
      SortDirection.asc => SortState(field: field, direction: SortDirection.desc),
      SortDirection.desc => SortState(field: null, direction: SortDirection.none),
      SortDirection.none => SortState(field: field, direction: SortDirection.asc),
    };
  }
}

/// 可排序列头——读取 [ActionDescriptor.sortable] 列表。
///
/// 点击列头循环切换：无排序 → 升序 ↑ → 降序 ↓ → 无排序。
class SortHeader extends StatelessWidget {
  final List<String> columns;
  final SortState sortState;
  final ValueChanged<SortState> onSortChanged;

  const SortHeader({
    super.key,
    required this.columns,
    required this.sortState,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: columns.map((col) {
        final isActive = sortState.field == col;
        final icon = isActive
            ? (sortState.direction == SortDirection.asc
                ? Icons.arrow_upward
                : Icons.arrow_downward)
            : Icons.unfold_more;

        return Expanded(
          child: InkWell(
            onTap: () => onSortChanged(sortState.toggle(col)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    col,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(icon, size: 16),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

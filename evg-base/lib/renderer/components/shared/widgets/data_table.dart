/// 数据表格渲染——根据 [DataBindingDescriptor(display=table)] 渲染表格。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/app/service/theme/theme_provider.dart';
import 'sort_header.dart';
import 'empty_state.dart';

/// 数据表视图。
///
/// 读取 [ActionDescriptor.sortable] 列头支持排序。
/// 数据列为 [columns]，数据行为 [rows]（每行 Map）。
class EvergreenDataTable extends StatelessWidget {
  final DataBindingDescriptor binding;
  final ActionDescriptor? actions;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  const EvergreenDataTable({
    super.key,
    required this.binding,
    this.actions,
    this.columns = const [],
    this.rows = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.table_chart_outlined,
        title: '暂无数据',
      );
    }

    final sortableCols = actions?.sortable ?? <String>[];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(context),
          DataTableWidget(
            columns: columns,
            sortable: sortableCols,
            rows: rows,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    if (!binding.filter) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.filter_list,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '筛选',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// 内部表格组件——支持排序。
class DataTableWidget extends StatefulWidget {
  final List<String> columns;
  final List<String> sortable;
  final List<Map<String, dynamic>> rows;

  const DataTableWidget({
    super.key,
    required this.columns,
    required this.sortable,
    required this.rows,
  });

  @override
  State<DataTableWidget> createState() => _DataTableWidgetState();
}

class _DataTableWidgetState extends State<DataTableWidget> {
  SortState _sortState = const SortState();

  List<Map<String, dynamic>> get _sortedRows {
    if (_sortState.field == null || _sortState.direction == SortDirection.none) {
      return widget.rows;
    }
    final sorted = List<Map<String, dynamic>>.from(widget.rows);
    sorted.sort((a, b) {
      final va = a[_sortState.field]?.toString() ?? '';
      final vb = b[_sortState.field]?.toString() ?? '';
      return _sortState.direction == SortDirection.asc
          ? va.compareTo(vb)
          : vb.compareTo(va);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final sortable = widget.sortable;
    final rows = _sortedRows;

    return Column(
      children: [
        if (sortable.isNotEmpty)
          SortHeader(
            columns: widget.columns.where((c) => sortable.contains(c)).toList(),
            sortState: _sortState,
            onSortChanged: (s) => setState(() => _sortState = s),
          ),
        SingleChildScrollView(
          child: Table(
            border: TableBorder.all(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
            columnWidths: {
              for (var i = 0; i < widget.columns.length; i++)
                i: const FlexColumnWidth(),
            },
            children: [
              // 表头
              TableRow(
                decoration: BoxDecoration(
                  color: context.componentColor('table', 'header') ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                children: widget.columns
                    .map((c) => Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            c,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ))
                    .toList(),
              ),
              // 数据行
              for (final row in rows)
                TableRow(
                  children: widget.columns
                      .map((c) => Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              '${row[c] ?? ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ))
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

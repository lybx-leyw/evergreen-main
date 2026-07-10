/// DataTable 槽位——基于分层 editable/ 架构的可编辑数据表格。
///
/// 替代原先的只读 Flutter [DataTable] 实现，
/// 现在使用 [EditableTableData] + [TableEditController] + [EditableTable]。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../document/editable/editable.dart';

/// DataTable 组件——从 [ComponentDescriptor.config] 读取数据渲染可编辑表格。
///
/// 使用 StatefulWidget 持有独立的 [TableEditController]，
/// 支持单元格内联编辑、斑马纹、新建行等操作。
class DataTableSlot extends StatefulWidget {
  final ComponentDescriptor config;

  const DataTableSlot({super.key, required this.config});

  @override
  State<DataTableSlot> createState() => _DataTableSlotState();
}

class _DataTableSlotState extends State<DataTableSlot> {
  late final TableEditController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    final cfg = widget.config.config;
    final tableData = EditableTableData.fromJson(cfg);
    _controller = TableEditController(data: tableData);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.rows.isEmpty) {
      return _emptyState(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题（如果 config 中有 title）
        if ((widget.config.config['title'] as String?)?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              widget.config.config['title'] as String,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        // 可编辑表格
        Flexible(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: EditableTable(
                controller: _controller,
                zebraStripe: true,
                stripeColor1: Theme.of(context).colorScheme.surface,
                stripeColor2: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderColor: Theme.of(context).dividerColor,
                showCreateButton: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            '暂无表格数据',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

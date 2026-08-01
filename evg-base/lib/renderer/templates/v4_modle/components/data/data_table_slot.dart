/// DataTable 槽位——基于分层 editable/ 架构的可编辑数据表格。
///
/// 替代原先的只读 Flutter [DataTable] 实现，
/// 现在使用 [EditableTableData] + [TableEditController] + [EditableTable]。
///
/// M2 P2：改为 [DataSourceSlot] 消费方，支持 dataSource 注入 `rows`
/// （`List<Map>` → `config.rows`，或 `{rows:[...]}` Map）。内层 [_EditableTableView]
/// 独立持有 [TableEditController]，数据到达时在 [didUpdateWidget] 重建 controller。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/editable.dart';

/// DataTable 组件——从 [ComponentDescriptor.config] 读取数据渲染可编辑表格。
class DataTableSlot extends DataSourceSlot {
  const DataTableSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定
  @override
  DataMapping get dataMapping => const DataMapping(targetKey: 'rows');

  @override
  DataSourceSlotState<DataTableSlot> createState() => _DataTableSlotState();
}

class _DataTableSlotState extends DataSourceSlotState<DataTableSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    // 用合并后的 config 作为 key 的一部分，保证注入数据变化时内层重建 controller。
    return _EditableTableView(cfg: cfg);
  }
}

/// 内层视图——独立持有 [TableEditController]，支持单元格内联编辑、斑马纹、新建行。
class _EditableTableView extends StatefulWidget {
  final Map<String, dynamic> cfg;

  const _EditableTableView({required this.cfg});

  @override
  State<_EditableTableView> createState() => _EditableTableViewState();
}

class _EditableTableViewState extends State<_EditableTableView> {
  late TableEditController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = _buildController(widget.cfg);
  }

  @override
  void didUpdateWidget(_EditableTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 注入数据到达 / config 变化时，重建 controller。
    if (!identical(oldWidget.cfg, widget.cfg)) {
      _controller.dispose();
      _controller = _buildController(widget.cfg);
    }
  }

  TableEditController _buildController(Map<String, dynamic> cfg) {
    final tableData = EditableTableData.fromJson(cfg);
    return TableEditController(data: tableData);
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

    final title = widget.cfg['title'] as String?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题（如果 config 中有 title）
        if (title?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              title!,
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



/// Spreadsheet 视图——基于分层 editable/ 架构的自由编辑电子表格。
///
/// 替代原先直接依赖 [package:editable/editable.dart] 三方库的实现，
/// 现在使用项目内部 [EditableTableData] + [TableEditController] + [EditableTable]。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../document/editable/editable.dart';

/// 电子表格范式完整视图。
///
/// 使用分层架构的 [EditableTable] 替代三方 editable 包，
/// 支持自由编辑单元格、增删行、保存/恢复操作。
class SpreadsheetView extends StatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor? component;

  const SpreadsheetView({super.key, required this.descriptor, this.component});

  @override
  State<SpreadsheetView> createState() => _SpreadsheetViewState();
}

class _SpreadsheetViewState extends State<SpreadsheetView> {
  late final TableEditController _controller;

  @override
  void initState() {
    super.initState();
    final raw = widget.component?.config['spreadsheet'];
    final EditableTableData tableData;
    if (raw is Map<String, dynamic>) {
      tableData = EditableTableData.fromJson(raw);
    } else {
      tableData = EditableTableData.empty(columnCount: 4, rowCount: 8);
    }
    _controller = TableEditController(data: tableData);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 工具栏：保存 / 添加行
        _buildToolbar(context),
        // 表格区域
        Expanded(
          child: EditableTable(
            controller: _controller,
            zebraStripe: true,
            stripeColor1: Theme.of(context).colorScheme.surface,
            stripeColor2: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderColor: Theme.of(context).dividerColor,
            showSaveButton: true,
            showDeleteButton: true,
            showCreateButton: true,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const Text('Spreadsheet',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: '添加行',
            onPressed: () => _controller.addRow(),
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 18),
            tooltip: '保存',
            onPressed: () {
              // 遍历所有已编辑行触发保存回调
              for (int i = 0; i < _controller.rowCount; i++) {
                if (_controller.hasRowEdits(i)) {
                  _controller.saveRow(i);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 外部可通过此方法设置数据（供测试/初始化使用）。
  void setData({
    EditableTableData? data,
  }) {
    if (data != null) {
      _controller.replaceData(data);
    }
  }
}

/// 可编辑表格主组件——分层架构的顶层 UI。
///
/// 用法：
/// ```dart
/// final controller = TableEditController(data: tableData);
/// EditableTable(controller: controller)
/// ```
///
/// 与原始 [editable] 包 `Editable` 的区别：
/// - 强类型模型（[EditableColumn] / [EditableTableData]）替代 Map<String, dynamic>
/// - [TableEditController] 集中管理状态与 CRUD 操作
/// - 分离 header cell / data cell 为独立 widget
/// - 支持行保存/删除、列添加/删除
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/controller/table_edit_controller.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/models/editable_column.dart';
import 'editable_header_cell.dart';
import 'editable_data_cell.dart';

/// 可编辑表格主组件。
class EditableTable extends StatelessWidget {
  final TableEditController controller;

  // ── 外观配置 ──

  /// 边框颜色。
  final Color borderColor;

  /// 边框宽度。
  final double borderWidth;

  /// 行高。
  final double rowHeight;

  /// 数据单元格样式。
  final TextStyle? cellStyle;

  /// 表头样式。
  final TextStyle? headerStyle;

  /// 表头内边距。
  final EdgeInsetsGeometry headerPadding;

  /// 数据单元格内边距。
  final EdgeInsetsGeometry cellPadding;

  /// 数据单元格最大行数。
  final int cellMaxLines;

  /// 是否显示斑马纹。
  final bool zebraStripe;

  /// 斑马纹颜色 1（偶数行）。
  final Color stripeColor1;

  /// 斑马纹颜色 2（奇数行）。
  final Color stripeColor2;

  /// 是否显示行保存按钮。
  final bool showSaveButton;

  /// 是否显示行删除按钮。
  final bool showDeleteButton;

  /// 是否显示新建行按钮。
  final bool showCreateButton;

  /// 是否显示列操作工具栏。
  final bool showColumnToolbar;

  /// 数据单元格对齐方式。
  final TextAlign cellAlignment;

  /// 单元格编辑提交回调。
  final ValueChanged<String>? onCellSubmitted;

  const EditableTable({
    super.key,
    required this.controller,
    this.borderColor = Colors.grey,
    this.borderWidth = 0.5,
    this.rowHeight = 48.0,
    this.cellStyle,
    this.headerStyle,
    this.headerPadding = const EdgeInsets.only(left: 8, top: 8, bottom: 8, right: 8),
    this.cellPadding = const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
    this.cellMaxLines = 1,
    this.zebraStripe = false,
    this.stripeColor1 = Colors.white,
    this.stripeColor2 = const Color(0x1F000000),
    this.showSaveButton = false,
    this.showDeleteButton = false,
    this.showCreateButton = false,
    this.showColumnToolbar = false,
    this.cellAlignment = TextAlign.start,
    this.onCellSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cols = controller.columns;
    final rows = controller.rows;

    if (cols.isEmpty) {
      return const SizedBox.shrink();
    }

    // 不使用 Flexible：垂直滚动由父级容器（Expanded + Scrollbar）处理
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showColumnToolbar) _buildColumnToolbar(context),
        _buildTable(context, cols, rows),
        if (showCreateButton) _buildCreateButton(context),
      ],
    );
  }

  /// 构建表格：表头 + 全部数据行（水平可滚动）。
  ///
  /// 不做垂直滚动——交给父级容器处理（Expanded + SingleChildScrollView/ListView）。
  Widget _buildTable(
      BuildContext context, List<EditableColumn> cols, List<Map<String, dynamic>> rows) {
    final hasActionCol = showSaveButton || showDeleteButton;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: cols.fold<double>(
                0,
                (sum, col) => sum + col.widthFactor * 600,
              ) +
              (hasActionCol ? 60 : 0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 表头行
            _buildHeaderRow(context, cols, hasActionCol),
            // 全部数据行（直接展开，不内部滚动）
            ...List.generate(rows.length,
                (i) => _buildDataRow(context, cols, rows, i, hasActionCol)),
          ],
        ),
      ),
    );
  }

  /// 构建表头行。
  Widget _buildHeaderRow(BuildContext context, List<EditableColumn> cols, bool hasActionCol) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: borderWidth),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(cols.length, (i) {
              final widthByFactor = cols[i].widthFactor *
                  MediaQuery.of(context).size.width *
                  0.8; // 80% 屏幕宽作为表格可用面积
              return SizedBox(
                width: widthByFactor.clamp(60.0, 400.0),
                child: EditableHeaderCell(
                  column: cols[i],
                  padding: headerPadding,
                  textStyle: headerStyle,
                ),
              );
            }),
            // 操作列占位
            if (hasActionCol)
              const SizedBox(width: 60, child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  /// 构建单行数据。
  Widget _buildDataRow(BuildContext context, List<EditableColumn> cols,
      List<Map<String, dynamic>> rows, int rowIndex, bool hasActionCol) {
    final bgColor = _rowBackground(rowIndex);

    return Container(
      height: rowHeight,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor, width: borderWidth),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(cols.length, (colIndex) {
              final widthByFactor = cols[colIndex].widthFactor *
                  MediaQuery.of(context).size.width *
                  0.8;
              return Container(
                width: widthByFactor.clamp(60.0, 400.0),
                decoration: BoxDecoration(
                  border: Border(
                    right: colIndex < cols.length - 1
                        ? BorderSide(color: borderColor, width: borderWidth)
                        : BorderSide.none,
                  ),
                ),
                child: EditableDataCell(
                  controller: controller,
                  row: rowIndex,
                  col: colIndex,
                  textStyle: cellStyle,
                  padding: cellPadding,
                  textAlign: cellAlignment,
                  maxLines: cellMaxLines,
                  onSubmitted: onCellSubmitted,
                ),
              );
            }),
            // 操作列（保存/删除按钮）
            if (hasActionCol) _buildActionCell(context, rowIndex),
          ],
        ),
      ),
    );
  }

  /// 行背景色（斑马纹）。
  Color? _rowBackground(int index) {
    if (!zebraStripe) return null;
    return index.isEven ? stripeColor1 : stripeColor2;
  }

  /// 操作列：保存 + 删除按钮。
  Widget _buildActionCell(BuildContext context, int rowIndex) {
    final hasEdits = controller.hasRowEdits(rowIndex);

    // Two IconButtons (48px each with default tap target) → need 96px
    final buttonCount = (showSaveButton ? 1 : 0) + (showDeleteButton ? 1 : 0);
    return SizedBox(
      width: buttonCount * 48.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSaveButton)
            IconButton(
              icon: Icon(
                Icons.save,
                size: 16,
                color: hasEdits
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: '保存行',
              onPressed: () => controller.saveRow(rowIndex),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          if (showDeleteButton)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Theme.of(context).colorScheme.error,
              ),
              visualDensity: VisualDensity.compact,
              tooltip: '删除行',
              onPressed: () => controller.removeRow(rowIndex),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  /// 列工具栏。
  Widget _buildColumnToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Text(
            '列操作',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 8),
          _toolButton(
            icon: Icons.add,
            tooltip: '添加列',
            onTap: () => controller.addColumn(title: '新列'),
          ),
          _toolButton(
            icon: Icons.delete_outline,
            tooltip: '删除最后一列',
            onTap: () {
              if (controller.columnCount > 1) {
                controller.removeColumn(controller.columnCount - 1);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 新建行按钮。
  Widget _buildCreateButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: InkWell(
        onTap: () => controller.addRow(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.add,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}

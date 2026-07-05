/// 电子表格单元格——按 [SpreadsheetOptions] 配置渲染。
///
/// 公开类：[SpreadsheetGrid]
import 'package:flutter/material.dart';

/// 单元格数据模型。
class CellData {
  final dynamic value;
  final String? formula;
  final String? format;

  const CellData({this.value, this.formula, this.format});
}

/// 电子表格网格组件。
///
/// 读取 [SpreadsheetOptions] 中的 columns/rows/resizableColumns/conditionalFormatting。
class SpreadsheetGrid extends StatelessWidget {
  final int columns;
  final int rows;
  final bool conditionalFormatting;
  final bool resizableColumns;

  const SpreadsheetGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.conditionalFormatting = false,
    this.resizableColumns = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            // 行号列
            const DataColumn(label: Text('#')),
            for (var c = 0; c < columns; c++) DataColumn(label: Text(String.fromCharCode(65 + c))),
          ],
          rows: List.generate(rows, (rowIdx) {
            return DataRow(
              cells: [
                DataCell(Text('${rowIdx + 1}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11))),
                for (var colIdx = 0; colIdx < columns; colIdx++)
                  DataCell(_buildCell(rowIdx, colIdx)),
              ],
            );
          }),
          border: TableBorder.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCell(int row, int col) {
    // TODO: 实际单元格内容来自数据绑定
    return const SizedBox(width: 100, height: 24, child: Text(''));
  }
}

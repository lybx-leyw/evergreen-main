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
/// 若提供 [columnDefs] 和 [rowData]，则按数据渲染；否则显示空行。
class SpreadsheetGrid extends StatelessWidget {
  final int columns;
  final int rows;
  final bool conditionalFormatting;
  final bool resizableColumns;
  /// 列定义：每项含 `key` 和 `label`（如 `{"key":"k","label":"指标"}`）。
  final List<Map<String, dynamic>>? columnDefs;
  /// 行数据：每项为 Map<key, value>。
  final List<Map<String, dynamic>>? rowData;

  const SpreadsheetGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.conditionalFormatting = false,
    this.resizableColumns = false,
    this.columnDefs,
    this.rowData,
  });

  @override
  Widget build(BuildContext context) {
    // 优先使用 columnDefs 渲染，否则回退到 A-Z 列名。
    final cols = columnDefs;
    final data = rowData;
    final colCount = cols?.length ?? columns;
    final rowCount = data?.length ?? rows;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            // 行号列
            const DataColumn(label: Text('#')),
            if (cols != null)
              for (final c in cols)
                DataColumn(label: Text(c['label'] as String? ?? c['key'] as String? ?? '?'))
            else
              for (var c = 0; c < colCount; c++) DataColumn(label: Text(String.fromCharCode(65 + c))),
          ],
          rows: List.generate(rowCount, (rowIdx) {
            return DataRow(
              cells: [
                DataCell(Text('${rowIdx + 1}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11))),
                for (var colIdx = 0; colIdx < colCount; colIdx++)
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
    final data = rowData;
    final cols = columnDefs;
    if (data != null && cols != null && row < data.length && col < cols.length) {
      final key = cols[col]['key'] as String? ?? '';
      final value = data[row][key]?.toString() ?? '';
      return SizedBox(
        width: 100,
        height: 24,
        child: Text(value, style: const TextStyle(fontSize: 13)),
      );
    }
    // 无数据时显示空占位
    return const SizedBox(width: 100, height: 24, child: Text(''));
  }
}

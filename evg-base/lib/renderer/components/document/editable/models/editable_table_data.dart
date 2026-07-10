/// 可编辑表格的完整数据快照模型。
///
/// 封装列定义 + 行数据 + 编辑追踪状态，作为 [TableEditController] 的状态载体。
library;

import 'editable_column.dart';

/// 单行编辑追踪——记录被修改的行和对应字段。
class CellEdit {
  final int rowIndex;
  final Map<String, dynamic> changes;

  const CellEdit({required this.rowIndex, required this.changes});

  @override
  String toString() => 'CellEdit(row: $rowIndex, changes: $changes)';
}

/// 表格完整数据状态。
class EditableTableData {
  final List<EditableColumn> columns;
  final List<Map<String, dynamic>> rows;

  /// 已编辑行（行索引 → 变更字段 Map）。
  final List<CellEdit> editedRows;

  const EditableTableData({
    required this.columns,
    required this.rows,
    this.editedRows = const [],
  });

  /// 空表格工厂。
  factory EditableTableData.empty({
    int columnCount = 4,
    int rowCount = 8,
  }) {
    final cols = List.generate(columnCount, (i) {
      final letter = String.fromCharCode(65 + i); // A, B, C, D...
      return EditableColumn(
        title: letter,
        key: letter,
        widthFactor: 0.15,
      );
    });
    final rows = List.generate(
        rowCount, (_) => <String, dynamic>{});
    return EditableTableData(columns: cols, rows: rows);
  }

  /// 从 JSON 解析（manifest config 格式）。
  factory EditableTableData.fromJson(Map<String, dynamic> json) {
    // 解析列
    final rawCols = json['columns'];
    final List<EditableColumn> columns;
    if (rawCols is List && rawCols.isNotEmpty) {
      columns = rawCols
          .whereType<Map<String, dynamic>>()
          .map(EditableColumn.fromJson)
          .toList();
    } else {
      columns = EditableTableData.empty(columnCount: 4, rowCount: 0).columns;
    }

    // 解析行
    final rawRows = json['rows'];
    final List<Map<String, dynamic>> rows;
    if (rawRows is List) {
      rows = rawRows.whereType<Map<String, dynamic>>().toList();
    } else {
      rows = [];
    }

    return EditableTableData(columns: columns, rows: rows);
  }

  /// 获取行数。
  int get rowCount => rows.length;

  /// 获取列数。
  int get columnCount => columns.length;

  /// 获取指定行列的值。
  String getCellValue(int row, String colKey) {
    if (row < 0 || row >= rows.length) return '';
    return (rows[row][colKey] ?? '').toString();
  }

  /// 拷贝并替换 columns。
  EditableTableData copyWithColumns(List<EditableColumn> newColumns) {
    return EditableTableData(
      columns: newColumns,
      rows: rows,
      editedRows: editedRows,
    );
  }

  /// 拷贝并替换 rows。
  EditableTableData copyWithRows(List<Map<String, dynamic>> newRows) {
    return EditableTableData(
      columns: columns,
      rows: newRows,
      editedRows: editedRows,
    );
  }

  /// 拷贝并替换 editedRows。
  EditableTableData copyWithEdits(List<CellEdit> newEdits) {
    return EditableTableData(
      columns: columns,
      rows: rows,
      editedRows: newEdits,
    );
  }

  @override
  String toString() =>
      'EditableTableData(cols: $columnCount, rows: $rowCount, edits: ${editedRows.length})';
}

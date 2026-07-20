/// 可编辑表格控制器——管理表格状态与 CRUD 操作。
///
/// 基于 [ChangeNotifier] 实现响应式更新，与 Flutter widget 解耦。
///
/// 使用方式：
/// ```dart
/// final controller = TableEditController(data: tableData);
/// // UI 层通过 ListenableBuilder / AnimatedBuilder 订阅
/// ListenableBuilder(
///   listenable: controller,
///   builder: (context, _) => EditableTable(controller: controller),
/// )
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/models/editable_column.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/models/editable_table_data.dart';

/// 行保存结果回调签名。
typedef RowSaveCallback = void Function(CellEdit edit);

/// 新行创建回调签名。
typedef RowCreateCallback = void Function(Map<String, dynamic> newRow);

class TableEditController extends ChangeNotifier {
  EditableTableData _data;

  /// 外部回调：行保存。
  RowSaveCallback? onRowSaved;

  /// 外部回调：创建新行。
  RowCreateCallback? onCreateRow;

  TableEditController({
    required EditableTableData data,
    this.onRowSaved,
    this.onCreateRow,
  }) : _data = data;

  // ── Getters ──

  EditableTableData get data => _data;
  List<EditableColumn> get columns => _data.columns;
  List<Map<String, dynamic>> get rows => _data.rows;
  int get rowCount => _data.rowCount;
  int get columnCount => _data.columnCount;

  /// 获取指定行列的值。
  String cellValue(int row, String colKey) => _data.getCellValue(row, colKey);

  /// 指定列是否可编辑。
  bool isColumnEditable(int colIndex) {
    if (colIndex < 0 || colIndex >= columns.length) return false;
    return columns[colIndex].isEditable;
  }

  /// 指定列的宽度比例。
  double columnWidthFactor(int colIndex) {
    if (colIndex < 0 || colIndex >= columns.length) return 0.15;
    return columns[colIndex].widthFactor;
  }

  // ── 行操作 ──

  /// 添加一行空数据。
  void addRow() {
    final newRow = <String, dynamic>{};
    for (final col in columns) {
      newRow[col.key] = '';
    }
    final newRows = List<Map<String, dynamic>>.from(rows)..add(newRow);
    _data = _data.copyWithRows(newRows);
    onCreateRow?.call(newRow);
    notifyListeners();
  }

  /// 删除指定行。
  void removeRow(int index) {
    if (index < 0 || index >= rows.length) return;
    final newRows = List<Map<String, dynamic>>.from(rows)..removeAt(index);
    // 移除对应的编辑记录
    final newEdits = _data.editedRows
        .where((e) => e.rowIndex != index)
        .toList();
    // 调整编辑记录的行索引
    for (final edit in newEdits) {
      if (edit.rowIndex > index) {
        // CellEdit is immutable - this won't work as is.
        // We need to handle this differently.
      }
    }
    // Actually, since CellEdit is immutable, we need to rebuild the list
    final adjustedEdits = <CellEdit>[];
    for (final edit in newEdits) {
      if (edit.rowIndex > index) {
        adjustedEdits.add(CellEdit(
          rowIndex: edit.rowIndex - 1,
          changes: edit.changes,
        ));
      } else {
        adjustedEdits.add(edit);
      }
    }
    _data = EditableTableData(
      columns: columns,
      rows: newRows,
      editedRows: adjustedEdits,
    );
    notifyListeners();
  }

  /// 保存指定行（触发 [onRowSaved] 回调）。
  void saveRow(int index) {
    final edit = _data.editedRows.cast<CellEdit?>().firstWhere(
          (e) => e?.rowIndex == index,
          orElse: () => null,
        );
    if (edit != null) {
      onRowSaved?.call(edit);
    } else {
      debugPrint('[TableEditController] 行 $index 无修改，跳过保存');
    }
  }

  // ── 单元格编辑 ──

  /// 修改指定单元格的值。
  void setCellValue(int row, String colKey, String value) {
    if (row < 0 || row >= rows.length) return;

    // 更新行数据
    final newRows = List<Map<String, dynamic>>.from(rows);
    newRows[row] = Map<String, dynamic>.from(newRows[row]);
    newRows[row][colKey] = value;

    // 更新编辑追踪
    final newEdits = List<CellEdit>.from(_data.editedRows);
    final existingIndex =
        newEdits.indexWhere((e) => e.rowIndex == row);
    if (existingIndex >= 0) {
      final oldChanges = Map<String, dynamic>.from(newEdits[existingIndex].changes);
      oldChanges[colKey] = value;
      newEdits[existingIndex] = CellEdit(rowIndex: row, changes: oldChanges);
    } else {
      newEdits.add(CellEdit(rowIndex: row, changes: {colKey: value}));
    }

    _data = EditableTableData(
      columns: columns,
      rows: newRows,
      editedRows: newEdits,
    );
    notifyListeners();
  }

  /// 检查指定行是否有编辑变更。
  bool hasRowEdits(int index) {
    return _data.editedRows.any((e) => e.rowIndex == index);
  }

  /// 获取指定行的编辑变更。
  CellEdit? getRowEdit(int index) {
    try {
      return _data.editedRows.firstWhere((e) => e.rowIndex == index);
    } catch (_) {
      return null;
    }
  }

  // ── 列操作 ──

  /// 添加一列（默认可编辑）。
  void addColumn({String title = '', String? key, double widthFactor = 0.15}) {
    final colKey = key ?? (title.isNotEmpty ? title : 'col_${columns.length}');
    final newCol = EditableColumn(
      title: title,
      key: colKey,
      widthFactor: widthFactor,
    );
    final newColumns = List<EditableColumn>.from(columns)..add(newCol);
    // 为所有现有行初始化新列的值
    final newRows = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r[colKey] = '';
      return r;
    }).toList();
    _data = EditableTableData(
      columns: newColumns,
      rows: newRows,
      editedRows: _data.editedRows,
    );
    notifyListeners();
  }

  /// 删除指定列。
  void removeColumn(int index) {
    if (index < 0 || index >= columns.length) return;
    final keyToRemove = columns[index].key;
    final newColumns = List<EditableColumn>.from(columns)..removeAt(index);
    // 从所有行中移除该列数据
    final newRows = rows.map((row) {
      final r = Map<String, dynamic>.from(row);
      r.remove(keyToRemove);
      return r;
    }).toList();
    _data = EditableTableData(
      columns: newColumns,
      rows: newRows,
      editedRows: _data.editedRows,
    );
    notifyListeners();
  }

  // ── 批量操作 ──

  /// 替换整个数据集。
  void replaceData(EditableTableData newData) {
    _data = newData;
    notifyListeners();
  }

  /// 重置编辑追踪（清除所有变更记录）。
  void clearEdits() {
    _data = _data.copyWithEdits([]);
    notifyListeners();
  }

  @override
  void dispose() {
    onRowSaved = null;
    onCreateRow = null;
    super.dispose();
  }
}

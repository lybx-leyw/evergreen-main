/// 可编辑表格——数据单元格组件。
///
/// 根据列的 [EditableColumn.isEditable] 决定渲染：
/// - 可编辑：带 [TextFormField] 的内联编辑
/// - 只读：纯 [Text] 显示
///
/// 设计模式：继承 original [editable] 包的 [RowBuilder] 概念，
/// 但使用强类型模型 + 控制器驱动。
library;

import 'package:flutter/material.dart';
import '../controller/table_edit_controller.dart';

/// 数据单元格——单行单列的交互单元。
class EditableDataCell extends StatefulWidget {
  final TableEditController controller;
  final int row;
  final int col;

  /// 单元格文本样式。
  final TextStyle? textStyle;

  /// 单元格内边距。
  final EdgeInsetsGeometry padding;

  /// 文本对齐方式。
  final TextAlign textAlign;

  /// 可编辑时的最大行数（默认 1，即不换行）。
  final int maxLines;

  /// 提交（回车）回调。
  final ValueChanged<String>? onSubmitted;

  const EditableDataCell({
    super.key,
    required this.controller,
    required this.row,
    required this.col,
    this.textStyle,
    this.padding = const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 12),
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.onSubmitted,
  });

  @override
  State<EditableDataCell> createState() => _EditableDataCellState();
}

class _EditableDataCellState extends State<EditableDataCell> {
  late TextEditingController _textController;
  String _lastColKey = '';
  String _lastValue = '';

  String get _colKey {
    final cols = widget.controller.columns;
    if (widget.col < 0 || widget.col >= cols.length) return '';
    return cols[widget.col].key;
  }

  bool get _isEditable => widget.controller.isColumnEditable(widget.col);

  @override
  void initState() {
    super.initState();
    _lastColKey = _colKey;
    _lastValue = widget.controller.cellValue(widget.row, _lastColKey);
    _textController = TextEditingController(text: _lastValue);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final currentKey = _colKey;
    final currentValue = widget.controller.cellValue(widget.row, currentKey);
    // 仅当外部数据变化时才同步到 TextEditingController
    if (currentKey != _lastColKey || currentValue != _lastValue) {
      _lastColKey = currentKey;
      _lastValue = currentValue;
      _textController.text = currentValue;
    }
  }

  void _handleChanged(String value) {
    _lastValue = value;
    widget.controller.setCellValue(widget.row, _colKey, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_colKey.isEmpty) return const SizedBox.shrink();

    if (!_isEditable) {
      // 只读渲染
      return Padding(
        padding: widget.padding,
        child: Align(
          alignment: _alignmentFromTextAlign(widget.textAlign),
          child: Text(
            widget.controller.cellValue(widget.row, _colKey),
            textAlign: widget.textAlign,
            style: widget.textStyle ?? const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    // 可编辑渲染：TextFormField 内联编辑
    return Padding(
      padding: EdgeInsets.zero,
      child: TextFormField(
        controller: _textController,
        textAlign: widget.textAlign,
        style: widget.textStyle,
        maxLines: widget.maxLines,
        onChanged: _handleChanged,
        onFieldSubmitted: widget.onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          contentPadding: widget.padding,
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }

  static Alignment _alignmentFromTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.justify:
        return Alignment.centerLeft;
    }
  }
}

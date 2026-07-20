/// 可编辑表格——表头单元格组件。
///
/// 显示列标题，支持自定义样式和对齐。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/editable/models/editable_column.dart';

/// 表头单元格——单列的标题头。
class EditableHeaderCell extends StatelessWidget {
  final EditableColumn column;

  /// 表头文字样式。
  final TextStyle? textStyle;

  /// 表头内边距。
  final EdgeInsetsGeometry padding;

  /// 表头字体粗细（若未提供 textStyle）。
  final FontWeight fontWeight;

  /// 表头字体大小（若未提供 textStyle）。
  final double fontSize;

  const EditableHeaderCell({
    super.key,
    required this.column,
    this.textStyle,
    this.padding = const EdgeInsets.only(left: 8, top: 8, bottom: 12, right: 8),
    this.fontWeight = FontWeight.w600,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: _alignmentFromTextAlign(
            column.headerAlignment),
        child: Text(
          column.title,
          textAlign: column.headerAlignment,
          style: textStyle ??
              Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: fontWeight,
                    fontSize: fontSize,
                  ) ??
              TextStyle(
                fontWeight: fontWeight,
                fontSize: fontSize,
              ),
          overflow: TextOverflow.ellipsis,
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

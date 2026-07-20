/// 可编辑表格列定义模型。
///
/// 替代 original [editable] 包中 `Map<String, dynamic>` 的裸字典方案，
/// 提供编译期类型安全。
import 'package:flutter/painting.dart';
class EditableColumn {
  /// 列头显示标题。
  final String title;

  /// 数据行中此列对应的 key（如 'name', 'date'）。
  final String key;

  /// 列宽比例（0.0 ~ 1.0），表示占父容器宽度的百分比。
  /// 默认 0.15。
  final double widthFactor;

  /// 此列是否允许内联编辑。
  /// 默认 true。
  final bool isEditable;

  /// 列头文本对齐方式。
  /// 默认 [TextAlign.start]。
  final TextAlign headerAlignment;

  const EditableColumn({
    required this.title,
    required this.key,
    this.widthFactor = 0.15,
    this.isEditable = true,
    this.headerAlignment = TextAlign.start,
  });

  /// 从 manifest 的 JSON 字典创建。
  ///
  /// 输入格式：
  /// ```json
  /// {"title": "Name", "key": "name", "widthFactor": 0.2, "editable": false}
  /// ```
  ///
  /// 容错：缺失字段使用默认值，不抛异常。
  factory EditableColumn.fromJson(Map<String, dynamic> json) {
    return EditableColumn(
      title: (json['title'] as String?) ?? (json['label'] as String?) ?? '',
      key: (json['key'] as String?) ?? '',
      widthFactor: (json['widthFactor'] as num?)?.toDouble() ?? 0.15,
      isEditable: (json['editable'] as bool?) ?? true,
    );
  }

  /// 转为 JSON（用于序列化/导出）。
  Map<String, dynamic> toJson() => {
        'title': title,
        'key': key,
        'widthFactor': widthFactor,
        'editable': isEditable,
      };

  @override
  String toString() =>
      'EditableColumn(title: $title, key: $key, widthFactor: $widthFactor, editable: $isEditable)';
}

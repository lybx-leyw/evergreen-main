/// 表单字段渲染器——根据 [FormFieldDescriptor] 动态渲染表单控件。
///
/// 公开类：[FormFieldRenderer]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 动态表单字段渲染。
///
/// 读取 [FormFieldDescriptor.type] 选择对应的输入控件：
/// - text → TextField
/// - textarea → 多行 TextField
/// - number → 数字输入
/// - select → 下拉选择
/// - bool_ → Switch
/// - date → 日期选择
class FormFieldRenderer extends StatelessWidget {
  final FormFieldDescriptor field;
  final dynamic initialValue;
  final ValueChanged<dynamic>? onChanged;

  const FormFieldRenderer({
    super.key,
    required this.field,
    this.initialValue,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      'bool_' || 'checkbox' || 'switch' => _buildBoolField(context),
      'select' || 'dropdown' => _buildSelectField(context),
      'date' => _buildDateField(context),
      'number' => _buildNumberField(context),
      'textarea' => _buildTextAreaField(context),
      _ => _buildTextField(context), // 'text' + 未知
    };
  }

  Widget _buildTextField(BuildContext context) {
    return TextFormField(
      initialValue: initialValue?.toString(),
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      validator: field.required
          ? (v) => (v == null || v.trim().isEmpty) ? '${field.label} 为必填' : null
          : null,
      onChanged: onChanged,
    );
  }

  Widget _buildTextAreaField(BuildContext context) {
    return TextFormField(
      initialValue: initialValue?.toString(),
      maxLines: 5,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        alignLabelWithHint: true,
      ),
      validator: field.required
          ? (v) => (v == null || v.trim().isEmpty) ? '${field.label} 为必填' : null
          : null,
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField(BuildContext context) {
    return TextFormField(
      initialValue: initialValue?.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.placeholder ?? '输入数字',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      validator: field.required
          ? (v) => (v == null || v.trim().isEmpty) ? '${field.label} 为必填' : null
          : null,
      onChanged: onChanged,
    );
  }

  Widget _buildBoolField(BuildContext context) {
    return SwitchListTile(
      title: Text(field.label),
      subtitle: field.placeholder != null ? Text(field.placeholder!) : null,
      value: initialValue == true,
      onChanged: (v) => onChanged?.call(v),
    );
  }

  Widget _buildSelectField(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: initialValue?.toString(),
      decoration: InputDecoration(
        labelText: field.label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: (field.options ?? <String>[])
          .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
          .toList(),
      onChanged: (v) => onChanged?.call(v),
      validator: field.required
          ? (v) => (v == null || v.isEmpty) ? '${field.label} 为必填' : null
          : null,
    );
  }

  Widget _buildDateField(BuildContext context) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (date != null) {
          onChanged?.call(date.toIso8601String().split('T').first);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: field.label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(initialValue?.toString() ?? '选择日期'),
      ),
    );
  }
}

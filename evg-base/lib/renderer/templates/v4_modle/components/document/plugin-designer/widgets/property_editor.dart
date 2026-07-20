/// 通用属性编辑器 —— 为 [PropertyPanel] 提供可复用的字段构建器。
///
/// 封装常用的表单字段类型：文本、数字、下拉、开关、颜色选择。
/// 避免在 [PropertyPanel] 和元数据编辑器中重复编写相同的 TextField 逻辑。
library;

import 'package:flutter/material.dart';

/// 单个可编辑属性字段描述。
class PropertyField {
  final String key;
  final String label;
  final String? value;
  final PropertyFieldType type;
  final List<String>? options; // 用于下拉选择
  final String? hint;
  final bool multiline;

  const PropertyField({
    required this.key,
    required this.label,
    this.value,
    this.type = PropertyFieldType.text,
    this.options,
    this.hint,
    this.multiline = false,
  });
}

/// 属性字段类型。
enum PropertyFieldType {
  text,
  number,
  dropdown,
  switchToggle,
  multiline,
}

/// 创建通用的属性编辑器表单。
///
/// [fields] 定义要编辑的字段列表，
/// [onChanged] 在每个字段值变化时回调。
class PropertyEditor extends StatefulWidget {
  final List<PropertyField> fields;
  final ValueChanged<Map<String, String>>? onChanged;

  const PropertyEditor({
    super.key,
    required this.fields,
    this.onChanged,
  });

  @override
  State<PropertyEditor> createState() => _PropertyEditorState();
}

class _PropertyEditorState extends State<PropertyEditor> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, bool> _switches = {};
  final Map<String, String> _dropdowns = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _ctrls[f.key] = TextEditingController(text: f.value ?? '');
      if (f.type == PropertyFieldType.switchToggle) {
        _switches[f.key] = f.value == 'true';
      }
      if (f.type == PropertyFieldType.dropdown && f.options != null) {
        _dropdowns[f.key] = f.value ?? f.options!.first;
      }
    }
  }

  @override
  void didUpdateWidget(covariant PropertyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在 fields 变化时重新初始化
    if (oldWidget.fields.length != widget.fields.length ||
        oldWidget.fields.any((of) {
          final nf = widget.fields
              .where((f) => f.key == of.key)
              .firstOrNull;
          return nf == null || nf.value != of.value;
        })) {
      _reload();
    }
  }

  void _reload() {
    for (final f in widget.fields) {
      if (_ctrls.containsKey(f.key)) {
        _ctrls[f.key]!.text = f.value ?? '';
      } else {
        _ctrls[f.key] = TextEditingController(text: f.value ?? '');
      }
      if (f.type == PropertyFieldType.switchToggle) {
        _switches[f.key] = f.value == 'true';
      }
      if (f.type == PropertyFieldType.dropdown && f.options != null) {
        _dropdowns[f.key] = f.value ?? f.options!.first;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final values = <String, String>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case PropertyFieldType.switchToggle:
          values[f.key] = (_switches[f.key] ?? false).toString();
          break;
        case PropertyFieldType.dropdown:
          values[f.key] = _dropdowns[f.key] ?? '';
          break;
        default:
          values[f.key] = _ctrls[f.key]?.text ?? '';
      }
    }
    widget.onChanged?.call(values);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.fields.map(_buildField).toList(),
    );
  }

  Widget _buildField(PropertyField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: switch (field.type) {
        PropertyFieldType.multiline => _buildMultiline(field),
        PropertyFieldType.switchToggle => _buildSwitch(field),
        PropertyFieldType.dropdown => _buildDropdown(field),
        _ => _buildText(field),
      },
    );
  }

  Widget _buildText(PropertyField field) {
    return TextField(
      controller: _ctrls[field.key],
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      keyboardType:
          field.type == PropertyFieldType.number ? TextInputType.number : null,
      onChanged: (_) => _emit(),
    );
  }

  Widget _buildMultiline(PropertyField field) {
    return TextField(
      controller: _ctrls[field.key],
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      maxLines: 3,
      minLines: 2,
      onChanged: (_) => _emit(),
    );
  }

  Widget _buildSwitch(PropertyField field) {
    return Row(
      children: [
        Text(field.label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Switch(
          value: _switches[field.key] ?? false,
          onChanged: (v) {
            setState(() => _switches[field.key] = v);
            _emit();
          },
        ),
      ],
    );
  }

  Widget _buildDropdown(PropertyField field) {
    return DropdownButtonFormField<String>(
      value: _dropdowns[field.key],
      decoration: InputDecoration(
        labelText: field.label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      style: const TextStyle(fontSize: 13),
      items: (field.options ?? [])
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => _dropdowns[field.key] = v);
          _emit();
        }
      },
    );
  }
}

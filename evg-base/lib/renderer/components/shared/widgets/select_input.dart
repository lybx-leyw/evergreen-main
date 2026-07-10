/// 选择输入——[InputOptions(mode=select)] 下拉/多选/标签选择。
///
/// 公开类：[SelectInput]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 选择模式输入组件。
///
/// 读取 [InputOptions.select] 配置选项列表和交互方式。
class SelectInput extends StatefulWidget {
  final InputOptions input;
  final ValueChanged<String>? onChanged;

  const SelectInput({
    super.key,
    required this.input,
    this.onChanged,
  });

  @override
  State<SelectInput> createState() => _SelectInputState();
}

class _SelectInputState extends State<SelectInput> {
  String? _selected;

  List<String> get _options => widget.input.options ?? [];

  @override
  Widget build(BuildContext context) {
    if (_options.isEmpty) {
      return const Center(child: Text('无选项'));
    }

    final multi = widget.input.select?.multi ?? false;

    if (multi) {
      return _buildChipSelect();
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: DropdownButtonFormField<String>(
        value: _selected,
        decoration: InputDecoration(
          labelText: widget.input.placeholder ?? '请选择',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        items: _options
            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
            .toList(),
        onChanged: (value) {
          setState(() => _selected = value);
          widget.onChanged?.call(value ?? '');
        },
      ),
    );
  }

  Widget _buildChipSelect() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: _options.map((opt) {
          final selected = _selected == opt;
          return FilterChip(
            label: Text(opt),
            selected: selected,
            onSelected: (v) {
              setState(() => _selected = v ? opt : null);
              widget.onChanged?.call(v ? opt : '');
            },
          );
        }).toList(),
      ),
    );
  }
}

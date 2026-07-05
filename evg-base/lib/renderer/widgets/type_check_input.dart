/// 打字检查输入——[InputOptions(mode=type-check)] 逐字比对输入。
///
/// 公开类：[TypeCheckInput]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 打字检查模式输入组件。
///
/// 读取 [InputOptions.typeCheck] 配置显示原文和用户输入比对。
class TypeCheckInput extends StatefulWidget {
  final InputOptions input;
  final ValueChanged<String>? onChanged;

  const TypeCheckInput({
    super.key,
    required this.input,
    this.onChanged,
  });

  @override
  State<TypeCheckInput> createState() => _TypeCheckInputState();
}

class _TypeCheckInputState extends State<TypeCheckInput> {
  final _controller = TextEditingController();
  String _matchStatus = '';

  String get _reference => widget.input.options?.firstOrNull ?? '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 参考文本
        if (_reference.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _reference,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
          ),

        // 用户输入区域
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _controller,
            maxLines: null,
            autofocus: widget.input.autoFocus,
            maxLength: widget.input.maxLength,
            decoration: InputDecoration(
              hintText: '对照输入...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              _checkMatch(value);
              widget.onChanged?.call(value);
            },
          ),
        ),

        // 匹配状态
        if (_matchStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _matchStatus,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }

  void _checkMatch(String input) {
    if (_reference.isEmpty) return;
    final ref = _reference.replaceAll(RegExp(r'\s+'), '');
    final inp = input.replaceAll(RegExp(r'\s+'), '');
    final correct = ref.characters
        .toList()
        .asMap()
        .entries
        .where((e) => e.key < inp.length && e.value == inp[e.key])
        .length;
    final total = ref.characters.length;
    setState(() {
      _matchStatus = '匹配: $correct / $total 字符';
    });
  }
}

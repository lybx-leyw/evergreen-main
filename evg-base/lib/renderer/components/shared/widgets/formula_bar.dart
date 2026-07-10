/// 公式栏——电子表格公式输入区。
///
/// 公开类：[FormulaBar]
import 'package:flutter/material.dart';

/// 公式输入栏。
///
/// 左侧显示当前单元格引用，右侧显示公式/值。
class FormulaBar extends StatefulWidget {
  final String? activeCell;
  final String? initialFormula;
  final ValueChanged<String>? onFormulaChanged;

  const FormulaBar({
    super.key,
    this.activeCell,
    this.initialFormula,
    this.onFormulaChanged,
  });

  @override
  State<FormulaBar> createState() => _FormulaBarState();
}

class _FormulaBarState extends State<FormulaBar> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialFormula ?? '');
  }

  @override
  void didUpdateWidget(covariant FormulaBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFormula != oldWidget.initialFormula) {
      _controller.text = widget.initialFormula ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // 单元格引用
          Container(
            width: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Text(
              widget.activeCell ?? 'A1',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          // 公式输入
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: InputBorder.none,
                hintText: '输入值或公式 (=SUM...)',
              ),
              onChanged: widget.onFormulaChanged,
            ),
          ),
        ],
      ),
    );
  }
}

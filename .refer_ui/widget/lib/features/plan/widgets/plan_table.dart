/// 周计划时间表 V4 — 多选、批量填充、复制粘贴、涂色。
library;

import 'dart:collection';
import 'package:flutter/material.dart';

const _days = ['时段', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _hours = [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1];
String _hourLabel(int h) => h == 0 ? '0:00' : h == 1 ? '1:00' : '$h:00';

const _presetColors = [
  Colors.transparent, // index 0 = no color
  Color(0xFFFFCDD2), Color(0xFFFFF9C4), Color(0xFFC8E6C9),
  Color(0xFFBBDEFB), Color(0xFFE1BEE7), Color(0xFFFFE0B2),
  Color(0xFFB2EBF2), Color(0xFFF0F4C3), Color(0xFFFFCCBC),
];

class PlanTable extends StatefulWidget {
  final Map<String, Map<int, String>> schedule;
  final Map<String, Map<int, int>> colors;
  final void Function(String day, int hour, String text)? onCellChanged;
  final void Function(Map<String, Map<int, String>> changes)? onCellsChanged;
  final void Function(Map<String, Map<int, int>> changes)? onColorsChanged;

  const PlanTable({
    super.key,
    required this.schedule,
    this.colors = const {},
    this.onCellChanged,
    this.onCellsChanged,
    this.onColorsChanged,
  });

  @override
  State<PlanTable> createState() => _PlanTableState();
}

class _PlanTableState extends State<PlanTable> {
  final _selected = <_CellKey>{};
  final LinkedHashMap<String, String> _clipboard = LinkedHashMap();

  int _colorFor(String day, int hour) => widget.colors[day]?[hour] ?? 0;

  bool _isSelected(String day, int hour) => _selected.contains(_CellKey(day, hour));

  void _toggleCell(String day, int hour) {
    setState(() {
      final key = _CellKey(day, hour);
      _selected.contains(key) ? _selected.remove(key) : _selected.add(key);
    });
  }

  List<_CellKey> get _orderedSelected {
    final list = _selected.toList();
    list.sort((a, b) {
      final h = _hours.indexOf(a.hour).compareTo(_hours.indexOf(b.hour));
      if (h != 0) return h;
      return _days.indexOf(a.day).compareTo(_days.indexOf(b.day));
    });
    return list;
  }

  // ── Fill ──

  void _batchFill() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量填充 (${_selected.length}格)'),
        content: TextField(controller: ctrl, autofocus: true,
            decoration: const InputDecoration(hintText: '输入内容...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { _doFill(ctrl.text, ctx); }, child: const Text('填充')),
        ],
      ),
    );
  }

  void _doFill(String text, BuildContext ctx) {
    final changes = <String, Map<int, String>>{};
    for (final k in _orderedSelected) {
      changes.putIfAbsent(k.day, () => {})[k.hour] = text;
    }
    widget.onCellsChanged?.call(changes);
    setState(() => _selected.clear());
    Navigator.pop(ctx);
  }

  // ── Copy / Paste ──

  void _copySelected() {
    _clipboard.clear();
    for (final k in _orderedSelected) {
      _clipboard['${k.day}-${k.hour}'] = widget.schedule[k.day]?[k.hour] ?? '';
    }
    setState(() {});
  }

  void _pasteToSelected() {
    if (_clipboard.isEmpty) return;
    final values = _clipboard.values.toList();
    final targets = _orderedSelected;
    final changes = <String, Map<int, String>>{};
    for (var i = 0; i < targets.length && i < values.length; i++) {
      changes.putIfAbsent(targets[i].day, () => {})[targets[i].hour] = values[i];
    }
    widget.onCellsChanged?.call(changes);
    setState(() => _selected.clear());
  }

  // ── Color ──

  void _pickColor() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('涂色 (${_selected.length}格)'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _presetColors.map((c) {
              final ci = _presetColors.indexOf(c);
              return GestureDetector(
                onTap: () { Navigator.pop(ctx); _applyColor(ci); },
                child: Container(
                  width: 32, height: 32,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: ci == 0 ? Colors.grey.shade200 : c,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: ci == 0 ? const Icon(Icons.block, size: 16, color: Colors.grey) : null,
                ),
              );
            }).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
      ),
    );
  }

  void _applyColor(int colorIdx) {
    final changes = <String, Map<int, int>>{};
    for (final k in _orderedSelected) {
      changes.putIfAbsent(k.day, () => {})[k.hour] = colorIdx;
    }
    widget.onColorsChanged?.call(changes);
    setState(() => _selected.clear());
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (_selected.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.blue.shade50,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('已选 ${_selected.length} 格', style: const TextStyle(fontSize: 12)),
              _Tb(Icons.format_color_fill, '填充', _batchFill),
              _Tb(Icons.copy, '复制', _copySelected),
              _Tb(Icons.paste, '粘贴', _clipboard.isEmpty ? null : _pasteToSelected),
              _Tb(Icons.palette, '涂色', _pickColor),
              IconButton(icon: const Icon(Icons.close, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selected.clear())),
            ]),
          ),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
            columnWidths: {0: const FixedColumnWidth(50), for (var i = 1; i <= 7; i++) i: const FixedColumnWidth(120)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(decoration: BoxDecoration(color: Colors.grey.shade100),
                children: _days.map((d) => Padding(padding: const EdgeInsets.all(4),
                  child: Text(d, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)))).toList()),
              for (final h in _hours)
                TableRow(children: [
                  Container(padding: const EdgeInsets.all(2), color: Colors.grey.shade50,
                    child: Text(_hourLabel(h), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                  for (var d = 1; d < _days.length; d++) _cell(_days[d], h),
                ]),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _cell(String day, int hour) {
    final text = widget.schedule[day]?[hour] ?? '';
    final sel = _isSelected(day, hour);
    final clrIdx = _colorFor(day, hour);
    final bg = sel ? Colors.blue.shade200 : clrIdx > 0 ? _presetColors[clrIdx] : text.isNotEmpty ? Colors.blue.shade50 : Colors.transparent;

    return GestureDetector(
      onTap: () => _toggleCell(day, hour),
      onLongPress: () => _editDialog(day, hour, text),
      child: Container(
        padding: const EdgeInsets.all(2),
        height: 36,
        decoration: BoxDecoration(color: bg, border: sel ? Border.all(color: Colors.blue, width: 1.5) : null),
        child: Text(text, style: TextStyle(fontSize: 11, color: text.isNotEmpty ? Colors.blue.shade800 : Colors.grey.shade400), maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  void _editDialog(String day, int hour, String text) {
    final ctrl = TextEditingController(text: text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$day ${_hourLabel(hour)}'),
        content: TextField(controller: ctrl, maxLines: 4, autofocus: true,
            decoration: const InputDecoration(hintText: '输入计划内容...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { widget.onCellChanged?.call(day, hour, ctrl.text); Navigator.pop(ctx); }, child: const Text('确定')),
        ],
      ),
    );
  }
}

class _Tb extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback? onTap;
  const _Tb(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 14), label: Text(label, style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact)),
  );
}

class _CellKey { final String day; final int hour; const _CellKey(this.day, this.hour); @override bool operator ==(Object o) => o is _CellKey && o.day == day && o.hour == hour; @override int get hashCode => day.hashCode ^ hour.hashCode; }

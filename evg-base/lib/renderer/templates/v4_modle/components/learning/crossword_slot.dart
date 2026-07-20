/// 填字游戏槽位——从 [ComponentDescriptor.config] 读取 grid[][] + clues。
///
/// `config.grid` 为二维数组，每格为字母字符串（可填）或 null（空白）。
/// `config.clues` 含 `across` / `down` 线索列表。渲染网格并允许点击格子，
/// 当前选中格可由键盘输入字母（轻量交互）。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 填字游戏——`crossword` 组件。
class CrosswordSlot extends StatefulWidget {
  final ComponentDescriptor config;

  const CrosswordSlot({super.key, required this.config});

  @override
  State<CrosswordSlot> createState() => _CrosswordSlotState();
}

class _CrosswordSlotState extends State<CrosswordSlot> {
  List<List<String?>> _grid = const [];
  List<String> _across = const [];
  List<String> _down = const [];
  final Map<String, TextEditingController> _controllers = {};
  int? _selR;
  int? _selC;

  @override
  void initState() {
    super.initState();
    final cfg = widget.config.config;
    final raw = cfg['grid'];
    if (raw is List) {
      _grid = raw.map((row) {
        if (row is List) {
          return row.map((c) => c == null ? null : c.toString()).toList();
        }
        return <String?>[];
      }).toList();
    }
    final clues = cfg['clues'] as Map<String, dynamic>? ?? {};
    _across = (clues['across'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    _down = (clues['down'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    _initControllers();
  }

  void _initControllers() {
    _controllers.clear();
    for (var r = 0; r < _grid.length; r++) {
      for (var c = 0; c < _grid[r].length; c++) {
        if (_grid[r][c] != null) {
          _controllers['$r-$c'] = TextEditingController(text: _grid[r][c]);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final title = cfg['title'] as String? ?? '填字游戏';
    final theme = Theme.of(context);

    if (_grid.isEmpty) {
      return _emptyState(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 网格
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _grid.isNotEmpty ? _grid.first.length : 1,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: _grid.length * (_grid.isNotEmpty ? _grid.first.length : 0),
                    itemBuilder: (ctx, i) {
                      final r = i ~/ (_grid.isNotEmpty ? _grid.first.length : 1);
                      final c = i % (_grid.isNotEmpty ? _grid.first.length : 1);
                      final filled = _grid[r][c] != null;
                      final selected = _selR == r && _selC == c;
                      if (!filled) {
                        return Container(color: theme.colorScheme.surfaceContainerHighest);
                      }
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selR = r;
                          _selC = c;
                        }),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: TextField(
                            controller: _controllers['$r-$c'],
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                            style: theme.textTheme.titleMedium,
                            onTap: () => setState(() {
                              _selR = r;
                              _selC = c;
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // 线索
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('横向', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ..._across.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('${e.key + 1}. ${e.value}',
                                style: theme.textTheme.bodySmall),
                          )),
                      const SizedBox(height: 12),
                      Text('纵向', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ..._down.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('${e.key + 1}. ${e.value}',
                                style: theme.textTheme.bodySmall),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_3x3, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置填字 (config.grid)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

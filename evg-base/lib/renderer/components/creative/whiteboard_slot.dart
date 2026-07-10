/// 白板槽位——从 [ComponentDescriptor.config] 读取 tools/colors/lineWidth。
///
/// 提供一个基础涂鸦画布：从 config 读取可用颜色、工具与线宽，
/// 支持手指/鼠标绘制，工具栏按 config 动态生成。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 白板——`whiteboard` 组件。
class WhiteboardSlot extends StatefulWidget {
  final ComponentDescriptor config;

  const WhiteboardSlot({super.key, required this.config});

  @override
  State<WhiteboardSlot> createState() => _WhiteboardSlotState();
}

class _WhiteboardSlotState extends State<WhiteboardSlot> {
  final List<_Stroke> _strokes = [];
  List<Offset> _current = [];
  Color _activeColor = Colors.black;
  double _lineWidth = 3;
  String _tool = 'pen';

  @override
  void initState() {
    super.initState();
    final cfg = widget.config.config;
    final colors = (cfg['colors'] as List<dynamic>?) ?? ['#000000', '#FF4D4F', '#1677FF', '#52C41A'];
    final parsed = colors
        .map((c) {
          if (c is String) {
            try {
              return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
            } catch (_) {}
          }
          return null;
        })
        .whereType<Color>()
        .toList();
    if (parsed.isNotEmpty) _activeColor = parsed.first;
    _lineWidth = (cfg['lineWidth'] as num?)?.toDouble() ?? 3;
    final tools = (cfg['tools'] as List<dynamic>?) ?? ['pen', 'eraser'];
    if (tools.isNotEmpty) _tool = tools.first.toString();
  }

  void _onPanStart(Offset p) => setState(() {
        _current = [p];
        _strokes.add(_Stroke(color: _activeColor, width: _lineWidth, tool: _tool, points: _current));
      });

  void _onPanUpdate(Offset p) => setState(() => _current.add(p));

  void _onPanEnd() => setState(() => _current = []);

  void _clear() => setState(() => _strokes.clear());

  void _undo() => setState(() {
        if (_strokes.isNotEmpty) _strokes.removeLast();
      });

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final tools = (cfg['tools'] as List<dynamic>?) ?? ['pen', 'eraser'];
    final colors = (cfg['colors'] as List<dynamic>?) ?? ['#000000', '#FF4D4F', '#1677FF', '#52C41A'];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in tools)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: Icon(
                        (t.toString()) == 'eraser' ? Icons.cleaning_services : Icons.edit,
                        size: 18,
                      ),
                      isSelected: _tool == t.toString(),
                      selectedIcon: Icon(
                        (t.toString()) == 'eraser' ? Icons.cleaning_services : Icons.edit,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () => setState(() => _tool = t.toString()),
                      tooltip: t.toString(),
                    ),
                  ),
                const VerticalDivider(width: 12),
                for (final c in colors)
                  Builder(builder: (ctx) {
                    Color? col;
                    if (c is String) {
                      try {
                        col = Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
                      } catch (_) {}
                    }
                    if (col == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () => setState(() => _activeColor = col!),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _activeColor == col
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                const VerticalDivider(width: 12),
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  onPressed: _undo,
                  tooltip: '撤销',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: _clear,
                  tooltip: '清空',
                ),
              ],
            ),
          ),
        ),
        // 画布
        Expanded(
          child: GestureDetector(
            onPanStart: (d) => _onPanStart(d.localPosition),
            onPanUpdate: (d) => _onPanUpdate(d.localPosition),
            onPanEnd: (_) => _onPanEnd(),
            child: Container(
              color: theme.colorScheme.surface,
              child: CustomPaint(
                painter: _WhiteboardPainter(strokes: _strokes),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stroke {
  final Color color;
  final double width;
  final String tool;
  final List<Offset> points;
  const _Stroke({required this.color, required this.width, required this.tool, required this.points});
}

class _WhiteboardPainter extends CustomPainter {
  final List<_Stroke> strokes;
  const _WhiteboardPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.tool == 'eraser' ? Colors.white : s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter old) => true;
}

import 'package:flutter/material.dart';
import '../../../slot/service/slot_scale.dart';

/// 轻量级思维导图组件。
///
/// 将缩进树状文本解析为可视化节点图。
/// 格式：
/// ```
/// 根节点
///   子节点1
///     孙节点A
///     孙节点B
///   子节点2
/// ```
///
/// 横向可滚动（可超出），纵向自适应 SlotScale。
class MindMapWidget extends StatelessWidget {
  final String text;

  const MindMapWidget({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final root = _parse(text);
    if (root == null) return const SizedBox.shrink();

    final s = SlotScale.of(context).scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 横向可滚动（内容可超宽），纵向不可滚动 → 必须自适应
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : double.infinity,
            ),
            child: SingleChildScrollView(
              child: _NodeWidget(node: root, level: 0, scale: s),
            ),
          ),
        );
      },
    );
  }

  /// 解析缩进文本为树节点。
  _Node? _parse(String raw) {
    final lines = raw.split('\n');
    final start = lines.first.trim().toLowerCase() == 'mindmap' ? 1 : 0;
    if (start >= lines.length) return null;

    String? rootLine;
    int rootIndent = 0;
    for (final line in lines.skip(start)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      rootLine = trimmed;
      rootIndent = line.length - line.trimLeft().length;
      break;
    }
    if (rootLine == null) return null;

    final root = _Node(rootLine);
    _buildTree(lines, start, rootIndent, root, start + 1);
    return root;
  }

  int _buildTree(List<String> lines, int startIndent, int parentIndent,
      _Node parent, int fromIndex) {
    int i = fromIndex;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      if (indent <= parentIndent) return i;
      final child = _Node(trimmed);
      parent.children.add(child);
      i = _buildTree(lines, indent, indent, child, i + 1);
    }
    return i;
  }
}

class _Node {
  final String text;
  final List<_Node> children;
  _Node(this.text) : children = [];
}

/// 单个节点及其子树的渲染。
class _NodeWidget extends StatelessWidget {
  final _Node node;
  final int level;
  final double scale;

  const _NodeWidget({
    required this.node,
    required this.level,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final nodeWidget = Container(
      constraints: BoxConstraints(
        minWidth: 80 * scale,
        maxWidth: 160 * scale,
      ),
      padding: EdgeInsets.symmetric(
          horizontal: 12 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: _colorForLevel(level),
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(
          color: _colorForLevel(level).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        node.text,
        style: TextStyle(
          fontSize: (level == 0 ? 15 : 13) * scale,
          fontWeight: level <= 1 ? FontWeight.w600 : FontWeight.normal,
          color: level <= 1 ? Colors.white : Colors.black87,
          height: 1.2,
        ),
        textAlign: TextAlign.center,
      ),
    );

    if (node.children.isEmpty) return nodeWidget;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        nodeWidget,
        SizedBox(width: 16 * scale),
        SizedBox(
          width: 20 * scale,
          child: CustomPaint(
            painter: _LinePainter(
              color: _colorForLevel(level).withValues(alpha: 0.6),
            ),
          ),
        ),
        SizedBox(width: 4 * scale),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: node.children.map((child) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 4 * scale),
              child: _NodeWidget(
                  node: child, level: level + 1, scale: scale),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _colorForLevel(int level) {
    const colors = [
      Color(0xFF1677FF),
      Color(0xFF2DA44E),
      Color(0xFFCF222E),
      Color(0xFF722ED1),
      Color(0xFFFA8C16),
    ];
    return colors[level % colors.length];
  }
}

/// 连接线绘制。
class _LinePainter extends CustomPainter {
  final Color color;
  _LinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.color != color;
}

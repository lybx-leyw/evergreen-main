import 'package:flutter/material.dart';

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
class MindMapWidget extends StatelessWidget {
  final String text;

  const MindMapWidget({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final root = _parse(text);
    if (root == null) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _NodeWidget(node: root, level: 0),
    );
  }

  /// 解析缩进文本为树节点。
  _Node? _parse(String raw) {
    final lines = raw.split('\n');
    // 跳过第一行如果是 "mindmap"
    final start = lines.first.trim().toLowerCase() == 'mindmap' ? 1 : 0;
    if (start >= lines.length) return null;

    // 计算根节点缩进（第一个非空行）
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

    // 递归构建树
    final root = _Node(rootLine);
    _buildTree(lines, start, rootIndent, root, start + 1);
    return root;
  }

  int _buildTree(List<String> lines, int startIndent, int parentIndent, _Node parent, int fromIndex) {
    int i = fromIndex;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) { i++; continue; }

      final indent = line.length - line.trimLeft().length;
      if (indent <= parentIndent) {
        // 回到父级缩进或以上 → 结束当前层级
        return i;
      }

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

  const _NodeWidget({required this.node, required this.level});

  @override
  Widget build(BuildContext context) {
    final nodeWidget = Container(
      constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _colorForLevel(level),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _colorForLevel(level).withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        node.text,
        style: TextStyle(
          fontSize: level == 0 ? 15 : 13,
          fontWeight: level <= 1 ? FontWeight.w600 : FontWeight.normal,
          color: level <= 1 ? Colors.white : Colors.black87,
          height: 1.2,
        ),
        textAlign: TextAlign.center,
      ),
    );

    if (node.children.isEmpty) return nodeWidget;

    // 子树：垂直排列子节点，左侧画连线
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        nodeWidget,
        const SizedBox(width: 16),
        SizedBox(
          width: 20,
          child: CustomPaint(
            painter: _LinePainter(
              color: _colorForLevel(level).withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 子节点垂直排列
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: node.children.map((child) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _NodeWidget(node: child, level: level + 1),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _colorForLevel(int level) {
    const colors = [
      Color(0xFF1677FF), // ZJU 蓝 — 根节点
      Color(0xFF2DA44E), // 绿
      Color(0xFFCF222E), // 红
      Color(0xFF722ED1), // 紫
      Color(0xFFFA8C16), // 橙
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

    // 从左边缘中间到右边缘中间画横线
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => oldDelegate.color != color;
}

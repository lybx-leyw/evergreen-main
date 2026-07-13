/// Slot 可视化绘制器 — 在画布上渲染 DesignSlot 的虚线框 + 命名标签。
///
/// P2 实现：CustomPainter 绘制虚线矩形框 + 标签 + 组件信息。 
library;

import 'package:flutter/material.dart';

import '../models/design_slot.dart';

/// Slot 在画布上的绘制参数。
class SlotDrawInfo {
  final DesignSlot slot;
  final Rect rect; // 画布像素坐标
  final bool isSelected;
  final bool isHovered;

  const SlotDrawInfo({
    required this.slot,
    required this.rect,
    this.isSelected = false,
    this.isHovered = false,
  });
}

/// Slot 绘制器 —— 在 [CustomPainter] 或 [CustomPaint] 中渲染 Slot 的视觉表示。
///
/// 绘制内容：
/// - 虚线矩形边框（选中时加粗变色）
/// - 顶部标签条（显示 slot.label 或 region 名称）
/// - 已绑定组件时显示组件图标+类型名
/// - 未绑定时显示 "+" 添加提示
class SlotPainter extends CustomPainter {
  final List<SlotDrawInfo> slots;
  final Color defaultColor;
  final Color selectedColor;
  final Color hoverColor;

  SlotPainter({
    required this.slots,
    this.defaultColor = Colors.blueGrey,
    this.selectedColor = Colors.blue,
    this.hoverColor = Colors.lightBlue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final info in slots) {
      _drawSlot(canvas, info);
    }
  }

  void _drawSlot(Canvas canvas, SlotDrawInfo info) {
    final rect = info.rect;
    final color = info.isSelected
        ? selectedColor
        : info.isHovered
            ? hoverColor
            : defaultColor;

    // ── 虚线边框 ──
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = info.isSelected ? 2.5 : 1.5;

    _drawDashedRect(canvas, rect, borderPaint, dashWidth: 6, gapWidth: 4);

    // ── 填充半透明背景 ──
    final fillPaint = Paint()
      ..color = color.withValues(alpha: info.isSelected ? 0.1 : 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // ── 顶部标签条 ──
    final labelHeight = 24.0;
    if (rect.height > labelHeight + 16) {
      final labelRect = Rect.fromLTWH(
        rect.left, rect.top,
        rect.width, labelHeight,
      );
      final labelBg = Paint()
        ..color = color.withValues(alpha: 0.85);
      canvas.drawRect(labelRect, labelBg);

      // 标签文字
      final label = info.slot.label.isNotEmpty ? info.slot.label : info.slot.region.name;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      textPainter.layout(maxWidth: rect.width - 8);
      textPainter.paint(
        canvas,
        Offset(rect.left + 4, rect.top + (labelHeight - textPainter.height) / 2),
      );
    }

    // ── 中间内容（组件信息或占位提示） ──
    if (info.slot.component != null) {
      _drawComponentInfo(canvas, info, color);
    } else if (info.isSelected && rect.height > 60) {
      _drawPlaceholder(canvas, rect, color);
    }
  }

  void _drawComponentInfo(Canvas canvas, SlotDrawInfo info, Color color) {
    final rect = info.rect;
    final comp = info.slot.component!;
    final typeStr = comp.type;

    final tp = TextPainter(
      text: TextSpan(
        text: typeStr,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
  }

  void _drawPlaceholder(Canvas canvas, Rect rect, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: '+ 拖入组件',
        style: TextStyle(
          color: color.withValues(alpha: 0.5),
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    double dashWidth = 6,
    double gapWidth = 4,
  }) {
    final path = Path();
    // 上
    path.moveTo(rect.left, rect.top);
    path.lineTo(rect.right, rect.top);
    // 右
    path.moveTo(rect.right, rect.top);
    path.lineTo(rect.right, rect.bottom);
    // 下
    path.moveTo(rect.right, rect.bottom);
    path.lineTo(rect.left, rect.bottom);
    // 左
    path.moveTo(rect.left, rect.bottom);
    path.lineTo(rect.left, rect.top);

    // 使用 PathMetrics 绘制虚线
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, end.toDouble()),
          paint,
        );
        distance = end + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant SlotPainter oldDelegate) {
    return oldDelegate.slots != slots;
  }
}

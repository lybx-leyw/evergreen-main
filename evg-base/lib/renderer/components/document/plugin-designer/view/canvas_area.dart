/// 画布区域 —— 拖放组件、框选 Slot、移动/调整 Slot 的核心交互层。
///
/// P2 实现：
/// - 虚线网格背景
/// - 渲染已有 Slot（通过 SlotPainter）
/// - 拖拽框选创建新 Slot
/// - 点击选中 Slot、拖拽移动
/// - DragTarget 接收从 ComponentPicker 拖入的组件
library;

import 'package:flutter/material.dart';

import '../models/design_component.dart';
import '../models/design_slot.dart';
import 'slot_painter.dart';

/// 画布交互回调。
typedef SlotSelectedCallback = void Function(int slotIndex);
typedef SlotCreatedCallback = void Function(double x, double y, double w, double h);
typedef SlotMovedCallback = void Function(int slotIndex, double dx, double dy);
typedef ComponentDroppedCallback = void Function(int slotIndex, String componentType);

/// 编排画布 —— 中间交互区域。
///
/// 交互模型：
/// 1. 空闲态（idle）：点击选中 Slot，拖拽空白区域开始框选
/// 2. 框选态（drawing）：鼠标拖动创建新 Slot 虚线框
/// 3. 拖拽态（dragging）：拖拽已有 Slot 到新位置
/// 4. 接收态（receiving）：DragTarget 高亮，接收组件拖放
class CanvasArea extends StatefulWidget {
  /// 当前页面的 Slot 列表。
  final List<DesignSlot> slots;

  /// 当前选中的 Slot 索引（-1 = 未选中）。
  final int selectedSlotIndex;

  /// 画布宽度（逻辑像素）。
  final double canvasWidth;

  /// 画布高度（逻辑像素）。
  final double canvasHeight;

  /// 网格大小（像素）。
  final double gridSize;

  // ── 回调 ──
  final SlotSelectedCallback? onSlotSelected;
  final SlotCreatedCallback? onSlotCreated;
  final SlotMovedCallback? onSlotMoved;
  final ComponentDroppedCallback? onComponentDropped;

  const CanvasArea({
    super.key,
    required this.slots,
    this.selectedSlotIndex = -1,
    this.canvasWidth = 800,
    this.canvasHeight = 600,
    this.gridSize = 20,
    this.onSlotSelected,
    this.onSlotCreated,
    this.onSlotMoved,
    this.onComponentDropped,
  });

  @override
  State<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<CanvasArea> {
  // 框选状态
  bool _isDrawing = false;
  Offset? _drawStart;
  Offset? _drawCurrent;

  // 拖拽状态
  int _draggingSlotIndex = -1;
  Offset? _dragStart;

  // 悬停状态
  int _hoveredSlotIndex = -1;

  // DragTarget 高亮
  bool _dragOverCanvas = false;

  @override
  Widget build(BuildContext context) {
    final slots = widget.slots;
    final drawInfos = <SlotDrawInfo>[];
    final slotRects = <int, Rect>{};

    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final rect = Rect.fromLTWH(
        slot.rect[0], slot.rect[1],
        slot.rect[2], slot.rect[3],
      );
      slotRects[i] = rect;
      drawInfos.add(SlotDrawInfo(
        slot: slot,
        rect: rect,
        isSelected: i == widget.selectedSlotIndex,
        isHovered: i == _hoveredSlotIndex,
      ));
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _dragOverCanvas = true);
        return true;
      },
      onLeave: (_) => setState(() => _dragOverCanvas = false),
      onAcceptWithDetails: (details) {
        setState(() => _dragOverCanvas = false);
        final localPos = _getLocalPos(context, details.offset);
        // 找到鼠标落在哪个 Slot 里
        int targetIdx = -1;
        for (final entry in slotRects.entries) {
          if (entry.value.contains(localPos)) {
            targetIdx = entry.key;
            break;
          }
        }
        if (targetIdx >= 0) {
          widget.onComponentDropped?.call(targetIdx, details.data);
        } else {
          // 没有命中已有 Slot → 自动创建一个
          final newX = (localPos.dx / widget.gridSize).round() * widget.gridSize;
          final newY = (localPos.dy / widget.gridSize).round() * widget.gridSize;
          widget.onSlotCreated?.call(newX.toDouble(), newY.toDouble(), 200, 150);
          // 延迟回调：下一个 frame 再放组件（slots 已更新）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final newIdx = widget.slots.length - 1;
            if (newIdx >= 0) {
              widget.onComponentDropped?.call(newIdx, details.data);
            }
          });
        }
      },
      builder: (context, candidateData, rejectedData) => LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: GestureDetector(
                onPanStart: (d) => _onPanStart(d.localPosition, slotRects),
                onPanUpdate: (d) => _onPanUpdate(d.localPosition),
                onPanEnd: (d) => _onPanEnd(),
                onTapUp: (d) => _onTapUp(d.localPosition, slotRects),
                child: MouseRegion(
                  onHover: (e) => _onHover(e.localPosition, slotRects),
                  child: SizedBox(
                    width: widget.canvasWidth,
                    height: widget.canvasHeight,
                    child: Stack(
                      children: [
                        // 网格背景
                        CustomPaint(
                          size: Size(widget.canvasWidth, widget.canvasHeight),
                          painter: _GridPainter(
                            gridSize: widget.gridSize,
                            highlight: _dragOverCanvas,
                          ),
                        ),
                        // Slot 绘制
                        CustomPaint(
                          size: Size(widget.canvasWidth, widget.canvasHeight),
                          painter: SlotPainter(slots: drawInfos),
                        ),
                        // 框选框
                        if (_isDrawing && _drawStart != null && _drawCurrent != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SelectionBoxPainter(
                                start: _drawStart!,
                                current: _drawCurrent!,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Offset _getLocalPos(BuildContext context, Offset globalPos) {
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return globalPos;
    return rb.globalToLocal(globalPos);
  }

  void _onPanStart(Offset pos, Map<int, Rect> slotRects) {
    // 检查是否在已有 Slot 内部
    for (final entry in slotRects.entries) {
      if (entry.value.contains(pos)) {
        // 开始拖拽已有 Slot
        setState(() {
          _draggingSlotIndex = entry.key;
          _dragStart = pos;
        });
        widget.onSlotSelected?.call(entry.key);
        return;
      }
    }
    // 开始框选
    setState(() {
      _isDrawing = true;
      _drawStart = pos;
      _drawCurrent = pos;
      _draggingSlotIndex = -1;
      widget.onSlotSelected?.call(-1);
    });
  }

  void _onPanUpdate(Offset pos) {
    if (_draggingSlotIndex >= 0 && _dragStart != null) {
      // 拖拽已有 Slot
      final dx = (pos.dx - _dragStart!.dx).roundToDouble();
      final dy = (pos.dy - _dragStart!.dy).roundToDouble();
      if (dx.abs() > 2 || dy.abs() > 2) {
        widget.onSlotMoved?.call(_draggingSlotIndex, dx, dy);
        _dragStart = pos; // 增量更新
      }
    } else if (_isDrawing) {
      setState(() => _drawCurrent = pos);
    }
  }

  void _onPanEnd() {
    if (_isDrawing && _drawStart != null && _drawCurrent != null) {
      final rect = Rect.fromPoints(_drawStart!, _drawCurrent!);
      final w = rect.width.abs();
      final h = rect.height.abs();
      if (w > 20 && h > 20) {
        final x = rect.left < rect.right ? rect.left : rect.right;
        final y = rect.top < rect.bottom ? rect.top : rect.bottom;
        // 吸附网格
        final snappedX = (x / widget.gridSize).round() * widget.gridSize;
        final snappedY = (y / widget.gridSize).round() * widget.gridSize;
        widget.onSlotCreated?.call(
          snappedX.toDouble(),
          snappedY.toDouble(),
          w,
          h,
        );
      }
    }
    setState(() {
      _isDrawing = false;
      _drawStart = null;
      _drawCurrent = null;
      _draggingSlotIndex = -1;
      _dragStart = null;
    });
  }

  void _onTapUp(Offset pos, Map<int, Rect> slotRects) {
    for (final entry in slotRects.entries) {
      if (entry.value.contains(pos)) {
        widget.onSlotSelected?.call(entry.key);
        return;
      }
    }
    widget.onSlotSelected?.call(-1);
  }

  void _onHover(Offset pos, Map<int, Rect> slotRects) {
    for (final entry in slotRects.entries) {
      if (entry.value.contains(pos)) {
        if (_hoveredSlotIndex != entry.key) {
          setState(() => _hoveredSlotIndex = entry.key);
        }
        return;
      }
    }
    if (_hoveredSlotIndex != -1) {
      setState(() => _hoveredSlotIndex = -1);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 网格背景绘制器
// ═══════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final double gridSize;
  final bool highlight;

  _GridPainter({required this.gridSize, this.highlight = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = highlight
          ? Colors.blue.withValues(alpha: 0.08)
          : Colors.grey.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    // 竖线
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // 横线
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.gridSize != gridSize || oldDelegate.highlight != highlight;
}

// ═══════════════════════════════════════════════════════════════
// 框选虚线框绘制器
// ═══════════════════════════════════════════════════════════════

class _SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  _SelectionBoxPainter({required this.start, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, current);
    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SelectionBoxPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.current != current;
}

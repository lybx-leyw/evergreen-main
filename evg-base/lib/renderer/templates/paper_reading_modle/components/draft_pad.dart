/// 草稿本 — 笔写多页可翻页可新增页面的草稿。
///
/// 参考 whiteboard_slot.dart 的 CustomPaint + GestureDetector 模式实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';

class DraftPad extends ConsumerStatefulWidget {
  const DraftPad({super.key});

  @override
  ConsumerState<DraftPad> createState() => _DraftPadState();
}

class _DraftPadState extends ConsumerState<DraftPad> {
  /// 当前页的未保存笔迹：List<(Offset, Offset)>
  final List<(Offset, Offset)> _currentStrokes = [];

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(draftPagesProvider);
    final currentPage = ref.watch(currentDraftPageProvider);
    final tool = ref.watch(draftToolProvider);
    final color =
        Color(ref.watch(draftColorProvider));
    final lineWidth = ref.watch(draftLineWidthProvider);

    final pageData = currentPage < pages.length
        ? pages[currentPage]
        : pages.first;

    return Column(
      children: [
        // 工具栏
        _buildToolbar(tool, color, lineWidth),
        // 画布
        Expanded(
          child: GestureDetector(
            onPanStart: (details) {
              if (tool == 'pen') {
                _currentStrokes.add((
                  details.localPosition,
                  details.localPosition,
                ));
                setState(() {});
              } else if (tool == 'eraser') {
                // 橡皮：在 stroke 列表里前进标记擦除点
                _currentStrokes.add((
                  details.localPosition,
                  details.localPosition,
                ));
                setState(() {});
              }
            },
            onPanUpdate: (details) {
              if (_currentStrokes.isNotEmpty) {
                final last = _currentStrokes.last;
                _currentStrokes[_currentStrokes
                        .length -
                    1] = (last.$1,
                    details.localPosition);
                setState(() {});
              }
            },
            onPanEnd: (_) {
              // 保存笔迹到页数据
              if (_currentStrokes.isNotEmpty) {
                final allPages =
                    ref.read(draftPagesProvider);
                final updated =
                    List<DraftPage>.from(allPages);
                final page =
                    updated[currentPage];
                final newStrokes = [
                  ...page.strokes,
                  ..._currentStrokes
                      .map((s) => [
                            s.$1.dx,
                            s.$1.dy,
                            s.$2.dx,
                            s.$2.dy,
                          ])
                ];
                updated[currentPage] =
                    page.copyWith(
                        strokes: newStrokes);
                ref
                    .read(draftPagesProvider
                        .notifier)
                    .state = updated;
                _currentStrokes.clear();
                setState(() {});
              }
            },
            child: Container(
              color: const Color(0xFFFFF8E7),
              child: ClipRect(
                child: CustomPaint(
                  painter: _DraftPainter(
                    savedStrokes: pageData.strokes,
                    currentStrokes: _currentStrokes,
                    color: color,
                    lineWidth: lineWidth,
                    isEraser: tool == 'eraser',
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        // 页脚：翻页 + 新增页
        _buildPageFooter(currentPage, pages.length),
      ],
    );
  }

  Widget _buildToolbar(
      String tool, Color color, double lineWidth) {
    final colors = [
      0xFF000000, // 黑
      0xFFE05353, // 红
      0xFF4A90D9, // 蓝
      0xFF50B86C, // 绿
      0xFFE8A838, // 金
    ];

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFFEDE5D5),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.edit,
            label: '笔',
            isActive: tool == 'pen',
            onTap: () => ref
                .read(draftToolProvider.notifier)
                .state = 'pen',
          ),
          _ToolButton(
            icon: Icons.auto_fix_high,
            label: '擦',
            isActive: tool == 'eraser',
            onTap: () => ref
                .read(draftToolProvider.notifier)
                .state = 'eraser',
          ),
          const SizedBox(width: 8),
          ...colors.map((c) => GestureDetector(
                onTap: () => ref
                    .read(draftColorProvider.notifier)
                    .state = c,
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 3),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ref.watch(
                                  draftColorProvider) ==
                              c
                          ? const Color(0xFF8B6914)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              )),
          const Spacer(),
          _ToolButton(
            icon: Icons.delete_outline,
            label: '清',
            onTap: () {
              final allPages =
                  ref.read(draftPagesProvider);
              final updated =
                  List<DraftPage>.from(allPages);
              updated[
                      ref.watch(currentDraftPageProvider)] =
                  DraftPage(
                      pageIndex: ref.watch(
                          currentDraftPageProvider));
              ref
                  .read(
                      draftPagesProvider.notifier)
                  .state = updated;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPageFooter(int currentPage, int total) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFEDE5D5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: currentPage > 0
                ? () => ref
                    .read(currentDraftPageProvider
                        .notifier)
                    .state = currentPage - 1
                : null,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32),
          ),
          Text('${currentPage + 1} / $total',
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B6914))),
          IconButton(
            icon: const Icon(Icons.chevron_right,
                size: 18),
            onPressed: currentPage < total - 1
                ? () => ref
                    .read(currentDraftPageProvider
                        .notifier)
                    .state = currentPage + 1
                : null,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: () {
              final allPages =
                  ref.read(draftPagesProvider);
              ref
                  .read(
                      draftPagesProvider.notifier)
                  .state = [
                ...allPages,
                DraftPage(pageIndex: allPages.length)
              ];
              ref
                  .read(currentDraftPageProvider
                      .notifier)
                  .state = allPages.length;
            },
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32),
            tooltip: '新增页面',
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF8B6914).withAlpha(30)
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: isActive
                    ? const Color(0xFF4A2C00)
                    : const Color(0xFF8B6914)),
            const SizedBox(width: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: isActive
                        ? const Color(0xFF4A2C00)
                        : const Color(0xFF8B6914))),
          ],
        ),
      ),
    );
  }
}

/// 草稿绘制器。
class _DraftPainter extends CustomPainter {
  final List<List<double>> savedStrokes;
  final List<(Offset, Offset)> currentStrokes;
  final Color color;
  final double lineWidth;
  final bool isEraser;

  _DraftPainter({
    required this.savedStrokes,
    required this.currentStrokes,
    required this.color,
    required this.lineWidth,
    required this.isEraser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制已保存笔迹
    for (final stroke in savedStrokes) {
      if (stroke.length < 4) continue;
      final paint = Paint()
        ..color = isEraser
            ? const Color(0xFFFFF8E7)
            : color
        ..strokeWidth = isEraser ? lineWidth * 3 : lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < stroke.length - 3; i += 4) {
        canvas.drawLine(
          Offset(stroke[i], stroke[i + 1]),
          Offset(stroke[i + 2], stroke[i + 3]),
          paint,
        );
      }
    }

    // 绘制当前笔迹
    final currentPaint = Paint()
      ..color = isEraser ? const Color(0xFFFFF8E7) : color
      ..strokeWidth = isEraser ? lineWidth * 3 : lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in currentStrokes) {
      canvas.drawLine(
        stroke.$1,
        stroke.$2,
        currentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DraftPainter oldDelegate) =>
      oldDelegate.savedStrokes != savedStrokes ||
      oldDelegate.currentStrokes != currentStrokes ||
      oldDelegate.color != color;
}

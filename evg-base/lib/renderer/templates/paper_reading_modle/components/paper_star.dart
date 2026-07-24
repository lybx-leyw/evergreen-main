/// 论文星星 — 星空视图中的星星组件。
///
/// 每颗星 = 一篇论文，闪烁 + 漂浮动画，标题始终可见。
library;

import 'dart:math';
import 'package:flutter/material.dart';

class PaperStar extends StatefulWidget {
  final String title;
  final String authors;
  final Color color;
  final bool isAdd;
  final VoidCallback? onTap;

  const PaperStar({
    super.key,
    required this.title,
    required this.authors,
    required this.color,
    this.isAdd = false,
    this.onTap,
  });

  @override
  State<PaperStar> createState() => _PaperStarState();
}

class _PaperStarState extends State<PaperStar>
    with TickerProviderStateMixin {
  late AnimationController _twinkle;
  late AnimationController _float;
  late Animation<double> _twinkleAnim;
  late Animation<Offset> _floatAnim;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    final dur = Duration(
        milliseconds: 1500 + _random.nextInt(1500));
    _twinkle = AnimationController(
      vsync: this,
      duration: dur,
    )..repeat(reverse: true);
    _twinkleAnim =
        Tween<double>(begin: 0.6, end: 1.0).animate(_twinkle);

    _float = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: 2500 + _random.nextInt(2000)),
    )..repeat(reverse: true);
    _floatAnim = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(
        (_random.nextDouble() - 0.5) * 12,
        (_random.nextDouble() - 0.5) * 8,
      ),
    ).animate(_float);
  }

  @override
  void dispose() {
    _twinkle.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_twinkle, _float]),
        builder: (context, _) {
          return Transform.translate(
            offset: _floatAnim.value,
            child: Opacity(
              opacity: widget.isAdd ? 0.5 : _twinkleAnim.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isAdd)
                    Icon(Icons.add_circle_outline,
                        size: 28,
                        color: Colors.white.withAlpha(128))
                  else
                    Icon(Icons.auto_awesome,
                        size: 28,
                        color: widget.color,
                        shadows: [
                          Shadow(
                            color: widget.color.withAlpha(180),
                            blurRadius: 12,
                          ),
                        ]),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 130,
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isAdd
                            ? Colors.white.withAlpha(153)
                            : Colors.white.withAlpha(217),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        shadows: [
                          Shadow(
                            color: widget.color.withAlpha(102),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.authors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.authors,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white.withAlpha(179),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

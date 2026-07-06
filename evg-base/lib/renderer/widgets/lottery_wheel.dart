/// 抽奖转盘——自绘可交互旋转转盘组件。
///
/// 公开类：[LotteryWheel]
///
/// 使用 CustomPainter 绘制扇形分区，支持：
/// - 点击旋转（随机结果）
/// - 平滑旋转动画（ease-out deceleration）
/// - 自定义分区颜色和文字
/// - 指示器标记中奖结果
library;

import 'dart:math';
import 'package:flutter/material.dart';

/// 转盘分区数据。
class WheelSegment {
  final String label;
  final Color color;
  final IconData? icon;

  const WheelSegment({
    required this.label,
    this.color = Colors.blue,
    this.icon,
  });
}

/// 自绘旋转转盘组件。
///
/// 使用方式：
/// ```dart
/// LotteryWheel(
///   segments: [
///     WheelSegment(label: '一等奖', color: Colors.red),
///     WheelSegment(label: '二等奖', color: Colors.orange),
///     WheelSegment(label: '三等奖', color: Colors.blue),
///   ],
///   onResult: (segment) => print('中奖: ${segment.label}'),
/// )
/// ```
class LotteryWheel extends StatefulWidget {
  /// 分区列表（至少 2 个）。
  final List<WheelSegment> segments;

  /// 转盘直径。
  final double size;

  /// 中奖回调。
  final void Function(WheelSegment segment)? onResult;

  /// 旋转按钮文字。
  final String spinLabel;

  const LotteryWheel({
    super.key,
    required this.segments,
    this.size = 280,
    this.onResult,
    this.spinLabel = '开始抽奖',
  });

  @override
  State<LotteryWheel> createState() => _LotteryWheelState();
}

class _LotteryWheelState extends State<LotteryWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _currentAngle = 0;
  bool _spinning = false;
  WheelSegment? _result;
  String _resultText = '';

  static const _colors = [
    Color(0xFFE53935), // red
    Color(0xFF1E88E5), // blue
    Color(0xFF43A047), // green
    Color(0xFFFB8C00), // orange
    Color(0xFF8E24AA), // purple
    Color(0xFF00ACC1), // cyan
    Color(0xFFF4511E), // deep orange
    Color(0xFF3949AB), // indigo
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _controller.addListener(() {
      setState(() {
        _currentAngle = _animation.value;
      });
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onSpinComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    if (_spinning) return;

    setState(() {
      _spinning = true;
      _result = null;
      _resultText = '';
    });

    // 随机旋转 5~10 圈 + 随机偏移
    final random = Random();
    final spins = 5 + random.nextInt(5); // 5-9 full rotations
    final extraAngle = random.nextDouble() * 2 * pi;
    final targetAngle = _currentAngle + (spins * 2 * pi) + extraAngle;

    _animation = Tween<double>(
      begin: _currentAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.reset();
    _controller.forward();
  }

  void _onSpinComplete() {
    setState(() {
      _spinning = false;
    });

    // 计算指针指向哪个分区
    final segmentAngle = 2 * pi / widget.segments.length;
    // 指针在顶部（-pi/2），需要计算当前角度对应的分区
    final normalizedAngle = _currentAngle % (2 * pi);
    // 指针方向是向上 (270度 = -pi/2)，转盘顺时针旋转
    // 指针指向的分区 = 旋转角度对应的分区（逆推）
    final pointerIndex =
        (normalizedAngle / segmentAngle).round() % widget.segments.length;
    // 由于指针在顶部（270°），需要反转索引
    final resultIndex =
        (widget.segments.length - pointerIndex) % widget.segments.length;

    final result = widget.segments[resultIndex];
    setState(() {
      _result = result;
      _resultText = '🎉 ${result.label}';
    });

    widget.onResult?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSegments = _withColors(widget.segments);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 结果展示
        if (_resultText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _resultText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),

        // 转盘
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 转盘主体
              Transform.rotate(
                angle: _currentAngle,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _WheelPainter(segments: effectiveSegments),
                ),
              ),

              // 中心按钮
              GestureDetector(
                onTap: _spinning ? null : _spin,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _spinning
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.play_arrow_rounded,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                ),
              ),

              // 顶部指针
              Positioned(
                top: 0,
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: _PointerPainter(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 旋转按钮
        SizedBox(
          width: 160,
          child: FilledButton.icon(
            onPressed: _spinning ? null : _spin,
            icon: const Icon(Icons.casino, size: 20),
            label: Text(widget.spinLabel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),

        // 分区图例
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: effectiveSegments.map((seg) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: seg.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  seg.label,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 如果 segment 未指定颜色，自动分配。
  List<WheelSegment> _withColors(List<WheelSegment> segments) {
    return segments.asMap().entries.map((e) {
      final seg = e.value;
      return WheelSegment(
        label: seg.label,
        color: seg.color != Colors.blue
            ? seg.color
            : _colors[e.key % _colors.length],
        icon: seg.icon,
      );
    }).toList();
  }
}

/// 转盘扇形绘制器。
class _WheelPainter extends CustomPainter {
  final List<WheelSegment> segments;

  _WheelPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final segmentAngle = 2 * pi / segments.length;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final startAngle = i * segmentAngle - pi / 2;
      final sweepAngle = segmentAngle;

      // 绘制扇形
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // 扇形边框
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      // 绘制文字
      final textAngle = startAngle + sweepAngle / 2;
      final textRadius = radius * 0.65;
      final textX = center.dx + textRadius * cos(textAngle);
      final textY = center.dy + textRadius * sin(textAngle);

      final textPainter = TextPainter(
        text: TextSpan(
          text: seg.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(color: Colors.black26, blurRadius: 2),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: radius * 0.5);
      textPainter.paint(
        canvas,
        Offset(textX - textPainter.width / 2, textY - textPainter.height / 2),
      );
    }

    // 外圈装饰
    final outerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, outerPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return segments != oldDelegate.segments;
  }
}

/// 转盘指针绘制器（三角形指示器）。
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // 阴影
    canvas.drawShadow(path, Colors.black38, 3, false);
    canvas.drawPath(path, paint);

    // 白色边框
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

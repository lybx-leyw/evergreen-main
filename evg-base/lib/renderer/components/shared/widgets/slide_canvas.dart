/// 幻灯片画布——单张幻灯片渲染。
///
/// 公开类：[SlideCanvas]
import 'package:flutter/material.dart';
import 'models.dart';

/// 单张幻灯片。
///
/// 读取 [PresentationOptions] 中的 layouts/transitions/animations。
class SlideCanvas extends StatelessWidget {
  final SlideData? slide;
  final List<String> layouts;
  final bool transitions;
  final bool animations;

  const SlideCanvas({
    super.key,
    this.slide,
    this.layouts = const [],
    this.transitions = false,
    this.animations = false,
  });

  @override
  Widget build(BuildContext context) {
    if (slide == null) {
      return Center(
        child: Text(
          '无幻灯片',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                slide!.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                textAlign: TextAlign.center,
              ),
              if (slide!.content != null) ...[
                const SizedBox(height: 16),
                Text(
                  slide!.content!,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.black54,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

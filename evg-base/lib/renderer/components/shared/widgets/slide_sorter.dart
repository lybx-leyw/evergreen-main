/// 幻灯片排序器——缩略图列表。
///
/// 公开类：[SlideSorter]
import 'package:flutter/material.dart';
import 'models.dart';

/// 幻灯片缩略图排序列表。
class SlideSorter extends StatelessWidget {
  final List<SlideData> slides;
  final int activeIndex;
  final ValueChanged<int>? onSlideSelected;

  const SlideSorter({
    super.key,
    required this.slides,
    this.activeIndex = 0,
    this.onSlideSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '幻灯片',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: slides.length,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (context, index) {
                final slide = slides[index];
                final isActive = index == activeIndex;
                return GestureDetector(
                  onTap: () => onSlideSelected?.call(index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: isActive ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

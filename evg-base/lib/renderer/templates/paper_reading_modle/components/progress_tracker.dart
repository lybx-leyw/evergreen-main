/// 进度追踪组件 — 论文阅读覆盖率进度条。
library;

import 'package:flutter/material.dart';

class ProgressTracker extends StatelessWidget {
  final double progress;
  final String label;

  const ProgressTracker({
    super.key,
    required this.progress,
    this.label = '阅读进度',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8B6914),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A2C00),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor:
                const Color(0xFF8B6914).withAlpha(30),
            valueColor: const AlwaysStoppedAnimation(
                Color(0xFF8B6914)),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

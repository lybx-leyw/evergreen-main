/// 标签卡片 — 探索标签视图中展示标签覆盖情况。
library;

import 'package:flutter/material.dart';
import '../paper_reading_models.dart';

class TagCard extends StatelessWidget {
  final SectionCategory category;
  final String label;
  final String description;
  final int segmentCount;
  final double progress;
  final Color color;
  final VoidCallback? onTap;

  const TagCard({
    super.key,
    required this.category,
    required this.label,
    required this.description,
    required this.segmentCount,
    required this.progress,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withAlpha(30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withAlpha(50),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D1B00),
                      ),
                    ),
                  ),
                  if (progress >= 1.0)
                    Icon(Icons.check_circle,
                        size: 18, color: const Color(0xFF50B86C))
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    '$segmentCount 个段落',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 80,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor:
                            color.withAlpha(25),
                        valueColor:
                            AlwaysStoppedAnimation(color),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 技法标题卡片 — 书本中每页展示的技法/论文卡片。
library;

import 'package:flutter/material.dart';

class TechniqueTitleCard extends StatelessWidget {
  final String name;
  final String fullName;
  final String description;
  final int variantCount;
  final bool isLeft;
  final bool isPaper;
  final VoidCallback? onTap;

  const TechniqueTitleCard({
    super.key,
    required this.name,
    required this.fullName,
    required this.description,
    required this.variantCount,
    this.isLeft = true,
    this.isPaper = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final margin = EdgeInsets.only(
      left: isLeft ? 0 : 16,
      right: isLeft ? 16 : 0,
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF8B6914).withAlpha(40),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B6914).withAlpha(20),
            blurRadius: 8,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: const Color(0xFF8B6914).withAlpha(30),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D1B00),
                    letterSpacing: 2,
                    height: 1.2,
                  ),
                ),
                if (fullName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    fullName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 20),
                if (isPaper)
                  Text(
                    '$variantCount 个段落',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBB9944),
                      letterSpacing: 1,
                    ),
                  )
                else ...[
                  Text(
                    '$variantCount 篇论文',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBB9944),
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '🌟 探索星空',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFBB9944),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 笔记本封面组件。
///
/// 棕色皮面（创新技法本）/ 紫色布面（综述本），带书脊立体感。
library;

import 'package:flutter/material.dart';
import '../paper_reading_models.dart';

class NotebookCover extends StatelessWidget {
  final NotebookType type;

  const NotebookCover({
    super.key,
    required this.type,
  });

  bool get isInnovation => type == NotebookType.innovation;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        isInnovation ? const Color(0xFF5C3A1E) : const Color(0xFF3E2A4F);
    final spineColor =
        isInnovation ? const Color(0xFF3E2510) : const Color(0xFF2A1A38);
    final gold = const Color(0xFFD4A853);

    return Stack(
      children: [
        // 书体
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(180),
                  blurRadius: 20,
                  offset: const Offset(4, 6),
                ),
              ],
            ),
          ),
        ),
        // 书脊 (左侧)
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: Container(
            decoration: BoxDecoration(
              color: spineColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  offset: const Offset(2, 0),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  isInnovation ? '创新技法' : '综述文献',
                  style: TextStyle(
                    color: gold.withAlpha(200),
                    fontSize: 10,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 主封面区域 (书脊右侧)
        Positioned(
          left: 24,
          right: 0,
          top: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  baseColor.withAlpha(230),
                  baseColor,
                  baseColor.withAlpha(220),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
            ),
          ),
        ),
        // 装饰边框
        Positioned(
          left: 38,
          right: 12,
          top: 16,
          bottom: 16,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: gold.withAlpha(80),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 标题
        Positioned(
          left: 38,
          right: 12,
          top: 0,
          bottom: 0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isInnovation
                    ? Icons.auto_fix_high
                    : Icons.library_books,
                color: gold.withAlpha(204),
                size: 36,
              ),
              const SizedBox(height: 16),
              Text(
                isInnovation ? '创新技法' : '综述文献',
                style: TextStyle(
                  color: gold,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isInnovation ? 'Notebook of Innovations' : 'Survey Collection',
                style: TextStyle(
                  color: gold.withAlpha(153),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

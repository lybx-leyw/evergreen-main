/// 书架视图 — 两本笔记本封面。
///
/// 用户在此选择进入创新技法本或综述本。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';
import '../components/notebook_cover.dart';

class BookshelfView extends ConsumerWidget {
  const BookshelfView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('论文阅读'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white70,
        elevation: 0,
      ),
      body: Center(
        child: isNarrow
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNotebookRow(
                      context, ref, colors, size, isNarrow),
                  const SizedBox(height: 32),
                  _buildSurveyNotebook(
                      context, ref, colors, size, isNarrow),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildNotebookRow(
                      context, ref, colors, size, isNarrow),
                  const SizedBox(width: 48),
                  _buildSurveyNotebook(
                      context, ref, colors, size, isNarrow),
                ],
              ),
      ),
    );
  }

  Widget _buildNotebookRow(BuildContext context, WidgetRef ref,
      ColorScheme colors, Size size, bool isNarrow) {
    return GestureDetector(
      onTap: () {
        ref
            .read(currentNotebookTypeProvider.notifier)
            .state = NotebookType.innovation;
        pushView(ref, PaperReadingViewType.bookPages);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: isNarrow ? size.width * 0.7 : 220,
          height: isNarrow ? 260 : 310,
          child: const NotebookCover(
            type: NotebookType.innovation,
          ),
        ),
      ),
    );
  }

  Widget _buildSurveyNotebook(BuildContext context, WidgetRef ref,
      ColorScheme colors, Size size, bool isNarrow) {
    return GestureDetector(
      onTap: () {
        ref
            .read(currentNotebookTypeProvider.notifier)
            .state = NotebookType.survey;
        pushView(ref, PaperReadingViewType.bookPages);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: isNarrow ? size.width * 0.7 : 220,
          height: isNarrow ? 260 : 310,
          child: const NotebookCover(
            type: NotebookType.survey,
          ),
        ),
      ),
    );
  }
}

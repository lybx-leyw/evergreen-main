/// 论文阅读模板 — 根视图。
///
/// 使用自定义视图导航栈（非 Navigator），管理 5 级视图层级：
/// bookshelf → bookPages → starfield → explorationTags → reading。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'paper_reading_models.dart';
import 'paper_reading_state.dart';
import 'services/book_persistence.dart';
import 'screens/bookshelf_view.dart';
import 'screens/book_pages_view.dart';
import 'screens/starfield_view.dart';
import 'screens/exploration_tags_view.dart';
import 'screens/reading_view.dart';

class PaperReadingView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;

  const PaperReadingView({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  ConsumerState<PaperReadingView> createState() =>
      _PaperReadingViewState();
}

class _PaperReadingViewState
    extends ConsumerState<PaperReadingView> {
  @override
  void initState() {
    super.initState();
    _loadNotebooks();
  }

  Future<void> _loadNotebooks() async {
    try {
      final innovation = await BookPersistence.loadNotebook(NotebookType.innovation);
      final survey = await BookPersistence.loadNotebook(NotebookType.survey);
      ref.read(innovationNotebookProvider.notifier).state = innovation;
      ref.read(surveyNotebookProvider.notifier).state = survey;

      // 恢复 V3 章节+全文数据（paperId → chapters / fullText）
      ref.read(chaptersProvider.notifier).state = {
        ...innovation.chaptersData,
        ...survey.chaptersData,
      };
      ref.read(fullTextProvider.notifier).state = {
        ...innovation.fullTextsData,
        ...survey.fullTextsData,
      };

      debugPrint('[PaperReading] loaded: innovation=${innovation.techniques.length} techniques'
          ', survey=${survey.papers.length} papers'
          ', chapters=${ref.read(chaptersProvider).length} papers'
          ', fullTexts=${ref.read(fullTextProvider).length} papers');
    } catch (e) {
      debugPrint('[PaperReading] load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 自动保存（不崩溃）—— notebook 变更时同步保存 V3 章节/全文数据
    ref.listen(innovationNotebookProvider,
        (_, n) => BookPersistence.saveNotebook(
            n.copyWith(
                chaptersData: ref.read(chaptersProvider),
                fullTextsData: ref.read(fullTextProvider),
            )).catchError((_) {}));
    ref.listen(surveyNotebookProvider,
        (_, n) => BookPersistence.saveNotebook(
            n.copyWith(
                chaptersData: ref.read(chaptersProvider),
                fullTextsData: ref.read(fullTextProvider),
            )).catchError((_) {}));

    final view = ref.watch(currentViewProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: _buildView(view),
    );
  }

  Widget _buildView(PaperReadingViewType view) {
    final key = ValueKey(view);
    switch (view) {
      case PaperReadingViewType.bookshelf:
        return _BookshelfEntry(key: key);
      case PaperReadingViewType.bookPages:
        return _BookPagesEntry(key: key);
      case PaperReadingViewType.starfield:
        return _StarfieldEntry(key: key);
      case PaperReadingViewType.explorationTags:
        return _ExplorationTagsEntry(key: key);
      case PaperReadingViewType.reading:
        return _ReadingEntry(key: key);
    }
  }
}

/// 包装书架子视图。
class _BookshelfEntry extends StatelessWidget {
  const _BookshelfEntry({super.key});
  @override
  Widget build(BuildContext context) => const BookshelfView();
}

/// 包装书本翻页子视图。
class _BookPagesEntry extends StatelessWidget {
  const _BookPagesEntry({super.key});
  @override
  Widget build(BuildContext context) => const BookPagesView();
}

/// 包装星空子视图。
class _StarfieldEntry extends StatelessWidget {
  const _StarfieldEntry({super.key});
  @override
  Widget build(BuildContext context) => const StarfieldView();
}

/// 包装探索标签子视图。
class _ExplorationTagsEntry extends StatelessWidget {
  const _ExplorationTagsEntry({super.key});
  @override
  Widget build(BuildContext context) => const ExplorationTagsView();
}

/// 包装三栏阅读终端子视图。
class _ReadingEntry extends StatelessWidget {
  const _ReadingEntry({super.key});
  @override
  Widget build(BuildContext context) => const ReadingView();
}

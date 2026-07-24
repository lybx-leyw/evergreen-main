/// 论文阅读模板 V3 — Riverpod 状态管理（章节+段落导航）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'paper_reading_models.dart';

// ═══════════════ 笔记本 ═══════════════
final innovationNotebookProvider = StateProvider<NotebookData>((ref) => NotebookData(type: NotebookType.innovation));
final surveyNotebookProvider = StateProvider<NotebookData>((ref) => NotebookData(type: NotebookType.survey));
final currentNotebookTypeProvider = StateProvider<NotebookType?>((ref) => null);
final selectedTechniqueIndexProvider = StateProvider<int>((ref) => 0);
final currentBookPageProvider = StateProvider<int>((ref) => 0);

// ═══════════════ 导航 ═══════════════
final viewStackProvider = StateProvider<List<PaperReadingViewType>>((ref) => [PaperReadingViewType.bookshelf]);
final currentViewProvider = Provider<PaperReadingViewType>((ref) => ref.watch(viewStackProvider).last);

void pushView(WidgetRef ref, PaperReadingViewType v) {
  ref.read(viewStackProvider.notifier).state = [...ref.read(viewStackProvider), v];
}
void popView(WidgetRef ref) {
  final s = ref.read(viewStackProvider);
  if (s.length > 1) ref.read(viewStackProvider.notifier).state = s.sublist(0, s.length - 1);
}

// ═══════════════ 论文上下文 ═══════════════
final selectedPaperIdProvider = StateProvider<String?>((ref) => null);
final selectedExplorationTagProvider = StateProvider<String?>((ref) => null); // Now holds chapter title

// ═══════════════ V3：章节+段落 ═══════════════
/// paperId → List<ChapterModel>
final chaptersProvider = StateProvider<Map<String, List<ChapterModel>>>((ref) => {});

/// paperId → 全文
final fullTextProvider = StateProvider<Map<String, String>>((ref) => {});

/// 当前章节索引
final currentChapterIndexProvider = StateProvider<int>((ref) => 0);

/// 当前段落索引（在当前章节内）
final currentParagraphIndexProvider = StateProvider<int>((ref) => 0);

/// 获取当前论文的章节列表
List<ChapterModel> currentChapters(WidgetRef ref) {
  final paperId = ref.watch(selectedPaperIdProvider);
  if (paperId == null) return [];
  return ref.watch(chaptersProvider)[paperId] ?? [];
}

/// 获取当前选中的章节
ChapterModel? currentChapter(WidgetRef ref) {
  final chapters = currentChapters(ref);
  final idx = ref.watch(currentChapterIndexProvider);
  return (idx >= 0 && idx < chapters.length) ? chapters[idx] : null;
}

/// 获取当前选中的段落
ParagraphModel? currentParagraph(WidgetRef ref) {
  final chapter = currentChapter(ref);
  if (chapter == null) return null;
  final idx = ref.watch(currentParagraphIndexProvider);
  return (idx >= 0 && idx < chapter.paragraphs.length) ? chapter.paragraphs[idx] : null;
}

// ═══════════════ 导入状态 ═══════════════
final importStatusProvider = StateProvider<String>((ref) => '');
final importStatusMsgProvider = StateProvider<String>((ref) => '');

// ═══════════════ 草稿本 ═══════════════
final draftPagesProvider = StateProvider<List<DraftPage>>((ref) => [DraftPage(pageIndex: 0)]);
final currentDraftPageProvider = StateProvider<int>((ref) => 0);
final draftToolProvider = StateProvider<String>((ref) => 'pen');
final draftColorProvider = StateProvider<int>((ref) => 0xFF000000);
final draftLineWidthProvider = StateProvider<double>((ref) => 2.0);

// ═══════════════ 便利方法 ═══════════════
NotebookData currentNotebook(WidgetRef ref) {
  final type = ref.watch(currentNotebookTypeProvider);
  if (type == NotebookType.survey) return ref.watch(surveyNotebookProvider);
  return ref.watch(innovationNotebookProvider);
}

PaperRecord? selectedPaper(WidgetRef ref) {
  final paperId = ref.watch(selectedPaperIdProvider);
  if (paperId == null) return null;
  try { return currentNotebook(ref).papers.firstWhere((p) => p.id == paperId); }
  catch (_) { return null; }
}

TechniqueEntry? selectedTechnique(WidgetRef ref) {
  final notebook = currentNotebook(ref);
  final idx = ref.watch(selectedTechniqueIndexProvider);
  if (idx < 0 || idx >= notebook.techniques.length) return null;
  return notebook.techniques[idx];
}

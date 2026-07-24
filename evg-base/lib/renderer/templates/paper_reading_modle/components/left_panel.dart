/// 左栏 V3 — 章节导航 + 当前段落的原文+导语翻页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';

class LeftPanel extends ConsumerWidget {
  const LeftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = currentChapters(ref);
    final chapter = currentChapter(ref);
    final paragraph = currentParagraph(ref);
    final chapterIdx = ref.watch(currentChapterIndexProvider);
    final paraIdx = ref.watch(currentParagraphIndexProvider);

    return Container(
      color: const Color(0xFFFFF8E7),
      child: Column(children: [
        // 章节选择器
        _ChapterSelector(chapters: chapters, selected: chapterIdx, onSelect: (i) {
          ref.read(currentChapterIndexProvider.notifier).state = i;
          ref.read(currentParagraphIndexProvider.notifier).state = 0;
          ref.read(selectedExplorationTagProvider.notifier).state = chapters[i].title;
        }),
        // 当前段落
        Expanded(child: paragraph != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (chapter != null)
                    Text(chapter.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4A2C00))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFE8F0FE), borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF4A90D9).withAlpha(40))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('📖 ', style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(paragraph.guide, style: const TextStyle(fontSize: 13, color: Color(0xFF2D5A8C), height: 1.5))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(paragraph.content, style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF2D1B00))),
                ]),
              )
            : const Center(child: Text('未找到论文', style: TextStyle(color: Color(0xFFBB9944))))),
        // 段落翻页
        if (chapter != null && chapter.paragraphs.isNotEmpty)
          _ParaNav(current: paraIdx, total: chapter.paragraphs.length,
              onPrev: () { if (paraIdx > 0) ref.read(currentParagraphIndexProvider.notifier).state = paraIdx - 1; },
              onNext: () { if (paraIdx < chapter.paragraphs.length - 1) ref.read(currentParagraphIndexProvider.notifier).state = paraIdx + 1; }),
      ]),
    );
  }
}

class _ChapterSelector extends StatelessWidget {
  final List<ChapterModel> chapters; final int selected;
  final void Function(int) onSelect;
  const _ChapterSelector({required this.chapters, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: const Color(0xFFF5ECD7),
      child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: chapters.length,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (c, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: ChoiceChip(
            label: Text(chapters[i].title, style: TextStyle(fontSize: 11, color: i == selected ? Colors.white : const Color(0xFF4A2C00))),
            selected: i == selected,
            selectedColor: const Color(0xFF8B6914),
            backgroundColor: const Color(0xFFFFF8E7),
            onSelected: (_) => onSelect(i),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

class _ParaNav extends StatelessWidget {
  final int current, total;
  final VoidCallback onPrev, onNext;
  const _ParaNav({required this.current, required this.total, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    color: const Color(0xFFF0E8D5),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: current > 0 ? onPrev : null, color: const Color(0xFF8B6914)),
      Text('${current + 1} / $total', style: const TextStyle(fontSize: 12, color: Color(0xFF8B6914))),
      IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: current < total - 1 ? onNext : null, color: const Color(0xFF8B6914)),
    ]),
  );
}

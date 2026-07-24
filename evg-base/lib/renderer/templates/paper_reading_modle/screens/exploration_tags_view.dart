/// 探索标签 V3 — 显示章节列表，点击进入逐段阅读。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../paper_reading_models.dart';
import '../paper_reading_state.dart';

class ExplorationTagsView extends ConsumerWidget {
  const ExplorationTagsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = currentChapters(ref);
    final paper = selectedPaper(ref);

    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE0),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => popView(ref)),
        title: Text(paper?.title ?? '探索'),
        backgroundColor: const Color(0xFFFFF8E7), elevation: 1,
      ),
      body: chapters.isEmpty
          ? const Center(child: Text('未找到章节', style: TextStyle(color: Color(0xFFBB9944))))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: chapters.length,
              itemBuilder: (c, i) {
                final ch = chapters[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF8B6914))), backgroundColor: const Color(0xFFF5ECD7)),
                    title: Text(ch.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${ch.paragraphs.length} 段落', style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ref.read(currentChapterIndexProvider.notifier).state = i;
                      ref.read(currentParagraphIndexProvider.notifier).state = 0;
                      ref.read(selectedExplorationTagProvider.notifier).state = ch.title;
                      pushView(ref, PaperReadingViewType.reading);
                    },
                  ),
                );
              },
            ),
    );
  }
}

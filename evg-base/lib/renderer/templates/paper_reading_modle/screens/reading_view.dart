/// 三栏阅读终端 V3 — 左=原文段落, 中=译文, 右=草稿/AI答疑。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../paper_reading_state.dart';
import '../components/left_panel.dart';
import '../components/center_panel.dart';
import '../components/right_panel.dart';

class ReadingView extends ConsumerWidget {
  const ReadingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = selectedPaper(ref);
    if (paper == null) {
      return Scaffold(appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => popView(ref)), title: const Text('阅读')),
          body: const Center(child: Text('未找到论文')));
    }
    final tag = ref.watch(selectedExplorationTagProvider) ?? '';
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF0EBE0),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => popView(ref)),
        title: Text(tag.isNotEmpty ? '阅读 · $tag' : '阅读', style: const TextStyle(fontSize: 15)),
        backgroundColor: const Color(0xFFFFF8E7), elevation: 1,
      ),
      body: isNarrow
          ? SingleChildScrollView(child: Column(children: [
              SizedBox(height: size.height * 0.45, child: const LeftPanel()),
              const Divider(height: 1), SizedBox(height: size.height * 0.4, child: const CenterPanel()),
              const Divider(height: 1), SizedBox(height: size.height * 0.5, child: RightPanel(paperId: paper.id)),
            ]))
          : LayoutBuilder(builder: (c, cs) => Row(children: [
              Expanded(child: const LeftPanel()),
              VerticalDivider(width: 1), Expanded(child: const CenterPanel()),
              VerticalDivider(width: 1), Expanded(child: RightPanel(paperId: paper.id)),
            ])),
    );
  }
}

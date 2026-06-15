import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wordpecker_provider.dart';
import '../models/fsrs_card.dart';

/// WordPecker — FSRS-5 vocabulary learning.
///
/// Ports the core UI from app/js/components/wordpecker.js.
/// Uses the FSRS models and services for real spaced repetition scheduling.
class WordPeckerScreen extends ConsumerStatefulWidget {
  const WordPeckerScreen({super.key});
  @override
  ConsumerState<WordPeckerScreen> createState() => _WordPeckerScreenState();
}

class _WordPeckerScreenState extends ConsumerState<WordPeckerScreen> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wordpeckerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WordPecker 背词'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '统计',
            onPressed: () => context.go('/wordpecker-stats'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(wordpeckerProvider.notifier).load(),
          ),
        ],
      ),
      body: Column(
        children: [
          // FSRS stats bar
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('待复习', state.fsrsStats.dueCount.toString()),
                  _stat('总词数', state.fsrsStats.totalCards.toString()),
                  _stat('已掌握', state.fsrsStats.masteredCount.toString()),
                  _stat('学习中', state.fsrsStats.learningCount.toString()),
                ],
              ),
            ),
          ),
          // Strategy selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'chew', label: Text('咀嚼')),
                ButtonSegment(value: 'onepass', label: Text('一遍过')),
                ButtonSegment(value: 'review', label: Text('复习')),
              ],
              selected: {state.currentStrategy},
              onSelectionChanged: (s) =>
                  ref.read(wordpeckerProvider.notifier).setStrategy(s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: 8),
          // Mode selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'copy', label: Text('抄写')),
                ButtonSegment(value: 'dictation', label: Text('听写')),
                ButtonSegment(value: 'flashcard', label: Text('闪卡')),
                ButtonSegment(value: 'fullflow', label: Text('全流程')),
              ],
              selected: {state.currentMode},
              onSelectionChanged: (s) =>
                  ref.read(wordpeckerProvider.notifier).setMode(s.first),
              style: ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          // Word basket input
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    decoration: const InputDecoration(
                      hintText: '添加单词到篮子...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (w) {
                      if (w.trim().isNotEmpty) {
                        ref.read(wordpeckerProvider.notifier).addToBasket(w.trim());
                        _addController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: state.wordBasket.isNotEmpty ? () {
                    ref.read(wordpeckerProvider.notifier).startPractice();
                  } : null,
                  child: const Text('开始'),
                ),
              ],
            ),
          ),
          // Word basket chips
          if (state.wordBasket.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: state.wordBasket
                    .map((w) => Chip(
                          label: Text(w),
                          onDeleted: () =>
                              ref.read(wordpeckerProvider.notifier).removeFromBasket(w),
                        ))
                    .toList(),
              ),
            ),
          // Batch size + Auto etymology toggles
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: state.batchSize,
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('5个')),
                    DropdownMenuItem(value: 10, child: Text('10个')),
                    DropdownMenuItem(value: 20, child: Text('20个')),
                    DropdownMenuItem(value: 50, child: Text('50个')),
                  ],
                  onChanged: (v) {
                    if (v != null) ref.read(wordpeckerProvider.notifier).setBatchSize(v);
                  },
                ),
                const Spacer(),
                FilterChip(
                  label: const Text('自动词源'),
                  selected: state.autoEtymology,
                  onSelected: (_) => ref.read(wordpeckerProvider.notifier).toggleAutoEtymology(),
                ),
              ],
            ),
          ),
          // Practice area or placeholder
          Expanded(
            child: state.isPracticing && state.currentWord != null
                ? _PracticeArea(word: state.currentWord!)
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.translate, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('添加单词到篮子后点击开始', style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 8),
                        Text('FSRS-5 间隔重复 · 4种词典 · 4种练习模式 · AI词源',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
          ),
          // Etymology panel (shown during practice)
          if (state.etymologyResult != null && state.isPracticing)
            SizedBox(
              height: 150,
              child: Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: Text(state.etymologyResult!, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey)),
      ],
    );
  }
}

class _PracticeArea extends StatelessWidget {
  final String word;
  const _PracticeArea({required this.word});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(word, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ratingButton(context, 'Again', FsrsCard.ratingAgain, Colors.red),
              const SizedBox(width: 12),
              _ratingButton(context, 'Hard', FsrsCard.ratingHard, Colors.orange),
              const SizedBox(width: 12),
              _ratingButton(context, 'Good', FsrsCard.ratingGood, Colors.green),
              const SizedBox(width: 12),
              _ratingButton(context, 'Easy', FsrsCard.ratingEasy, Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ratingButton(BuildContext context, String label, int rating, Color color) {
    return ElevatedButton(
      onPressed: () {
        // Grade and advance to next word
        // ref.read(wordpeckerProvider.notifier).gradeWord(rating);
      },
      style: ElevatedButton.styleFrom(backgroundColor: color),
      child: Text(label),
    );
  }
}

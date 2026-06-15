import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wordpecker_provider.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../core/config/theme.dart';

/// WordPecker statistics screen — shows FSRS learning data.
class WordPeckerStatsScreen extends ConsumerWidget {
  const WordPeckerStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wordpeckerProvider);
    final stats = state.fsrsStats;

    return Scaffold(
      appBar: AppBar(title: const Text('WordPecker 统计')),
      body: stats.totalCards == 0
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无学习数据', style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('开始背词后，统计数据将在这里显示',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Overview cards
                  Row(
                    children: [
                      _StatCard(
                          label: '待复习',
                          value: stats.dueCount.toString(),
                          color: AppTheme.warningOrange),
                      const SizedBox(width: 12),
                      _StatCard(
                          label: '总词数',
                          value: stats.totalCards.toString(),
                          color: AppTheme.zjuBlue),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatCard(
                          label: '已掌握',
                          value: stats.masteredCount.toString(),
                          color: AppTheme.successGreen),
                      const SizedBox(width: 12),
                      _StatCard(
                          label: '学习中',
                          value: stats.learningCount.toString(),
                          color: AppTheme.accentPurple),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Progress bars
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('掌握进度',
                              style:
                                  Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 16),
                          _ProgressRow(
                            label: '新词',
                            value: stats.totalCards -
                                stats.masteredCount -
                                stats.learningCount,
                            total: stats.totalCards,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          _ProgressRow(
                            label: '学习中',
                            value: stats.learningCount,
                            total: stats.totalCards,
                            color: AppTheme.accentPurple,
                          ),
                          const SizedBox(height: 12),
                          _ProgressRow(
                            label: '已掌握',
                            value: stats.masteredCount,
                            total: stats.totalCards,
                            color: AppTheme.successGreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 8),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;
  const _ProgressRow(
      {required this.label,
      required this.value,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? value / total : 0.0;
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
            minHeight: 8,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text('$value / $total',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

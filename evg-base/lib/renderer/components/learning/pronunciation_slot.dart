/// 发音练习槽位——从 [ComponentDescriptor.config] 读取 word / phonetic / score。
///
/// 展示单词卡、音标与发音/录音按钮（占位交互）。分数仅当 config 提供时显示，
/// 否则显示「未评测」。录音与评分接口预留（后续对接真实音频能力）。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 发音练习——`pronunciation` 组件。
class PronunciationSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const PronunciationSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final word = cfg['word'] as String?;
    final phonetic = cfg['phonetic'] as String?;
    final score = cfg['score'];
    final theme = Theme.of(context);

    if (word == null || word.isEmpty) {
      return _emptyState(context);
    }

    final scoreText = score == null ? '未评测' : score.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('发音练习',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(word,
                            style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700)),
                        if (phonetic != null && phonetic.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(phonetic,
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.volume_up),
                      label: const Text('播放'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.mic),
                      label: const Text('录音'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('对比'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('发音评分: ',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    Text(scoreText,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: score == null
                                ? theme.colorScheme.onSurfaceVariant
                                : Colors.green)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.record_voice_over,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('未配置单词 (config.word)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

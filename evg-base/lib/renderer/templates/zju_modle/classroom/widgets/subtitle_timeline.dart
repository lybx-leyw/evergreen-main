/// 字幕时间轴——按毫秒时间戳排序展示。
///
/// 适配自 `.refer_ui/widget/lib/features/classroom/widgets/subtitle_timeline.dart`。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/classroom/classroom_models.dart';

/// 字幕时间轴。
class SubtitleTimeline extends StatelessWidget {
  final List<Subtitle> subtitles;
  final void Function(Subtitle subtitle)? onTap;

  const SubtitleTimeline({
    super.key,
    this.subtitles = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (subtitles.isEmpty) return _emptyState(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text('字幕 (${subtitles.length} 条)',
              style: theme.textTheme.titleSmall),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: subtitles.length,
            itemBuilder: (ctx, i) {
              final sub = subtitles[i];
              return InkWell(
                onTap: onTap != null ? () => onTap!(sub) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_fmtMs(sub.startMs),
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(sub.text,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.closed_caption_off, size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('暂无字幕',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );

  static String _fmtMs(int ms) {
    final m = (ms / 60000).floor();
    final s = ((ms % 60000) / 1000).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

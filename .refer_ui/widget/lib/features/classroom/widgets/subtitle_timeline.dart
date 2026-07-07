import 'package:flutter/material.dart';
import '../../classroom/models/subtitle.dart';

/// Scrollable subtitle timeline with time stamps.
class SubtitleTimeline extends StatelessWidget {
  final List<Subtitle> subtitles;
  final ValueChanged<int>? onTap;

  const SubtitleTimeline({
    super.key,
    required this.subtitles,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (subtitles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.closed_caption_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('暂无字幕', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '字幕 (${subtitles.length} 条)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: subtitles.length,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemBuilder: (_, i) {
              final s = subtitles[i];
              final min = (s.startMs / 60000).floor();
              final sec = ((s.startMs % 60000) / 1000).floor();
              return InkWell(
                onTap: onTap != null ? () => onTap!(i) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.text,
                          style: const TextStyle(fontSize: 13, height: 1.3),
                        ),
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
}

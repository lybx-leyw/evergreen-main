/// 演讲者备注面板——演示文稿演讲者视图。
///
/// 公开类：[SpeakerNotesPanel]
import 'package:flutter/material.dart';

/// 演讲者备注面板。
///
/// 显示当前幻灯片的演讲者备注 + 计时器 + 下一张预览。
class SpeakerNotesPanel extends StatelessWidget {
  final String? notes;

  const SpeakerNotesPanel({super.key, this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // 备注区域
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '演讲者备注',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: TextField(
                    maxLines: null,
                    expands: true,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: notes ?? '添加备注...',
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 计时器 + 下一张
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '00:00',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '下一张: 2',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 修订栏——文档修订标记。
///
/// 公开类：[TrackChangesGutter]
import 'package:flutter/material.dart';

/// 修订标记栏。
///
/// 显示在文档编辑区右侧，标记增/删/改行。
class TrackChangesGutter extends StatelessWidget {
  const TrackChangesGutter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              '修订',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          // TODO: 实际修订标记
          const Center(
            child: Text('', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

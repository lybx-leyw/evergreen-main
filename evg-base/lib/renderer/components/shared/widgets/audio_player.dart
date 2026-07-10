/// 音频播放器——根据 [AudioOptions] 渲染音频播放控件。
///
/// 公开类：[AudioPlayer]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 音频播放组件。
///
/// 读取 [AudioOptions] 控制自动播放、循环等行为。
class AudioPlayer extends StatelessWidget {
  final MediaDescriptor media;
  final String? fileUrl;

  const AudioPlayer({
    super.key,
    required this.media,
    this.fileUrl,
  });

  @override
  Widget build(BuildContext context) {
    final controls = media.controls;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 播放按钮
          IconButton.filled(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              // TODO: 实际播放逻辑
            },
          ),
          const SizedBox(width: 12),

          // 进度条 + 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileUrl?.split('/').last ?? '音频播放',
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (controls)
                  Row(
                    children: [
                      const Text('00:00',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('00:00',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
              ],
            ),
          ),

          // 音量
          if (controls)
            const Icon(Icons.volume_up, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}

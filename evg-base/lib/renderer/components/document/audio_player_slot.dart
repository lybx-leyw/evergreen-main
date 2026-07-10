/// 音频播放器槽位——从 [ComponentDescriptor.config] 读取 src/title 渲染。
///
/// 复用 [AudioPlayer] 原子组件能力，但本项目直接读 config 避免依赖 MediaDescriptor。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 音频播放器——`audio-player` 组件。
class AudioPlayerSlot extends StatelessWidget {
  final ComponentDescriptor config;

  const AudioPlayerSlot({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final src = cfg['src'] as String?;
    final title = cfg['title'] as String? ?? src?.split('/').last ?? '音频播放';

    if (src == null || src.isEmpty) {
      return _emptyState(context, Icons.audiotrack, '未配置音频源 (config.src)');
    }

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton.filled(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              // 真实播放逻辑由宿主注入，这里仅占位交互
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(src,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(Icons.volume_up, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}

Widget _emptyState(BuildContext context, IconData icon, String msg) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(msg,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    ),
  );
}

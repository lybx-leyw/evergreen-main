/// 音频播放器槽位——从 [ComponentDescriptor.config] 读取 src/title 真实播放。
///
/// 基于 media_kit 的 [Player] 实现真实音频播放，支持插件相对路径解析。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:media_kit/media_kit.dart';

/// 音频播放器——`audio-player` 组件。
class AudioPlayerSlot extends StatefulWidget {
  final ComponentDescriptor config;
  final String moduleId;
  final String pluginsDir;

  const AudioPlayerSlot({
    super.key,
    required this.config,
    required this.moduleId,
    required this.pluginsDir,
  });

  @override
  State<AudioPlayerSlot> createState() => _AudioPlayerSlotState();
}

class _AudioPlayerSlotState extends State<AudioPlayerSlot> {
  Player? _player;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMsg;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String? get _resolvedSrc {
    final raw = widget.config.config['src'] as String?;
    return resolvePluginAssetPath(raw, widget.moduleId, widget.pluginsDir);
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final src = _resolvedSrc;
    if (src == null || src.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMsg = '未配置音频源';
      });
      return;
    }

    try {
      final player = Player();
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      await player.open(Media(src));
      if (mounted) {
        setState(() => _player = player);
      } else {
        player.dispose();
      }
    } catch (e) {
      debugPrint('[AudioPlayerSlot] 初始化失败: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = e.toString();
        });
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_hasError) return;
    await _ensurePlayer();
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final rawSrc = cfg['src'] as String?;
    final title = cfg['title'] as String?
        ?? rawSrc?.split('/').last
        ?? '音频播放';
    final src = _resolvedSrc;

    if (rawSrc == null || rawSrc.isEmpty) {
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
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _hasError ? null : _togglePlay,
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
                Text(
                  _hasError
                      ? '加载失败: ${_errorMsg ?? '未知错误'}'
                      : (src ?? rawSrc),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

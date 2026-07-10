/// 视频播放器——基于 media_kit（libmpv），跨平台硬件加速。
///
/// 公开类：[VideoPlayerWidget]
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 视频播放组件。
///
/// 支持 asset 路径（`assets/...`）、网络 URL、以及本地文件路径。
/// 基于 media_kit (libmpv)，在 Windows/macOS/Linux 上均有原生支持。
/// 自动播放 + 循环 + 静音，适合封面/预览场景。
class VideoPlayerWidget extends StatefulWidget {
  final MediaDescriptor media;
  final String? fileUrl;

  const VideoPlayerWidget({
    super.key,
    required this.media,
    this.fileUrl,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  Player? _player;
  VideoController? _videoController;
  bool _initialized = false;
  bool _hasError = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileUrl != widget.fileUrl) {
      _disposePlayer();
      _initPlayer();
    }
  }

  void _disposePlayer() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _initialized = false;
    _hasError = false;
    _errorMsg = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (!mounted) return;
    final rawUrl = widget.fileUrl;

    try {
      if (rawUrl == null || rawUrl.isEmpty) {
        if (mounted) {
          setState(() { _hasError = true; _errorMsg = '未指定视频路径'; });
        }
        return;
      }

      final player = Player();
      final videoController = VideoController(player);

      String mediaPath;

      if (rawUrl.startsWith('assets/')) {
        // Flutter asset → 复制到临时目录，media_kit 不支持 asset:// 协议
        mediaPath = await _copyAssetToTemp(rawUrl);
      } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        // 网络 URL
        mediaPath = rawUrl;
      } else if (rawUrl.startsWith('file://')) {
        // 本地文件 file:// URI
        mediaPath = rawUrl;
      } else {
        // 尝试作为本地文件路径
        final file = File(rawUrl);
        if (await file.exists()) {
          mediaPath = 'file:///${file.absolute.path.replaceAll('\\', '/')}';
        } else {
          // 最后尝试 asset
          mediaPath = await _copyAssetToTemp(rawUrl);
        }
      }

      if (!mounted) {
        player.dispose();
        return;
      }

      _player = player;
      _videoController = videoController;

      // 打开媒体 → 自动播放 + 循环 + 静音
      await player.open(Media(mediaPath));
      player.setPlaylistMode(PlaylistMode.loop);
      await player.setVolume(0.0);

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[VideoPlayerWidget] 初始化失败: $e');
      _player?.dispose();
      _player = null;
      _videoController = null;
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = e.toString();
        });
      }
    }
  }

  /// 将 Flutter asset 复制到临时目录，返回 file:// URI。
  Future<String> _copyAssetToTemp(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final fileName = assetPath.split('/').last;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return 'file:///${file.path.replaceAll('\\', '/')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 8),
              Text(
                _errorMsg ?? '加载失败',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final player = _player;
    final videoController = _videoController;
    if (player == null || videoController == null || !_initialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1677FF).withValues(alpha: 0.2),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Video(
          controller: videoController,
          fit: BoxFit.cover,
          controls: (state) => MaterialVideoControls(state),
        ),
      ),
    );
  }
}

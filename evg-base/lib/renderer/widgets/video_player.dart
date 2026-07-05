/// 视频播放器——根据 [VideoOptions] 渲染视频播放控件。
///
/// 公开类：[VideoPlayer]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 视频播放组件。
///
/// 读取 [VideoOptions] 控制自动播放、循环、静音等行为。
/// 基础实现使用占位 UI，后续可接入 video_player 包。
class VideoPlayer extends StatelessWidget {
  final MediaDescriptor media;
  final String? fileUrl;

  const VideoPlayer({
    super.key,
    required this.media,
    this.fileUrl,
  });

  @override
  Widget build(BuildContext context) {
    final videoOpts = media.video;
    final controls = media.controls;

    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 视频占位
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_circle_fill,
                size: 64,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 8),
              Text(
                fileUrl?.split('/').last ?? '视频播放',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),

          // 播放控件栏
          if (controls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_arrow,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.volume_up,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Icon(Icons.fullscreen,
                        color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

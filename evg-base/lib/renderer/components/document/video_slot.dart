/// 视频 slot——委托 [VideoPlayerWidget] 渲染。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/video_player.dart';

class VideoSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const VideoSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final media = MediaDescriptor.fromJson(config.config);
    final fileUrl = config.config['url'] as String?;
    return VideoPlayerWidget(media: media, fileUrl: fileUrl);
  }
}

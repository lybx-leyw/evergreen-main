/// 视频 slot——委托 [VideoPlayerWidget] 渲染。
///
/// 支持插件相对路径（如 `assets/video/xxx.mp4`）→ 解析为绝对文件系统路径。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/video_player.dart';

class VideoSlot extends StatelessWidget {
  final ComponentDescriptor config;
  final String moduleId;
  final String pluginsDir;

  const VideoSlot({
    required this.config,
    required this.moduleId,
    required this.pluginsDir,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaDescriptor.fromJson(config.config);
    final fileUrl = resolvePluginAssetPath(
      config.config['url'] as String?,
      moduleId,
      pluginsDir,
    );
    return VideoPlayerWidget(media: media, fileUrl: fileUrl);
  }
}

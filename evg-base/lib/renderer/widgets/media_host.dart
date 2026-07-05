/// 媒体宿主——根据文件后缀匹配分发到对应渲染器。
///
/// 公开类：[MediaHost]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../docs/render_rules.dart';
import 'video_player.dart';
import 'audio_player.dart';
import 'document_viewer.dart';
import 'image_viewer.dart';

/// 媒体渲染宿主。
///
/// 读取 [MediaDescriptor.accept] 进行后缀匹配，
/// 按 [MediaDescriptor.mode] 选择展示容器（inline/fullscreen/drawer/dropdown/fixed）。
class MediaHost extends StatelessWidget {
  final MediaDescriptor media;
  final String? filePath;
  final String? fileUrl;

  const MediaHost({
    super.key,
    required this.media,
    this.filePath,
    this.fileUrl,
  });

  @override
  Widget build(BuildContext context) {
    final ext = _extractExtension(filePath ?? fileUrl ?? '').toLowerCase();
    final renderer = _dispatchRenderer(ext);

    return _wrapMode(context, renderer);
  }

  /// 从文件路径提取后缀。
  String _extractExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot);
  }

  /// 根据后缀分发到子渲染器。
  Widget _dispatchRenderer(String ext) {
    // 视频
    if (_matchExt(ext, ['.mp4', '.webm', '.mov', '.avi', '.mkv'])) {
      return VideoPlayer(media: media, fileUrl: fileUrl);
    }
    // 音频
    if (_matchExt(ext, ['.mp3', '.wav', '.ogg', '.flac', '.aac', '.m4a'])) {
      return AudioPlayer(media: media, fileUrl: fileUrl);
    }
    // 图片
    if (_matchExt(ext, ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'])) {
      return ImageViewer(media: media, fileUrl: fileUrl);
    }
    // 文档
    if (_matchExt(ext, ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.md'])) {
      return DocumentViewer(media: media, fileUrl: fileUrl);
    }
    // 未知类型
    return const Center(
      child: Text('不支持的文件类型', style: TextStyle(color: Colors.grey)),
    );
  }

  bool _matchExt(String actual, List<String> candidates) {
    return candidates.any((c) => actual.endsWith(c.replaceFirst('*', '')));
  }

  /// 按展示模式包裹渲染器。
  Widget _wrapMode(BuildContext context, Widget renderer) {
    return switch (media.mode) {
      'fullscreen' => Scaffold(
          appBar: AppBar(
            title: Text(filePath?.split('/').last ?? ''),
          ),
          body: renderer,
        ),
      'fixed' => SizedBox(
          width: MediaFixedRules.videoWidth,
          height: MediaFixedRules.videoHeight,
          child: renderer,
        ),
      'drawer' => _buildDrawer(context, renderer),
      'dropdown' => _buildDropdown(context, renderer),
      _ => renderer, // 'inline' + 未知
    };
  }

  Widget _buildDrawer(BuildContext context, Widget renderer) {
    // 使用 showBottomSheet / Drawer 需要 Scaffold 上下文，
    // 此处返回占位按钮，实际打开由父组件处理。
    return ElevatedButton.icon(
      icon: const Icon(Icons.open_in_new),
      label: Text('打开 ${_mediaTypeLabel()}'),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: renderer,
          ),
        );
      },
    );
  }

  Widget _buildDropdown(BuildContext context, Widget renderer) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.arrow_drop_down),
      label: Text('展开 ${_mediaTypeLabel()}'),
      onPressed: () {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: renderer,
            ),
          ),
        );
      },
    );
  }

  String _mediaTypeLabel() {
    final ext = _extractExtension(filePath ?? '');
    if (['.mp4', '.webm', '.mov'].contains(ext)) return '视频';
    if (['.mp3', '.wav', '.ogg'].contains(ext)) return '音频';
    if (['.jpg', '.png', '.gif'].contains(ext)) return '图片';
    if (['.pdf', '.docx'].contains(ext)) return '文档';
    return '文件';
  }
}

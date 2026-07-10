/// 图片查看器——根据 [ImageOptions] 渲染图片展示。
///
/// 公开类：[ImageViewer]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 图片查看组件。
///
/// 读取 [ImageOptions] 控制缩放、旋转等行为。
class ImageViewer extends StatelessWidget {
  final MediaDescriptor media;
  final String? fileUrl;

  const ImageViewer({
    super.key,
    required this.media,
    this.fileUrl,
  });

  @override
  Widget build(BuildContext context) {
    final imageOpts = media.image;
    final zoomable = imageOpts?.zoomable ?? true;

    if (zoomable) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 3.0,
        child: _buildContent(context),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    return Center(
      child: fileUrl != null
          ? Image.network(
              fileUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildPlaceholder(context),
            )
          : _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image,
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          '图片预览',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 图片画廊槽位——从 [ComponentDescriptor.config] 读取 images[] 渲染网格。
///
/// 支持插件相对路径（如 `assets/img/xxx.svg`）→ 解析为绝对文件系统路径，
/// SVG 用 flutter_svg，栅格图用 Image.file。
import 'dart:io';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 图片画廊——`image-gallery` 组件。
class ImageGallerySlot extends StatelessWidget {
  final ComponentDescriptor config;
  final String moduleId;
  final String pluginsDir;

  const ImageGallerySlot({
    super.key,
    required this.config,
    required this.moduleId,
    required this.pluginsDir,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final title = cfg['title'] as String? ?? '图片画廊';
    final images = (cfg['images'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600)),
        ),
        if (images.isEmpty)
          _emptyState(context)
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: images.length,
              itemBuilder: (ctx, i) {
                final raw = images[i];
                final item = raw is Map ? raw.cast<String, dynamic>() : null;
                final rawUrl = item?['url'] as String? ?? item?['src'] as String?;
                final url = resolvePluginAssetPath(rawUrl, moduleId, pluginsDir);
                final caption = item?['caption'] as String? ?? '';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: url != null && url.isNotEmpty
                            ? _buildImage(url)
                            : const Center(child: Icon(Icons.image, size: 40)),
                      ),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.svg')) {
      return SvgPicture.file(
        File(path),
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image, size: 40),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('未配置图片 (config.images[])',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

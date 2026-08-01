/// PPT 查看器——分页浏览 + 捏合缩放 + 保存下载。
///
/// 适配自 `.refer_ui/widget/lib/features/classroom/widgets/ppt_viewer.dart`。
/// 关键差异：图片路径通过外部注入的 [resolveAsset] 转换为绝对路径。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/classroom/classroom_models.dart';

/// 图片加载器签名：接收相对路径，返回字节（或 null 表示加载失败）。
typedef ImageLoader = Future<Uint8List?> Function(String imagePath);

/// PPT 幻灯片查看器。
class PptViewer extends StatefulWidget {
  final List<PptSlide> slides;
  final ImageLoader loadImage;
  final VoidCallback? onSaveCurrent;
  final VoidCallback? onSaveAll;

  const PptViewer({
    super.key,
    this.slides = const [],
    required this.loadImage,
    this.onSaveCurrent,
    this.onSaveAll,
  });

  @override
  State<PptViewer> createState() => _PptViewerState();
}

class _PptViewerState extends State<PptViewer> {
  int _current = 0;
  final Map<int, Uint8List?> _cache = {};
  final Map<int, String?> _errors = {};

  PptSlide? get _slide => widget.slides.isEmpty ? null : widget.slides[_current];

  Future<Uint8List?> _load(int idx) async {
    if (_cache.containsKey(idx)) return _cache[idx];
    if (_errors.containsKey(idx)) return null;
    try {
      final bytes = await widget.loadImage(widget.slides[idx].imageUrl);
      if (!mounted) return null;
      setState(() {
        if (bytes != null) {
          _cache[idx] = bytes;
        } else {
          _errors[idx] = '加载失败';
        }
      });
      return bytes;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _errors[idx] = e.toString());
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      return _emptyState(context);
    }
    final slide = _slide;
    if (slide == null) return _emptyState(context);
    final total = widget.slides.length;

    return Column(
      children: [
        // 顶部信息栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (slide.text != null && slide.text!.isNotEmpty)
                Expanded(
                  child: Text(slide.text!, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              Text('${_current + 1} / $total',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),
        // PPT 图片区域
        Expanded(
          child: FutureBuilder<Uint8List?>(
            future: _load(_current),
            builder: (ctx, snap) {
              final err = _errors[_current];
              if (err != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.broken_image, size: 48,
                          color: Colors.red),
                      const SizedBox(height: 8),
                      Text(err, style: Theme.of(ctx).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _errors.remove(_current));
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              final bytes = snap.data;
              if (bytes == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              );
            },
          ),
        ),
        // 底部导航栏
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一页',
                onPressed: _current > 0
                    ? () => setState(() => _current--)
                    : null,
              ),
              Text('${_current + 1} / $total',
                  style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一页',
                onPressed: _current < total - 1
                    ? () => setState(() => _current++)
                    : null,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: widget.onSaveCurrent,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存本页'),
              ),
              TextButton.icon(
                onPressed: widget.onSaveAll,
                icon: const Icon(Icons.save_alt, size: 16),
                label: const Text('保存全部'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow, size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('暂无 PPT',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

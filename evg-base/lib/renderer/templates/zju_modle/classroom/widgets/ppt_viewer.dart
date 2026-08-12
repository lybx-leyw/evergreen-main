/// PPT 幻灯片查看器（翻页 + 缩放 + 下载）。
///
/// B3-classroom（2026-08-12）自参考工程 `cp_evergreen_push/lib/features/
/// classroom/widgets/ppt_viewer.dart` 移植（`PptSlide` → `ZjuPptSlide`）。
/// [imageLoader] 可选——由外部提供带 SSO cookie 的下载函数（dio 直连二进制）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../shared/models/zju_ppt_slide.dart';

/// PPT 图片加载器签名（返回字节；null 表示加载失败）。
typedef ImageLoader = Future<Uint8List?> Function(String url);

/// 全屏 PPT 查看器：页指示 + 图片区（InteractiveViewer 缩放）+ 导航/下载条。
class PptViewer extends StatefulWidget {
  final List<ZjuPptSlide> slides;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final ImageLoader? imageLoader;
  final VoidCallback? onDownloadAll;
  final VoidCallback? onDownloadCurrent;

  const PptViewer({
    super.key,
    required this.slides,
    this.initialPage = 0,
    this.onPageChanged,
    this.imageLoader,
    this.onDownloadAll,
    this.onDownloadCurrent,
  });

  @override
  State<PptViewer> createState() => _PptViewerState();
}

class _PptViewerState extends State<PptViewer> {
  late int _currentPage;
  final Map<int, Uint8List?> _cache = {};
  final Map<int, String?> _errors = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.slides.isEmpty
        ? 0
        : widget.initialPage.clamp(0, widget.slides.length - 1);
    _loadImage(_currentPage);
  }

  @override
  void didUpdateWidget(PptViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage &&
        widget.slides.isNotEmpty) {
      _currentPage = widget.initialPage.clamp(0, widget.slides.length - 1);
      _loadImage(_currentPage);
    }
  }

  Future<void> _loadImage(int index) async {
    if (index < 0 || index >= widget.slides.length) return;
    if (_cache.containsKey(index)) return;

    setState(() => _loading = true);
    try {
      final bytes = await widget.imageLoader!(widget.slides[index].imageUrl);
      if (bytes != null) {
        _cache[index] = bytes;
        _errors.remove(index);
      } else {
        _errors[index] = '返回空数据';
      }
    } catch (e) {
      _errors[index] = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goTo(int page) {
    if (page < 0 || page >= widget.slides.length) return;
    setState(() => _currentPage = page);
    _loadImage(page);
    widget.onPageChanged?.call(page);
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) {
      return const Center(child: Text('暂无 PPT'));
    }

    final slide = slides[_currentPage];
    final imageBytes = _cache[_currentPage];
    final error = _errors[_currentPage];

    return Column(
      children: [
        // Page indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                slide.text ?? '',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${_currentPage + 1} / ${slides.length}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildImageArea(slide, imageBytes, error)),
        // Navigation bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _currentPage > 0 ? () => _goTo(_currentPage - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_currentPage + 1} / ${slides.length}'),
              IconButton(
                onPressed: _currentPage < slides.length - 1
                    ? () => _goTo(_currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              if (widget.onDownloadCurrent != null) ...[
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: widget.onDownloadCurrent,
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('保存当前页'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
              ],
              if (widget.onDownloadAll != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: widget.onDownloadAll,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('一键下载全部'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageArea(
      ZjuPptSlide slide, Uint8List? imageBytes, String? error) {
    if (imageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 64),
          ),
        ),
      );
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text('图片加载失败', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                _errors.remove(_currentPage);
                _cache.remove(_currentPage);
                _loadImage(_currentPage);
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('加载第 ${_currentPage + 1} 页...',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

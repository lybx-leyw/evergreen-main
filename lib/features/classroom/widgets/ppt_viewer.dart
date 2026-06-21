import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../classroom/models/ppt_slide.dart';

/// Full-screen PPT slide viewer with pinch-to-zoom and page navigation.
///
/// [imageLoader] is optional — if provided, it overrides the internal Dio
/// downloader.  Pass the shared Dio's download method to reuse session cookies.
typedef ImageLoader = Future<Uint8List?> Function(String url);

class PptViewer extends StatefulWidget {
  final List<PptSlide> slides;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final ImageLoader? imageLoader;

  const PptViewer({
    super.key,
    required this.slides,
    this.initialPage = 0,
    this.onPageChanged,
    this.imageLoader,
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
    _currentPage = widget.initialPage.clamp(0, widget.slides.length - 1);
    _loadImage(_currentPage);
  }

  @override
  void didUpdateWidget(PptViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage) {
      _currentPage = widget.initialPage.clamp(0, widget.slides.length - 1);
      _loadImage(_currentPage);
    }
  }

  Future<void> _loadImage(int index) async {
    if (index < 0 || index >= widget.slides.length) return;
    if (_cache.containsKey(index)) return; // already cached or attempted

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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Image area
        Expanded(
          child: _buildImageArea(slide, imageBytes, error),
        ),

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
                onPressed: _currentPage > 0 ? () => _goTo(_currentPage - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${_currentPage + 1} / ${slides.length}'),
              IconButton(
                onPressed: _currentPage < slides.length - 1
                    ? () => _goTo(_currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageArea(
      PptSlide slide, Uint8List? imageBytes, String? error) {
    if (imageBytes != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64),
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

    // Loading
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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// 内嵌 PDF 预览组件——使用 pdfrx 渲染页面为图片显示。
class PdfPreviewWidget extends StatefulWidget {
  final String pdfPath;
  final double height;

  const PdfPreviewWidget({
    super.key,
    required this.pdfPath,
    this.height = 300,
  });

  @override
  State<PdfPreviewWidget> createState() => _PdfPreviewWidgetState();
}

class _PdfPreviewWidgetState extends State<PdfPreviewWidget> {
  PdfDocument? _doc;
  int _currentPage = 1;
  int _totalPages = 0;
  ui.Image? _pageImage;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final file = File(widget.pdfPath);
      if (!await file.exists()) {
        setState(() {
          _error = '文件不存在';
          _loading = false;
        });
        return;
      }
      final doc = await PdfDocument.openFile(widget.pdfPath);
      setState(() {
        _doc = doc;
        _totalPages = doc.pages.length;
      });
      await _renderPage(1);
    } catch (e) {
      setState(() {
        _error = '无法打开 PDF: $e';
        _loading = false;
      });
    }
  }

  Future<void> _renderPage(int pageNum) async {
    if (_doc == null) return;
    setState(() => _loading = true);

    try {
      final page = _doc!.pages[pageNum - 1];
      const width = 600;
      final ratio = page.width / page.height;
      final height = (width / ratio).round();
      final pdfImage = await page.render(width: width, height: height);
      if (pdfImage != null) {
        final img = await pdfImage.createImage();
        setState(() {
          _pageImage = img;
          _currentPage = pageNum;
          _loading = false;
        });
      } else {
        setState(() {
          _error = '页面渲染失败';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '渲染错误: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageImage?.dispose();
    _doc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_loading && _pageImage == null) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        Expanded(
          child: _pageImage != null
              ? Center(
                  child: RawImage(
                    image: _pageImage,
                    fit: BoxFit.contain,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (_totalPages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _currentPage > 1
                      ? () => _renderPage(_currentPage - 1)
                      : null,
                ),
                Text('$_currentPage / $_totalPages',
                    style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _currentPage < _totalPages
                      ? () => _renderPage(_currentPage + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

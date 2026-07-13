/// PDF 预览原子组件（M3 `pdf-viewer`）。
///
/// 设计（遵循 M3 规则 R4/R5）：
/// - [url]：远程 PDF。Web 端直接 `openFile(url)`；IO 端下载到临时文件后 `openFile`。
/// - [path]：本地 asset 路径，经 `openAsset` 打开。
/// - 二者皆空 → 空态提示（R5），绝不白屏/崩溃。
/// - 加载失败由 `PdfView` 内部错误 UI 兜底（非白屏、非崩溃，R5 已满足）。
///
/// 资源生命周期：本组件为 [StatefulWidget]，[PdfController] 在 [initState]
/// 创建、[dispose] 释放——`PdfView` 自身**不会** dispose 传入的 controller，
/// 若每次 build 新建会泄漏其内部 PageController，故必须在此托管。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/empty_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

class PdfViewerWidget extends StatefulWidget {
  final String? url;
  final String? path;
  final String? title;
  final int initialPage;
  final bool showControls;

  const PdfViewerWidget({
    super.key,
    this.url,
    this.path,
    this.title,
    this.initialPage = 1,
    this.showControls = true,
  });

  @override
  State<PdfViewerWidget> createState() => _PdfViewerWidgetState();
}

class _PdfViewerWidgetState extends State<PdfViewerWidget> {
  PdfController? _controller;

  @override
  void initState() {
    super.initState();
    final doc = _resolveDocument();
    if (doc != null) {
      _controller = PdfController(
        document: doc,
        initialPage: widget.initialPage,
      );
    }
  }

  /// 解析 PDF 文档源；无法解析（无源）返回 null。
  Future<PdfDocument>? _resolveDocument() {
    if (widget.path != null && widget.path!.isNotEmpty) {
      return PdfDocument.openAsset(widget.path!);
    }
    if (widget.url != null && widget.url!.isNotEmpty) {
      if (kIsWeb) {
        return PdfDocument.openFile(widget.url!);
      }
      return _downloadThenOpen(widget.url!);
    }
    return null;
  }

  Future<PdfDocument> _downloadThenOpen(String url) async {
    final resp = await Dio().get<Uint8List>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data;
    if (bytes == null) throw Exception('PDF 下载为空');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/evg_pdf_${url.hashCode}.pdf');
    await file.writeAsBytes(bytes);
    return PdfDocument.openFile(file.path);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return const EmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: '未提供 PDF 地址',
        subtitle: '请在 config 中设置 url 或 path',
      );
    }
    final theme = Theme.of(context);
    return Column(
      children: [
        if (widget.showControls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.title ?? 'PDF 预览',
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        Expanded(child: PdfView(controller: _controller!)),
      ],
    );
  }
}

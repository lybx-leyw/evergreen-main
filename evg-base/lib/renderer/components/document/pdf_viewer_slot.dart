/// PDF 预览 slot——委托 [PdfViewerWidget] 渲染（M3 `pdf-viewer`）。
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/pdf_viewer.dart';
import 'package:flutter/material.dart';

class PdfViewerSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const PdfViewerSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    return PdfViewerWidget(
      url: cfg['url'] as String?,
      path: cfg['path'] as String?,
      title: cfg['title'] as String?,
      initialPage: (cfg['page'] as num?)?.toInt() ?? 1,
      showControls: cfg['controls'] as bool? ?? true,
    );
  }
}

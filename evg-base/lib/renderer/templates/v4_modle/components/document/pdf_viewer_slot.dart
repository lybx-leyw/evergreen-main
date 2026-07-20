/// PDF 预览 slot——委托 [PdfViewerWidget] 渲染（M3 `pdf-viewer`）。
///
/// 支持两种路径模式：
/// - 绝对文件系统路径 → 原样传递，由 [PdfViewerWidget] 以 `openFile` 打开。
/// - 相对路径（如 `assets/doc/xxx.pdf`）→ 解析为插件目录下的绝对路径：
///   `$pluginsDir/$moduleId/$relativePath`。
library;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/pdf_viewer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PdfViewerSlot extends StatelessWidget {
  final ComponentDescriptor config;
  final String moduleId;
  final String pluginsDir;
  const PdfViewerSlot({
    required this.config,
    required this.moduleId,
    required this.pluginsDir,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    return PdfViewerWidget(
      url: cfg['url'] as String?,
      path: _resolvePath(cfg['path'] as String?),
      title: cfg['title'] as String?,
      initialPage: (cfg['page'] as num?)?.toInt() ?? 1,
      showControls: cfg['controls'] as bool? ?? true,
    );
  }

  String? _resolvePath(String? raw) {
    final resolved = resolvePluginAssetPath(raw, moduleId, pluginsDir);
    debugPrint('[PdfViewerSlot] 📄 resolved: "$raw" → "$resolved"');
    return resolved;
  }
}

/// vision 插件 PDF 预拆分（Task R3-6）——安卓 pymupdf 平替。
///
/// 背景：Chaquopy Android 索引无 pymupdf wheel（2026-08 CI 验证
/// `No matching distribution found for pymupdf`），python 侧无法在安卓拆分
/// PDF；Android 系统内置 `android.graphics.pdf.PdfRenderer`（API 21+，零依赖）
/// 在 Kotlin 侧逐页渲染 PNG。
///
/// 本服务在 Agent 调 vision(file_path=*.pdf) 时先行拆分（**仅安卓**）：
///   1. 经 MethodChannel(`evergreen/pdf`).renderPdfToPngs 让 Kotlin 侧
///      PdfRenderer 把每页渲染为 PNG（150dpi，最长边 4096px 封顶防 OOM），
///      写入 `Directory.systemTemp/evergreen_vision_pdf/<时间戳>/`（安卓 =
///      app cache，OS 自动回收）；
///   2. 把页图片目录以新增 `pages_dir` 参数注入 stdin JSON → vision.py 按页读取，
///      跳过 fitz。
///
/// 失败语义（fail-open）：任何失败（MissingPluginException=旧 APK / 渲染异常 /
/// 0 页）→ 返回 null，调用方原参透传，vision.py 内部兜底（桌面 fitz / 安卓
/// 降级提示）——绝不引入新的崩溃路径。桌面（Platform.isAndroid=false）恒不拆分，
/// 桌面行为零变化。
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// PdfRenderer 渲染通道（Kotlin 侧注册于 MainActivity.configureFlutterEngine，
/// 与既有 `evergreen/python` 通道同模式）。
const MethodChannel _pdfCh = MethodChannel('evergreen/pdf');

/// 预拆分产物：转换后的工具参数 + 页图片目录（供执行后清理）。
class PdfSplitOutcome {
  final Map<String, dynamic> args;
  final String? pagesDir;
  const PdfSplitOutcome(this.args, this.pagesDir);
}

/// vision 的 PDF 预拆分能力（manifest `"preprocess": "pdf_split"` 触发）。
class VisionPdfPreprocess {
  /// 尝试对 vision 工具参数做 PDF 预拆分。
  ///
  /// 返回 [PdfSplitOutcome] 表示已拆分（args 含 pages_dir）；返回 null 表示
  /// 无需/未能拆分（参数原样透传）。
  static Future<PdfSplitOutcome?> trySplitPdf(Map<String, dynamic> args) async {
    if (!Platform.isAndroid) return null; // 桌面：vision.py 内部 fitz 路径不变
    if (args['pages_dir'] != null) return null; // 已拆分过（幂等防重入）
    final mode = args['mode']?.toString() ?? '';
    if (mode == 'generate') return null; // 生图占位，无文件输入
    final path = args['file_path']?.toString() ?? '';
    if (path.isEmpty || !path.toLowerCase().endsWith('.pdf')) return null;
    final dir = await _splitToPagesDir(path);
    if (dir == null) return null; // fail-open
    return PdfSplitOutcome(
      {...args, 'pages_dir': dir},
      dir,
    );
  }

  /// 经 MethodChannel 调 Kotlin PdfRenderer 逐页渲染 PNG 到临时目录。
  ///
  /// 成功返回页图片目录绝对路径；失败返回 null（fail-open）。
  static Future<String?> _splitToPagesDir(String pdfPath) async {
    final root = Directory('${Directory.systemTemp.path}'
        '${Platform.pathSeparator}evergreen_vision_pdf');
    final dir = Directory('${root.path}'
        '${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}');
    try {
      final resp = await _pdfCh.invokeMethod<Map<dynamic, dynamic>>(
        'renderPdfToPngs',
        {
          'pdfPath': pdfPath,
          'outputDir': dir.path,
          // 对齐桌面 fitz dpi=150（PdfRenderer 原生 72dpi 点阵，缩放 150/72）。
          'dpi': 150.0,
        },
      );
      // 原生侧未实现（旧 APK）或返回 error → fail-open。
      if (resp == null || resp['error'] != null) return null;
      final pages = resp['pages'] as List?;
      if (pages == null || pages.isEmpty) return null;
      return dir.path;
    } catch (_) {
      // MissingPluginException / PlatformException（渲染失败等）→ fail-open。
      // 尽力清理可能已创建的空目录（cache 目录兜底，失败静默忽略）。
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
      return null;
    }
  }
}

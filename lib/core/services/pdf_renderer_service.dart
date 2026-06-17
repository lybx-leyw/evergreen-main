import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../log.dart';

/// PDF 页面渲染服务（使用 pdfrx PDFium FFI，全平台可用）。
///
/// 替代桌面端的 pdf_to_images.py Python 脚本。
class PdfRendererService {
  /// 将 PDF 拆分为 PNG 页面图片，返回临时文件路径列表。
  ///
  /// [dpi] 控制渲染分辨率（默认 150），影响 OCR 识别率和速度。
  Future<List<String>> pdfToImages(String pdfPath, {int dpi = 150}) async {
    final tempDir = await getTemporaryDirectory();
    final outDir =
        '${tempDir.path}${Platform.pathSeparator}ocr_pdf_${DateTime.now().millisecondsSinceEpoch}';
    await Directory(outDir).create(recursive: true);

    try {
      final doc = await PdfDocument.openFile(pdfPath);
      final pagePaths = <String>[];

      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final pageNum = i + 1;

        // dpi 150 at A4 width (~8.27in) ≈ 1240px
        final width = (8.27 * dpi).round();
        final height = (width * 1.414).round(); // A4 aspect ratio

        final pdfImage = await page.render(width: width, height: height);
        if (pdfImage == null) {
          Log().warn('pdfrx: page $pageNum rendered empty');
          continue;
        }

        // Convert PdfImage → ui.Image → PNG bytes
        final uiImage = await pdfImage.createImage();
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          Log().warn('pdfrx: page $pageNum byteData is null');
          continue;
        }

        final pagePath = p.join(outDir, 'page_$pageNum.png');
        await File(pagePath).writeAsBytes(byteData.buffer.asUint8List());
        pagePaths.add(pagePath);
        Log().debug('pdfrx: page $pageNum rendered',
            data: {'path': pagePath, 'bytes': byteData.lengthInBytes});
      }

      await doc.dispose();
      Log().info('pdfrx: rendered ${pagePaths.length}/${doc.pages.length} pages');
      return pagePaths;
    } catch (e) {
      Log().warn('pdfrx: render failed', error: e);
      try {
        await Directory(outDir).delete(recursive: true);
      } catch (_) {}
      return [];
    }
  }

  /// 清理临时目录（由调用方在 OCR 完成后调用）。
  Future<void> cleanTempDir(String dirPath) async {
    try {
      await Directory(dirPath).delete(recursive: true);
    } catch (e) {
      Log().warn('pdfrx: failed to clean temp dir',
          data: {'path': dirPath}, error: e);
    }
  }
}

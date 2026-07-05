import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../log.dart';
import 'mlkit_ocr_service.dart';
import 'ocr_pipeline.dart';
import 'pdf_renderer_service.dart';

/// Initialize mobile OCR (Android/iOS).
///
/// Registers ML Kit handlers with [OcrPipeline] via [registerMobileOcr].
/// Called once from main.dart at startup on mobile platforms.
void initMobileOcr(Dio dio) {
  final mlKit = MlKitOcrService();
  final pdfRenderer = PdfRendererService();

  registerMobileOcr(
    ocrFile: (String filePath) async {
      final ext = p.extension(filePath).toLowerCase();
      if (ext == '.pdf') {
        final pages = await pdfRenderer.pdfToImages(filePath);
        if (pages.isEmpty) return null;
        final result = await mlKit.recognizePages(pages);
        if (pages.isNotEmpty) {
          await pdfRenderer.cleanTempDir(p.dirname(pages.first));
        }
        return result;
      }
      return await mlKit.recognizeImage(filePath);
    },
    ocrUrl: (String imageUrl) async {
      try {
        final resp = await dio.get<List<int>>(
          imageUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (resp.data == null || resp.data!.isEmpty) return '';

        final suffix = p.extension(imageUrl).isNotEmpty
            ? p.extension(imageUrl)
            : '.jpg';
        final tmpFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_url_mlkit_${DateTime.now().millisecondsSinceEpoch}$suffix',
        );
        try {
          await tmpFile.writeAsBytes(resp.data!);
          final result = await mlKit.recognizeImage(tmpFile.path);
          return result ?? '';
        } finally {
          try {
            await tmpFile.delete();
          } catch (_) {}
        }
      } catch (e) {
        Log().warn('OcrMobile: ML Kit URL OCR failed', error: e);
        return '';
      }
    },
    dispose: () => mlKit.dispose(),
  );
}

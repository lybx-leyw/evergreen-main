import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../log.dart';
import '../utils/python_env.dart';
import 'deepseek_ocr_service.dart';

// Mobile OCR delegates — set by ocr_mobile.dart at startup on Android/iOS.
// Null on desktop → Tesseract Python subprocess is used instead.
@visibleForTesting
Future<String?> Function(String)? mobileOcrFileDelegate;
@visibleForTesting
Future<String> Function(String)? mobileOcrUrlDelegate;
@visibleForTesting
void Function()? mobileOcrDisposeDelegate;

/// Register mobile (Android/iOS) OCR handlers.
///
/// Called from [initMobileOcr] in `ocr_mobile.dart` at app startup.
/// On desktop these remain null and the Python Tesseract path is used.
void registerMobileOcr({
  required Future<String?> Function(String) ocrFile,
  required Future<String> Function(String) ocrUrl,
  required void Function() dispose,
}) {
  mobileOcrFileDelegate = ocrFile;
  mobileOcrUrlDelegate = ocrUrl;
  mobileOcrDisposeDelegate = dispose;
}

/// 两级 OCR 编排服务。
///
/// 封装 "Level 1 (DeepSeek-OCR 云端) → Level 2 (Tesseract 本地)" 的降级逻辑，
/// 所有 OCR 调用点统一走此入口，避免各 Feature 重复实现降级链。
///
/// 用法:
/// ```dart
/// final pipeline = OcrPipeline(dio);
/// final text = await pipeline.recognizeFile('/path/to/file.pdf');
/// ```
class OcrPipeline {
  final Dio _dio;
  final PythonEnv _pythonEnv;

  OcrPipeline(this._dio, [PythonEnv? pythonEnv])
      : _pythonEnv = pythonEnv ?? PythonEnv();

  // ── 公开 API ────────────────────────────────────────────────

  /// 对本地文件（图片或 PDF）运行 OCR。
  ///
  /// 优先使用 DeepSeek-OCR（若已配置 API Key），失败时降级到本地 Tesseract。
  /// 返回所有页面的合并文本，完全失败则返回 null。
  Future<String?> recognizeFile(String filePath) async {
    if (!File(filePath).existsSync()) {
      Log().warn('OcrPipeline: file not found', data: {'path': filePath});
      return null;
    }

    // Level 1: DeepSeek-OCR
    final apiKey = AppConfig.deepseekOcrApiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final result = await _deepseekOcr(filePath, apiKey);
        if (result != null && result.isNotEmpty) {
          Log().info('OcrPipeline: Level 1 (DeepSeek) succeeded',
              data: {'path': filePath, 'length': result.length});
          return result;
        }
      } catch (e) {
        Log().warn('OcrPipeline: Level 1 exception, falling back', error: e);
      }
    }

    // Level 2: Tesseract fallback
    Log().info('OcrPipeline: falling back to Level 2 (Tesseract)',
        data: {'path': filePath});
    return await _tesseractOcr(filePath);
  }

  /// 对远程图片 URL 运行 OCR。
  ///
  /// 下载图片后优先用 DeepSeek-OCR，失败降级到 Tesseract。
  /// 返回识别文本，失败返回空字符串（与 _ocrOneSlide 接口兼容）。
  Future<String> recognizeUrl(String imageUrl) async {
    // Level 1: download → DeepSeek-OCR
    final apiKey = AppConfig.deepseekOcrApiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final result = await _deepseekOcrUrl(imageUrl, apiKey);
        if (result != null && result.isNotEmpty) {
          Log().info('OcrPipeline: Level 1 (DeepSeek) URL succeeded',
              data: {'length': result.length});
          return result;
        }
      } catch (e) {
        Log().warn('OcrPipeline: Level 1 URL exception, falling back', error: e);
      }
    }

    // Level 2: Tesseract via ocr_slides.py
    return await _tesseractOcrUrl(imageUrl);
  }

  // ── Level 1: DeepSeek-OCR ───────────────────────────────────

  Future<String?> _deepseekOcr(String filePath, String apiKey) async {
    final ext = p.extension(filePath).toLowerCase();
    const imageExts = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.webp'];

    if (imageExts.contains(ext)) {
      final ocrService = DeepSeekOcrService(_dio, apiKey);
      return await ocrService.recognize(File(filePath));
    }

    if (ext == '.pdf') {
      return await _deepseekOcrPdf(filePath, apiKey);
    }

    Log().warn('OcrPipeline: unsupported file type for Level 1',
        data: {'ext': ext});
    return null;
  }

  /// DeepSeek-OCR for PDF: split → OCR each page → merge.
  Future<String?> _deepseekOcrPdf(String pdfPath, String apiKey) async {
    // 1. PDF → images
    final tmpDir = Directory.systemTemp;
    final outDir = '${tmpDir.path}${Platform.pathSeparator}ocr_ds_${DateTime.now().millisecondsSinceEpoch}';
    final pdfScript = p.join(Directory.current.path, 'scripts', 'pdf_to_images.py');

    if (!File(pdfScript).existsSync()) {
      Log().warn('OcrPipeline: pdf_to_images.py not found');
      return null;
    }

    final imgProc = await runOcrProcess('python', [
      pdfScript, '--path', pdfPath, '--output_dir', outDir, '--dpi', '150',
    ]).timeout(const Duration(seconds: 120));

    if (imgProc.exitCode != 0) {
      Log().warn('OcrPipeline: pdf_to_images failed',
          data: {'stderr': imgProc.stderr});
      return null;
    }

    List<Map<String, dynamic>> pages;
    try {
      final parsed = jsonDecode(imgProc.stdout as String) as Map<String, dynamic>;
      pages = (parsed['pages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log().warn('OcrPipeline: failed to parse pdf_to_images output', error: e);
      return null;
    }

    if (pages.isEmpty) {
      Log().warn('OcrPipeline: PDF produced no pages');
      return null;
    }

    // 2. OCR each page with DeepSeek
    final ocrService = DeepSeekOcrService(_dio, apiKey);
    final buf = StringBuffer();
    var allSucceeded = true;

    for (final page in pages) {
      final imgPath = page['path'] as String?;
      if (imgPath == null) continue;

      try {
        final text = await ocrService.recognize(File(imgPath));
        if (text != null && text.isNotEmpty) {
          if (pages.length > 1) {
            buf.writeln('--- 第 ${page['page']} 页 ---');
          }
          buf.writeln(text);
          buf.writeln();
        } else {
          allSucceeded = false;
          break;
        }
      } catch (_) {
        allSucceeded = false;
        break;
      }
    }

    // 3. Clean up temp images
    try {
      await Directory(outDir).delete(recursive: true);
    } catch (_) {}

    if (!allSucceeded || buf.isEmpty) return null;
    return buf.toString().trim();
  }

  Future<String?> _deepseekOcrUrl(String imageUrl, String apiKey) async {
    // Download image to temp file → OCR
    final resp = await _dio.get<List<int>>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    if (resp.data == null || resp.data!.isEmpty) return null;

    final suffix = p.extension(imageUrl).isNotEmpty
        ? p.extension(imageUrl)
        : '.jpg';
    final tmpFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ocr_url_${DateTime.now().millisecondsSinceEpoch}$suffix',
    );

    try {
      await tmpFile.writeAsBytes(resp.data!);
      final ocrService = DeepSeekOcrService(_dio, apiKey);
      return await ocrService.recognize(tmpFile);
    } finally {
      try { await tmpFile.delete(); } catch (_) {}
    }
  }

  // ── Level 2: Tesseract ──────────────────────────────────────

  Future<String?> _tesseractOcr(String filePath) async {
    // Android/iOS → ML Kit (registered via registerMobileOcr)
    if ((Platform.isAndroid || Platform.isIOS) && mobileOcrFileDelegate != null) {
      return await mobileOcrFileDelegate!(filePath);
    }

    // Desktop → Python subprocess (Tesseract)
    try {
      final envError = await _pythonEnv.ensureReady();
      if (envError != null) {
        Log().warn('OcrPipeline: Python deps not ready',
            data: {'error': envError});
        return null;
      }

      final script = p.join(Directory.current.path, 'scripts', 'ocr_file.py');
      if (!File(script).existsSync()) {
        Log().error('OcrPipeline: ocr_file.py missing',
            data: {'path': script});
        return null;
      }

      final result = await runOcrProcess(
        'python', [script, '--path', filePath],
      ).timeout(const Duration(seconds: 120));

      if (result.exitCode != 0) {
        Log().warn('OcrPipeline: Tesseract subprocess failed',
            data: {'exitCode': result.exitCode, 'stderr': result.stderr});
        return null;
      }

      return parsePageOutput(result.stdout as String? ?? '');
    } catch (e) {
      Log().warn('OcrPipeline: Tesseract exception', error: e);
      return null;
    }
  }

  Future<String> _tesseractOcrUrl(String imageUrl) async {
    // Android/iOS → ML Kit (registered via registerMobileOcr)
    if ((Platform.isAndroid || Platform.isIOS) && mobileOcrUrlDelegate != null) {
      return await mobileOcrUrlDelegate!(imageUrl);
    }

    // Desktop → Python subprocess (Tesseract / ocr_slides)
    try {
      final exeName = Platform.isWindows ? 'ocr_slides.exe' : 'ocr_slides';
      final candidates = <String>[
        p.join(Directory.current.path, 'scripts', 'dist', exeName),
        p.join(Directory.current.path, 'scripts', exeName),
      ];

      String? ocrExe;
      for (final c in candidates) {
        if (File(c).existsSync()) { ocrExe = c; break; }
      }

      // 回退到 python 脚本
      String? pythonScript;
      if (ocrExe == null) {
        final pyPath = p.join(Directory.current.path, 'scripts', 'ocr_slides.py');
        if (File(pyPath).existsSync()) pythonScript = pyPath;
        if (pythonScript == null) return '';
      }

      final result = await runOcrProcess(
        ocrExe ?? 'python',
        ocrExe != null
            ? ['--urls', imageUrl]
            : [pythonScript!, '--urls', imageUrl],
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode != 0) return '';

      final stdout = result.stdout as String? ?? '';
      final parsed = jsonDecode(stdout) as Map<String, dynamic>;

      if (parsed['error'] != null) return '';

      final results = parsed['results'] as List?;
      if (results == null || results.isEmpty) return '';
      return (results.first as Map)['text']?.toString() ?? '';
    } catch (e) {
      Log().warn('OcrPipeline: Tesseract URL OCR failed', error: e);
      return '';
    }
  }

  // ── 工具方法 ────────────────────────────────────────────────

  /// 解析 ocr_file.py 的 JSON 输出，合并为纯文本（公开以便测试）。
  static String? parsePageOutput(String stdout) {
    try {
      final parsed = jsonDecode(stdout) as Map<String, dynamic>;
      final pages = parsed['pages'] as List?;
      if (pages == null || pages.isEmpty) return null;

      final buf = StringBuffer();
      for (final page in pages) {
        final text = (page as Map)['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          if (pages.length > 1) {
            buf.writeln('--- 第 ${page['page']} 页 ---');
          }
          buf.writeln(text);
          buf.writeln();
        }
      }
      final merged = buf.toString().trim();
      return merged.isEmpty ? null : merged;
    } catch (e) {
      Log().warn('OcrPipeline: JSON parse failed', error: e);
      return null;
    }
  }
}

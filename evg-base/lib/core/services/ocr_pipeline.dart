/// OCR 管线——两级降级（DeepSeek-OCR 云端 → Tesseract 本地）+ 并行提速 + 就绪诊断。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../log.dart';
import '../utils/greenix_path.dart';
import '../utils/python_env.dart';
import 'deepseek_ocr_service.dart';

/// 两级 OCR 编排服务。
///
/// 封装 "Level 1 (DeepSeek-OCR 云端) → Level 2 (Tesseract 本地)" 的降级逻辑，
/// 所有 OCR 调用点统一走此入口，避免各 Feature 重复实现降级链。
///
/// 用法:
/// ```dart
/// final pipeline = OcrPipeline(dio, apiKey: 'sk-...');
/// final text = await pipeline.recognizeFile('/path/to/file.pdf');
/// ```
///
/// [apiKey] 缺省时回退环境变量 `DEEPSEEK_OCR_API_KEY`；两者都为空则直接走
/// Level 2 本地降级。桌面端建议由调用方从设置中枢（getSetting）读取后注入。
class OcrPipeline {
  final Dio _dio;
  final PythonEnv _pythonEnv;
  final String _apiKey;

  /// 并行 OCR 的默认并发度（桌面端算力充足，可调大）。
  int pageConcurrency = 4;

  OcrPipeline(this._dio, [PythonEnv? pythonEnv, String? apiKey])
      : _pythonEnv = pythonEnv ?? PythonEnv(),
        _apiKey = apiKey != null && apiKey.isNotEmpty
            ? apiKey
            : (Platform.environment['DEEPSEEK_OCR_API_KEY'] ?? '');

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
    if (_apiKey.isNotEmpty) {
      try {
        final result = await _deepseekOcr(filePath, _apiKey);
        if (_isUsableText(result)) {
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

  /// 对多个本地文件（图片或 PDF）并行 OCR。
  ///
  /// 桌面端算力充足，多 PDF 并行可显著提速。结果与 [paths] 一一对应，
  /// 单文件失败不影响其他文件（对应位置为 null）。
  Future<List<String?>> recognizeFiles(
    List<String> paths, {
    int concurrency = 2,
  }) {
    return _runParallel(paths, recognizeFile, concurrency: concurrency);
  }

  /// 对远程图片 URL 运行 OCR。
  ///
  /// 下载图片后优先用 DeepSeek-OCR，失败降级到 Tesseract。
  /// 返回识别文本，失败返回空字符串（与 _ocrOneSlide 接口兼容）。
  Future<String> recognizeUrl(String imageUrl) async {
    final parsed = Uri.tryParse(imageUrl);
    if (parsed == null || parsed.host.isEmpty || !{'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
      return '';
    }
    // Level 1: download → DeepSeek-OCR
    if (_apiKey.isNotEmpty) {
      try {
        final result = await _deepseekOcrUrl(imageUrl, _apiKey);
        if (_isUsableText(result)) {
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

  /// OCR 环境就绪诊断（电脑端优先）。
  ///
  /// 返回结构化报告：Python 可用性、脚本资源、OCR Key、Tesseract 可用性。
  /// 供 UI 展示与深寻 agents 的 `check_ocr_ready` 工具使用。
  Future<OcrReadinessReport> checkReadiness() async {
    final issues = <String>[];

    final pythonOk = (await resolvePythonExe()) != null;
    if (!pythonOk) issues.add('未找到 Python 解释器（配置 PYTHON_EXE 或安装 Python）');

    final pdfScriptOk =
        File(p.join(greenixScriptsDir, 'pdf_to_images.py')).existsSync();
    if (!pdfScriptOk) issues.add('缺少 pdf_to_images.py（脚本资源未释放）');

    final ocrFileOk =
        File(p.join(greenixScriptsDir, 'ocr_file.py')).existsSync();
    if (!ocrFileOk) issues.add('缺少 ocr_file.py（脚本资源未释放）');

    final keyConfigured = _apiKey.isNotEmpty;
    if (!keyConfigured) {
      issues.add('未配置 DEEPSEEK_OCR_API_KEY（将降级到本地 Tesseract）');
    }

    var tesseractOk = false;
    if (pythonOk) {
      tesseractOk = await _probeTesseract();
      if (!tesseractOk && !keyConfigured) {
        issues.add('Tesseract 未就绪且未配置 OCR Key——扫描版 PDF 将无法识别');
      }
    }

    return OcrReadinessReport(
      pythonAvailable: pythonOk,
      pdfScriptAvailable: pdfScriptOk,
      ocrFileScriptAvailable: ocrFileOk,
      deepSeekKeyConfigured: keyConfigured,
      tesseractAvailable: tesseractOk,
      issues: issues,
    );
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

  /// DeepSeek-OCR for PDF: split → OCR each page **in parallel** → merge。
  ///
  /// 桌面端算力充足，逐页并行识别显著提速；单页失败容忍跳过，
  /// 只要有任何一页识别成功即返回合并文本。
  Future<String?> _deepseekOcrPdf(String pdfPath, String apiKey) async {
    // 1. PDF → images
    final tmpDir = Directory.systemTemp;
    final outDir = '${tmpDir.path}${Platform.pathSeparator}ocr_ds_${DateTime.now().millisecondsSinceEpoch}';
    final pdfScript = p.join(greenixScriptsDir, 'pdf_to_images.py');

    if (!File(pdfScript).existsSync()) {
      Log().warn('OcrPipeline: pdf_to_images.py not found');
      return null;
    }

    late ProcessResult imgProc;
    try {
      imgProc = await runOcrProcess(await resolvePythonExe() ?? 'python', [
        pdfScript, '--path', pdfPath, '--output_dir', outDir, '--dpi', '150',
      ]).timeout(const Duration(seconds: 120));
    } catch (e) {
      try { await Directory(outDir).delete(recursive: true); } catch (_) {}
      Log().warn('OcrPipeline: PDF 转图片异常', error: e);
      return null;
    }

    if (imgProc.exitCode != 0) {
      Log().warn('OcrPipeline: pdf_to_images failed',
          data: {'stderr': imgProc.stderr});
      return null;
    }

    List<Map<String, dynamic>> pages;
    try {
      final parsed = jsonDecode(imgProc.stdout as String) as Map<String, dynamic>;
      final rawPages = parsed['pages'] as List? ?? const [];
      pages = rawPages.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    } catch (e) {
      Log().warn('OcrPipeline: failed to parse pdf_to_images output', error: e);
      try { await Directory(outDir).delete(recursive: true); } catch (_) {}
      return null;
    }

    if (pages.isEmpty) {
      Log().warn('OcrPipeline: PDF produced no pages');
      try { await Directory(outDir).delete(recursive: true); } catch (_) {}
      return null;
    }
    if (pages.length > 100) {
      Log().warn('OcrPipeline: PDF 页数超过 100，截断 OCR 任务', data: {'pages': pages.length});
      pages = pages.take(100).toList();
    }

    try {
      // 2. OCR each page with DeepSeek（并行）
      final ocrService = DeepSeekOcrService(_dio, apiKey);
      final texts = await _runParallel(pages, (page) async {
        final imgPath = page['path'] as String?;
        if (imgPath == null) return null;
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            final value = await ocrService.recognize(File(imgPath));
            if (value != null && value.isNotEmpty) return value;
          } catch (_) { if (attempt == 1) rethrow; }
        }
        return null;
      }, concurrency: pageConcurrency);

      // 3. Merge in original page order（单页失败容忍，跳过）
      final buf = StringBuffer();
      var succeeded = 0;
      for (var i = 0; i < pages.length; i++) {
        final text = texts[i];
        if (text == null || text.isEmpty) continue;
        succeeded++;
        if (pages.length > 1) buf.writeln('--- 第 ${pages[i]['page']} 页 ---');
        buf.writeln(text);
        buf.writeln();
      }
      if (succeeded == 0 || buf.isEmpty) return null;
      Log().info('OcrPipeline: Level 1 PDF OCR 完成', data: {'pages': pages.length, 'succeeded': succeeded});
      return buf.toString().trim();
    } finally {
      try { await Directory(outDir).delete(recursive: true); }
      catch (e) { Log().warn('OcrPipeline: 临时图片目录清理失败: $e', error: e); }
    }
  }

  Future<String?> _deepseekOcrUrl(String imageUrl, String apiKey) async {
    // Download image to temp file → OCR
    final resp = await _dio.get<List<int>>(
      imageUrl,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10)),
    );

    if (resp.data == null || resp.data!.isEmpty) return null;
    if (resp.data!.length > 20 * 1024 * 1024) {
      Log().warn('OcrPipeline: 远程图片超过 20MiB 上限');
      return null;
    }

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
      try {
        await tmpFile.delete();
      } catch (e) {
        Log().warn('OcrPipeline: 临时文件删除失败: $e', error: e);
      }
    }
  }

  // ── Level 2: Tesseract ──────────────────────────────────────

  Future<String?> _tesseractOcr(String filePath) async {
    // Python subprocess (Tesseract)
    try {
      final envError = await _pythonEnv.ensureReady();
      if (envError != null) {
        Log().warn('OcrPipeline: Python deps not ready',
            data: {'error': envError});
        return null;
      }

      final script = p.join(greenixScriptsDir, 'ocr_file.py');
      if (!File(script).existsSync()) {
        Log().error('OcrPipeline: ocr_file.py missing',
            data: {'path': script});
        return null;
      }

      final result = await runOcrProcess(
        await resolvePythonExe() ?? 'python', [script, '--path', filePath],
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

  /// 过滤 OCR 服务返回的空壳/错误页，避免把低质量结果当成成功缓存。
  bool _isUsableText(String? text) {
    if (text == null) return false;
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 8) return false;
    if (normalized.startsWith('{"error"') || normalized.startsWith('[error')) return false;
    return normalized.runes.length >= 8;
  }

  Future<String> _tesseractOcrUrl(String imageUrl) async {
    // Python subprocess (Tesseract / ocr_slides)
    try {
      final exeName = Platform.isWindows ? 'ocr_slides.exe' : 'ocr_slides';
      final candidates = <String>[
        p.join(greenixScriptsDir, 'dist', exeName),
        p.join(greenixScriptsDir, exeName),
      ];

      String? ocrExe;
      for (final c in candidates) {
        if (File(c).existsSync()) { ocrExe = c; break; }
      }

      // 回退到 python 脚本
      String? pythonScript;
      if (ocrExe == null) {
        final pyPath = p.join(greenixScriptsDir, 'ocr_slides.py');
        if (File(pyPath).existsSync()) pythonScript = pyPath;
        if (pythonScript == null) return '';
      }

      final result = await runOcrProcess(
        ocrExe ?? await resolvePythonExe() ?? 'python',
        ocrExe != null
            ? ['--urls', imageUrl]
            : [pythonScript!, '--urls', imageUrl],
      ).timeout(const Duration(seconds: 15));

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

  /// 有限并发并行执行：每个 item 跑 [task]，单任务异常 → null（不中断整体）。
  Future<List<String?>> _runParallel<T>(
    List<T> items,
    Future<String?> Function(T item) task, {
    int concurrency = 4,
  }) async {
    final results = List<String?>.filled(items.length, null);
    var next = 0;
    final n = concurrency.clamp(1, items.length.clamp(1, 8)).toInt();

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= items.length) return;
        try {
          results[i] = await task(items[i]);
        } catch (e) {
          Log().warn('OcrPipeline: 并行任务单条异常', error: e);
          results[i] = null;
        }
      }
    }

    await Future.wait(List.generate(n, (_) => worker()));
    return results;
  }

  /// 探测本地 Tesseract（pytesseract 绑定可用性）。
  Future<bool> _probeTesseract() async {
    try {
      final py = await resolvePythonExe();
      if (py == null) return false;
      final r = await runOcrProcess(py, [
        '-c',
        'import pytesseract; print(pytesseract.get_tesseract_version())',
      ]).timeout(const Duration(seconds: 15));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

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

// ═══════ OcrReadinessReport ═══════

/// OCR 环境就绪诊断结果。
class OcrReadinessReport {
  final bool pythonAvailable;
  final bool pdfScriptAvailable;
  final bool ocrFileScriptAvailable;
  final bool deepSeekKeyConfigured;
  final bool tesseractAvailable;

  /// 人类可读的问题列表（空 = 就绪）。
  final List<String> issues;

  const OcrReadinessReport({
    required this.pythonAvailable,
    required this.pdfScriptAvailable,
    required this.ocrFileScriptAvailable,
    required this.deepSeekKeyConfigured,
    required this.tesseractAvailable,
    required this.issues,
  });

  bool get ready => issues.isEmpty;

  /// 单行摘要（供 Agent 工具返回）。
  String summarize() {
    if (ready) return 'OCR 就绪（DeepSeek-OCR ${deepSeekKeyConfigured ? "已配置" : "未配置"}，Tesseract ${tesseractAvailable ? "可用" : "不可用"}）';
    return 'OCR 未就绪：${issues.join('；')}';
  }
}

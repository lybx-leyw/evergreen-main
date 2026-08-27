/// OCR 管线——两级降级（DeepSeek-OCR 云端 → Tesseract 本地）+ 并行提速 + 就绪诊断。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../log.dart';
import '../utils/greenix_path.dart';
import '../utils/python_env.dart';
import 'deepseek_ocr_service.dart';

/// Python 一次性执行器——OcrPipeline 的进程抽象注入点。
///
/// 安卓默认绑定 ChaquopyRunner 包装（[bindOcrPlatformRunOnce]，由应用层注入）；
/// 测试可经构造参数注入 mock。返回 stdout/stderr/exitCode 三元组（与
/// `RunResult` 同构——但 core 子包不可 import plugin_runner，其 flutter_stub
/// 缺 services.dart 会编译失败，故用回调解耦）。
typedef PythonRunOnce = Future<({String stdout, String stderr, int exitCode})> Function(
  String entry, List<String> args, {Duration? timeout, String? workingDirectory});

/// 平台默认执行器（安卓由应用层绑定 ChaquopyRunner 包装；桌面不绑定）。
PythonRunOnce? _boundPlatformRunOnce;

/// 绑定安卓平台默认 Python 执行器（ChaquopyRunner 包装）。
///
/// core 子包不可直接 import `plugin_runner.dart`（其 import
/// `package:flutter/services.dart`，而 `lib/core` 的 flutter_stub 缺
/// services.dart），故由可 import 的应用层（app_bootstrap）在启动时调用一次；
/// 桌面不绑定 → [OcrPipeline] 缺省走历史 `runOcrProcess` 子进程（零变化）。
void bindOcrPlatformRunOnce(PythonRunOnce fn) {
  _boundPlatformRunOnce = fn;
}

/// 缺省执行器：平台绑定优先（安卓），否则维持历史 `runOcrProcess` 子进程（桌面）。
Future<({String stdout, String stderr, int exitCode})> _defaultRunOnce(
  String entry, List<String> args, {Duration? timeout, String? workingDirectory}) async {
  final platform = _boundPlatformRunOnce;
  if (platform != null) {
    return platform(entry, args, timeout: timeout, workingDirectory: workingDirectory);
  }
  if (Platform.isAndroid) {
    // 未绑定（未走 AppBootstrap 的嵌入/测试场景）：返回可读失败而非子进程
    // UnsupportedError——调用方按 exitCode!=0 走降级文案。
    return (
      stdout: '',
      stderr: '[error: 安卓 OCR Python 执行器未绑定（应用层 bindOcrPlatformRunOnce 未调用）]',
      exitCode: 1,
    );
  }
  // 桌面：维持历史 runOcrProcess 子进程（零变化）。
  final py = (await PythonInterpreter.instance.resolve()).legacyExePath ?? 'python';
  final r = await runOcrProcess(py, [entry, ...args], workingDirectory: workingDirectory);
  return (stdout: r.stdout as String, stderr: r.stderr as String, exitCode: r.exitCode);
}

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
///
/// 安卓降级链：DeepSeek OCR（图片，网络 API 可用）→ Chaquopy 执行
/// `ocr_file.py`（需构建期打包 Pillow/pytesseract/tesseract，见
/// [checkReadiness] 平台化文案）。
class OcrPipeline {
  final Dio _dio;
  final PythonEnv _pythonEnv;
  final String _apiKey;
  final PythonRunOnce _pythonRunOnce;

  /// 测试注入：强制按安卓路径执行（默认取 [Platform.isAndroid]）。
  final bool? _forceAndroid;

  /// 并行 OCR 的默认并发度（桌面端算力充足，可调大）。
  int pageConcurrency = 4;

  OcrPipeline(this._dio,
      [PythonEnv? pythonEnv, String? apiKey, PythonRunOnce? pythonRunOnce, bool? forceAndroid])
      : _pythonEnv = pythonEnv ?? PythonEnv(),
        _pythonRunOnce = pythonRunOnce ?? _defaultRunOnce,
        _forceAndroid = forceAndroid,
        _apiKey = apiKey != null && apiKey.isNotEmpty
            ? apiKey
            : (Platform.environment['DEEPSEEK_OCR_API_KEY'] ?? '');

  /// 平台判定：安卓走 Chaquopy 进程内执行（[forceAndroid] 供测试注入）。
  bool get _isAndroid => _forceAndroid ?? Platform.isAndroid;

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
              data: {'path': filePath, 'length': result!.length});
          return result!;
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
              data: {'length': result!.length});
          return result!;
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

    final pythonOk = (await PythonInterpreter.instance.resolve()).isAvailable;
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
        if (_isAndroid) {
          // 平台化文案：安卓本地 OCR 需构建期打包（Pillow/pytesseract 经
          // chaquopy.pip，tesseract 引擎需原生集成），主路径是 DeepSeek 云端——
          // 避免继续误导「安装 Python / 安装 Tesseract」的桌面向指引。
          issues.add('安卓本地 OCR 需构建期打包 Pillow/pytesseract 与 tesseract 引擎，'
              '当前以 DeepSeek OCR 为主路径；建议配置 DEEPSEEK_OCR_API_KEY');
        } else {
          issues.add('Tesseract 未就绪且未配置 OCR Key——扫描版 PDF 将无法识别');
        }
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
    if (_isAndroid) {
      // 安卓：pdf_to_images.py 依赖 pdf2image（poppler pdftoppm），安卓无该
      // 二进制；即使经 Chaquopy 过桥仍失败。返回明确提示而非静默 null。
      // TODO(R3-3 中期，报告 §5.5)：chaquopy.pip 加装 pymupdf（fitz 纯 wheel，
      // Android 有支持）并新增 pdf_to_images_fitz.py（fitz 渲染 PDF→JPEG，
      // 无 poppler），Dart 侧按平台选脚本——本轮不做。
      Log().warn('OcrPipeline: 安卓 PDF OCR 暂不支持（缺 poppler 渲染）',
          data: {'path': pdfPath});
      return '安卓 PDF OCR 暂不支持（缺 poppler 渲染，建议上传图片或桌面端处理）';
    }

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
      imgProc = await runOcrProcess(
        (await PythonInterpreter.instance.resolve()).legacyExePath ?? 'python',
        [pdfScript, '--path', pdfPath, '--output_dir', outDir, '--dpi', '150'],
      ).timeout(const Duration(seconds: 120));
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
    if (_isAndroid) {
      return _tesseractOcrChaquopy(filePath);
    }
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
        (await PythonInterpreter.instance.resolve()).legacyExePath ?? 'python',
        [script, '--path', filePath],
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

  /// 安卓本地 OCR：跳过 `ensureReady`（无 pip/子进程，必失败），直接经
  /// [_pythonRunOnce]（ChaquopyRunner 进程内执行）跑 `ocr_file.py`。
  ///
  /// - exitCode==0 → 复用 [parsePageOutput] 解析 stdout JSON；
  /// - exitCode!=0 → 解析 stderr 的 JSON 错误（ocr_file.py 缺失依赖时输出
  ///   `{"error": "..."}`）→ 返回可读降级文案，不静默吞掉。
  Future<String?> _tesseractOcrChaquopy(String filePath) async {
    try {
      final script = p.join(greenixScriptsDir, 'ocr_file.py');
      if (!File(script).existsSync()) {
        Log().error('OcrPipeline: ocr_file.py missing', data: {'path': script});
        return null;
      }

      final res = await _pythonRunOnce(
        script,
        ['--path', filePath],
        timeout: const Duration(seconds: 120),
      );

      if (res.exitCode == 0) {
        return parsePageOutput(res.stdout);
      }

      Log().warn('OcrPipeline: 安卓本地 OCR 缺依赖',
          data: {'exitCode': res.exitCode, 'stderr': res.stderr});
      return _androidOcrDegradationMessage(res.stderr);
    } catch (e) {
      Log().warn('OcrPipeline: 安卓 OCR 异常', error: e);
      return _androidOcrDegradationMessage('');
    }
  }

  /// 安卓本地 OCR 缺依赖的可读降级文案：优先透出 `ocr_file.py` stderr 的
  /// JSON 错误（`{"error": "..."}`），否则给出通用指引。
  static String _androidOcrDegradationMessage(String stderr) {
    var detail = '';
    try {
      final parsed = jsonDecode(stderr) as Map<String, dynamic>;
      detail = parsed['error']?.toString() ?? '';
    } catch (_) {
      final line = stderr.trim().split('\n').firstWhere(
            (l) => l.trim().isNotEmpty,
            orElse: () => '',
          );
      if (detail.isEmpty) detail = line;
    }
    final base = '安卓本地 OCR 缺依赖：Pillow/pytesseract/tesseract 需构建期'
        '打包进 APK；请配置 DEEPSEEK_OCR_API_KEY 走云端';
    if (detail.isNotEmpty) {
      return '[error: $base（脚本错误：$detail）]';
    }
    return '[error: $base]';
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
    if (_isAndroid) {
      // 低频路径：安卓无 ocr_slides.exe，python 脚本（ocr_slides.py）同样
      // 依赖 tesseract（未构建期打包）——本轮仅保证不抛异常并记录日志，
      // 完整支持留待 OCR 依赖打包后（报告 §5.5）。
      Log().warn('OcrPipeline: 安卓 URL OCR 暂不支持（无 ocr_slides 可执行/依赖）',
          data: {'url': imageUrl});
      return '';
    }
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
        ocrExe ?? (await PythonInterpreter.instance.resolve()).legacyExePath ?? 'python',
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
    if (_isAndroid) {
      return _probeTesseractChaquopy();
    }
    try {
      final rt = await PythonInterpreter.instance.resolve();
      if (!rt.isAvailable) return false;
      final py = rt.legacyExePath!;
      final r = await runOcrProcess(py, [
        '-c',
        'import pytesseract; print(pytesseract.get_tesseract_version())',
      ]).timeout(const Duration(seconds: 15));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 安卓探测：临时 probe 脚本经 [_pythonRunOnce]（Chaquopy）执行。
  ///
  /// 当前安卓未打包 pytesseract → 仍返回 false，但不再抛异常（桌面
  /// `python -c` 子进程在移动端不可用），checkReadiness 据此输出平台化文案。
  Future<bool> _probeTesseractChaquopy() async {
    final probePy = File(p.join(
      Directory.systemTemp.path,
      'ocr_probe_${DateTime.now().millisecondsSinceEpoch}.py',
    ));
    try {
      await probePy.writeAsString(
          'import pytesseract; print(pytesseract.get_tesseract_version())');
      final res = await _pythonRunOnce(
        probePy.path,
        const [],
        timeout: const Duration(seconds: 15),
      );
      return res.exitCode == 0;
    } catch (e) {
      Log().warn('OcrPipeline: 安卓 Tesseract 探测异常', error: e);
      return false;
    } finally {
      try {
        await probePy.delete();
      } catch (_) {}
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

/// PDF 翻译 Service — 通过 Python 子进程调用 pdf2zh 引擎。
///
/// 协议：启动 pdf_translate.py 子进程，逐行读取 stdout JSON Lines 事件流。
/// 依赖 DeepSeek API Key（通过参数传入）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:path/path.dart' as p;

/// PDF 翻译服务 — 单文件翻译。
///
/// 每个 [translate] 调用启动一个独立 Python 子进程，
/// 解析 stdout JSON Lines 事件流，通过回调实时报告进度。
class PdfTranslateService {
  final String _scriptPath; // pdf_translate.py 的绝对路径
  final String? _configuredPython;

  PdfTranslateService({
    required String scriptPath,
    String? pythonExe,
  })  : _scriptPath = scriptPath,
        _configuredPython = pythonExe;

  /// 解析 Python 可执行文件路径，优先使用 Greenix 嵌入版 Python。
  Future<String?> _resolvePython() async {
    // ① 优先 Greenix 嵌入版（.greenix/python/python.exe）
    final greenixPy = p.join(greenixPythonDir, 'python.exe');
    if (await File(greenixPy).exists()) {
      Log().info('PdfTranslate: using greenix Python', data: {'path': greenixPy});
      return greenixPy;
    }
    // ② 回退到通用发现
    return resolvePythonExe(configuredPath: _configuredPython);
  }

  /// .greenix/scripts/translate/ 目录（pdf2zh_next 所在位置）。
  String get _translateDir => File(_scriptPath).parent.path;

  /// 翻译单个 PDF。
  Future<PdfTranslateResult> translate({
    required String inputPath,
    required String outputDir,
    required String apiKey,
    String model = 'deepseek-chat',
    String? thinking,
    String langIn = 'en',
    String langOut = 'zh',
    void Function(int current, int total, String message)? onProgress,
    void Function(String stage, String message)? onStage,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('文件不存在: $inputPath');
    }

    final outputDirectory = Directory(outputDir);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final args = <String>[
      _scriptPath,
      '--input', inputPath,
      '--output', outputDir,
      '--api-key', apiKey,
      '--model', model,
      '--lang-in', langIn,
      '--lang-out', langOut,
    ];
    if (thinking != null && thinking.isNotEmpty) {
      args.addAll(['--thinking', thinking]);
    }

    Log().info('PdfTranslate: starting subprocess',
        data: {'script': _scriptPath, 'input': inputPath, 'model': model});

    final python = await _resolvePython();
    if (python == null) {
      throw Exception('未找到 Python，请安装 Python 3.10+');
    }

    // 安卓：Chaquopy 进程内执行（无子进程）。
    if (Platform.isAndroid) {
      return _translateAndroid(
        inputPath: inputPath,
        outputDir: outputDir,
        apiKey: apiKey,
        model: model,
        thinking: thinking,
        langIn: langIn,
        langOut: langOut,
        onProgress: onProgress,
        onStage: onStage,
      );
    }

    try {
      final process = await Process.start(
        python,
        args,
        includeParentEnvironment: true,
      );

      final stderrBuffer = StringBuffer();
      process.stderr
          .transform(utf8.decoder)
          .listen((data) => stderrBuffer.write(data));

      final completer = Completer<PdfTranslateResult>();
      String? monoPdf;
      String? dualPdf;
      double totalSeconds = 0;
      int totalTokens = 0;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            final type = event['type'] as String?;

            switch (type) {
              case 'stage':
                final stageName = event['stage'] as String? ?? '';
                final stageMsg = event['message'] as String? ?? '';
                onStage?.call(stageName, stageMsg);
                final current = (event['current'] as num?)?.toInt() ?? 0;
                final total = (event['total'] as num?)?.toInt() ?? 0;
                onProgress?.call(current, total, stageMsg);

              case 'progress':
                final current = (event['current'] as num?)?.toInt() ?? 0;
                final total = (event['total'] as num?)?.toInt() ?? 0;
                final message = event['message'] as String? ?? '';
                onProgress?.call(current, total, message);

              case 'finish':
                monoPdf = event['mono_pdf'] as String?;
                dualPdf = event['dual_pdf'] as String?;
                totalSeconds =
                    (event['total_seconds'] as num?)?.toDouble() ?? 0;
                final tokens = event['tokens'] as Map<String, dynamic>?;
                totalTokens = (tokens?['total'] as num?)?.toInt() ?? 0;

                Log().info('PdfTranslate: completed',
                    data: {
                      'dual': dualPdf,
                      'seconds': totalSeconds,
                      'tokens': totalTokens,
                    });

                completer.complete(PdfTranslateResult(
                  monoPdfPath: monoPdf,
                  dualPdfPath: dualPdf,
                  totalSeconds: totalSeconds,
                  totalTokens: totalTokens,
                ));

              case 'error':
                final message =
                    event['message'] as String? ?? 'Unknown error';
                final details = event['details'] as String? ?? '';
                Log().warn('PdfTranslate: error from subprocess',
                    data: {'message': message, 'details': details});
                completer.completeError(
                    Exception('翻译失败: $message\n$details'));

              default:
                final current = (event['current'] as num?)?.toInt() ?? 0;
                final total = (event['total'] as num?)?.toInt() ?? 0;
                final message = event['message'] as String? ?? type ?? '';
                onProgress?.call(current, total, message);
            }
          } on FormatException {
            Log().debug('PdfTranslate: non-JSON stdout: $line');
          } catch (e) {
            if (completer.isCompleted) return;
            Log().warn('PdfTranslate: error parsing event', error: e);
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            Log().error('PdfTranslate: stdout stream error', error: error);
            completer.completeError(error);
          }
        },
      );

      // 子进程异常退出检测
      process.exitCode.then((code) {
        if (!completer.isCompleted) {
          final stderr = stderrBuffer.toString().trim();
          Log().warn('PdfTranslate: subprocess exited before finish/error',
              data: {'exitCode': code, 'stderr': stderr});
          completer.completeError(
              Exception('子进程异常退出 (exit $code)\n$stderr'));
        }
      });

      final result = await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          process.kill();
          throw TimeoutException('翻译超时 (30分钟)');
        },
      );

      return result;
    } on TimeoutException catch (e) {
      Log().error('PdfTranslate: timeout', error: e);
      rethrow;
    } catch (e) {
      Log().error('PdfTranslate: unexpected error', error: e);
      rethrow;
    }
  }

  /// 安卓：经 Chaquopy MethodChannel 在 app 进程内执行 pdf_translate.py。
  ///
  /// runScript 一次性执行并回传 stdout/stderr（无流式），完成后解析
  /// JSON Lines 事件并回放进度/阶段。
  Future<PdfTranslateResult> _translateAndroid({
    required String inputPath,
    required String outputDir,
    required String apiKey,
    String model = 'deepseek-chat',
    String? thinking,
    String langIn = 'en',
    String langOut = 'zh',
    void Function(int current, int total, String message)? onProgress,
    void Function(String stage, String message)? onStage,
  }) async {
    const ch = MethodChannel('evergreen/python');
    final assetPath = await _resolveAndroidScriptPath();
    if (assetPath.isEmpty) {
      throw Exception(
          'pdf_translate.py 未打包进 APK（android/app/src/main/python/），请重新构建');
    }

    final args = <String>[
      '--input', inputPath,
      '--output', outputDir,
      '--api-key', apiKey,
      '--model', model,
      '--lang-in', langIn,
      '--lang-out', langOut,
    ];
    if (thinking != null && thinking.isNotEmpty) {
      args.addAll(['--thinking', thinking]);
    }
    Log().info('PdfTranslate: android chaquopy start',
        data: {'script': assetPath, 'input': inputPath});

    final resp = await ch.invokeMethod<Map<dynamic, dynamic>>('runScript', {
      'entry': assetPath,
      'args': args,
    });

    final stdout = resp?['stdout'] as String? ?? '';
    final stderr = resp?['stderr'] as String? ?? '';
    final code = (resp?['exitCode'] as num?)?.toInt() ?? -1;
    Log().info('PdfTranslate: android done', data: {'exitCode': code});

    // 解析 stdout JSON Lines 事件（progress/stage/finish/error）。
    String? monoPdf;
    String? dualPdf;
    double totalSeconds = 0;
    int totalTokens = 0;
    String? errorMessage;

    for (final line in const LineSplitter().convert(stdout)) {
      if (line.trim().isEmpty) continue;
      try {
        final event = jsonDecode(line) as Map<String, dynamic>;
        final type = event['type'] as String? ?? '';
        switch (type) {
          case 'stage':
            final stage = event['stage'] as String? ?? '';
            final msg = event['message'] as String? ?? '';
            onStage?.call(stage, msg);
            onProgress?.call(
                (event['current'] as num?)?.toInt() ?? 0,
                (event['total'] as num?)?.toInt() ?? 0,
                msg);
          case 'progress':
            onProgress?.call(
                (event['current'] as num?)?.toInt() ?? 0,
                (event['total'] as num?)?.toInt() ?? 0,
                event['message'] as String? ?? '');
          case 'finish':
            monoPdf = event['mono_pdf'] as String?;
            dualPdf = event['dual_pdf'] as String?;
            totalSeconds = (event['total_seconds'] as num?)?.toDouble() ?? 0;
            final tokens = event['tokens'] as Map<String, dynamic>?;
            totalTokens = (tokens?['total'] as num?)?.toInt() ?? 0;
          case 'error':
            errorMessage = event['message'] as String? ?? 'Unknown error';
        }
      } catch (e) {
        Log().warn('PdfTranslate: 事件行解析异常: $e', error: e);
      }
    }

    if (errorMessage != null) {
      throw Exception('翻译失败: $errorMessage');
    }
    if (monoPdf == null && dualPdf == null) {
      final hint = stderr.trim().isNotEmpty ? '\n$stderr' : '';
      throw Exception('翻译未完成 (exit $code)$hint');
    }
    return PdfTranslateResult(
      monoPdfPath: monoPdf,
      dualPdfPath: dualPdf,
      totalSeconds: totalSeconds,
      totalTokens: totalTokens,
    );
  }

  /// 安卓：解析 pdf_translate.py 在设备上的 chaquopy 资源路径。
  Future<String> _resolveAndroidScriptPath() async {
    try {
      final assetPath = await const MethodChannel('evergreen/python')
          .invokeMethod<String>('getAssetPath', {'name': 'pdf_translate.py'});
      if (assetPath != null && assetPath.isNotEmpty) return assetPath;
    } catch (e) {
      Log().warn('PdfTranslate: getAssetPath failed', error: e);
    }
    return '';
  }

  /// 检查翻译环境是否就绪。  ///
  /// 返回 [EnvStatus.ready] / [EnvStatus.missingPython] / [EnvStatus.missingDeps]。
  Future<EnvStatus> checkEnvironment() async {
    try {
      final python = await _resolvePython();
      if (python == null) return EnvStatus.missingPython;

      final pyResult = await Process.run(python, ['--version'])
          .timeout(const Duration(seconds: 10));
      if (pyResult.exitCode != 0) return EnvStatus.missingPython;

      // 检查 pdf2zh 依赖
      final translateDir = _translateDir;
      const verifyCode = r'''
import sys; sys.path.insert(0, r'__TRANSLATE_DIR__')
from pdf2zh_next.high_level import do_translate_async_stream
from pdf2zh_next.config.translate_engine_model import DeepSeekSettings
''';
      final code = verifyCode.replaceAll(
          '__TRANSLATE_DIR__', translateDir.replaceAll('\\', '\\\\'));

      final depResult = await Process.run(python, ['-c', code])
          .timeout(const Duration(seconds: 15));
      if (depResult.exitCode != 0) return EnvStatus.missingDeps;

      Log().info('PdfTranslate: environment ready');
      return EnvStatus.ready;
    } catch (e) {
      Log().warn('PdfTranslate: environment check failed', error: e);
      return EnvStatus.missingPython;
    }
  }

  /// 安装 pdf2zh 所需依赖。
  ///
  /// 等价于 `pip install babeldoc pymupdf openai tomlkit`。
  Future<bool> installDeps({
    void Function(String msg)? onProgress,
  }) async {
    final python = await _resolvePython();
    if (python == null) {
      onProgress?.call('未找到 Python，无法安装依赖');
      return false;
    }
    onProgress?.call('正在安装 babeldoc, pymupdf, openai...');
    try {
      final result = await Process.run(
        python,
        ['-m', 'pip', 'install', 'babeldoc', 'pymupdf', 'openai'],
      ).timeout(const Duration(seconds: 300));
      return result.exitCode == 0;
    } catch (e) {
      onProgress?.call('pip 安装失败: $e');
      return false;
    }
  }
}

/// 单文件翻译结果（core 内部类型）。
class PdfTranslateResult {
  final String? monoPdfPath;
  final String? dualPdfPath;
  final double totalSeconds;
  final int totalTokens;

  const PdfTranslateResult({
    this.monoPdfPath,
    this.dualPdfPath,
    this.totalSeconds = 0,
    this.totalTokens = 0,
  });

  bool get hasOutput => monoPdfPath != null || dualPdfPath != null;
}

/// 环境检查状态。
enum EnvStatus { ready, missingPython, missingDeps }

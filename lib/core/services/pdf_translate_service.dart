import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log.dart';
import '../result.dart';
import '../errors.dart';
import '../utils/python_env.dart';
import '../../features/translate/models/translation_job.dart';

/// PDF 翻译服务——通过 Python 子进程调用 pdf2zh 引擎。
///
/// pdf2zh 源码已内置于 `scripts/pdf2zh_next/`，无需外部引用。
/// 协议：启动 `scripts/pdf_translate.py` 子进程，逐行读取 JSON 事件流。
/// 依赖 DeepSeek API Key（通过参数传入，不存储）。
/// 超时 30 分钟/文件。
///
/// [pythonExe] 为 null 时自动检测（优先使用安装包自带 Python）。
class PdfTranslateService {
  final String scriptPath;
  final String? _configuredPython;

  PdfTranslateService({
    required this.scriptPath,
    String? pythonExe,
  }) : _configuredPython = pythonExe;

  /// 返回 scripts/ 目录路径（pdf2zh_next 所在位置），用于 Python 依赖检查。
  String get _scriptsDir => File(scriptPath).parent.path;

  /// 翻译单个 PDF，onProgress 实时回调进度。
  Future<Result<PdfTranslateResult>> translate({
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
      return Err(AppError.validationError('文件不存在: $inputPath'));
    }

    final outputDirectory = Directory(outputDir);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    final args = <String>[
      scriptPath,
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
        data: {'script': scriptPath, 'input': inputPath, 'model': model});

    // 自动发现 Python（优先自带嵌入版）
    final python = await resolvePythonExe(configuredPath: _configuredPython);
    if (python == null) {
      return Err(AppError.translationFailed(
          '未找到 Python', '请安装 Python 3.10+ 或在设置中配置 Python 路径'));
    }

    try {
      final process = await Process.start(
        python,
        args,
        includeParentEnvironment: true,
      );

      // Collect stderr for error reporting
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
                break;

              case 'progress':
                final current = (event['current'] as num?)?.toInt() ?? 0;
                final total = (event['total'] as num?)?.toInt() ?? 0;
                final message = event['message'] as String? ?? '';
                onProgress?.call(current, total, message);
                break;

              case 'finish':
                monoPdf = event['mono_pdf'] as String?;
                dualPdf = event['dual_pdf'] as String?;
                totalSeconds =
                    (event['total_seconds'] as num?)?.toDouble() ?? 0;
                final tokens = event['tokens'] as Map<String, dynamic>?;
                totalTokens =
                    (tokens?['total'] as num?)?.toInt() ?? 0;

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
                break;

              case 'error':
                final message = event['message'] as String? ?? 'Unknown error';
                final details = event['details'] as String? ?? '';
                Log().warn('PdfTranslate: error from subprocess',
                    data: {'message': message, 'details': details});
                completer.completeError(
                    _TranslationException(message, details));
                break;

              default:
                // Treat unknown types as progress
                final current = (event['current'] as num?)?.toInt() ?? 0;
                final total = (event['total'] as num?)?.toInt() ?? 0;
                final message = event['message'] as String? ?? type ?? '';
                onProgress?.call(current, total, message);
            }
          } on FormatException {
            // Skip non-JSON lines (e.g., warnings printed directly to stdout)
            Log().debug('PdfTranslate: non-JSON stdout: $line');
          } on _TranslationException {
            rethrow;
          } catch (e) {
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

      // Wait for process exit or timeout
      final result = await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          process.kill();
          throw TimeoutException('翻译超时 (30分钟)');
        },
      );

      // Await process exit to capture final stderr
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        final stderr = stderrBuffer.toString().trim();
        Log().warn('PdfTranslate: non-zero exit',
            data: {'exitCode': exitCode, 'stderr': stderr});
        if (result.hasOutput) {
          // Partial output available — return with warning
          return Ok(result);
        }
        return Err(AppError.translationFailed(
            'Python 子进程异常退出 (exit $exitCode)', stderr));
      }

      return Ok(result);
    } on TimeoutException catch (e) {
      Log().error('PdfTranslate: timeout', error: e);
      return Err(AppError.timeout(1800, 'PDF 翻译'));
    } on _TranslationException catch (e) {
      Log().error('PdfTranslate: translation error', error: e);
      return Err(AppError.translationFailed(e.message, e.details));
    } on ProcessException catch (e) {
      Log().error('PdfTranslate: process exception', error: e);
      return Err(AppError.translationFailed(
          '无法启动 Python ($python)', e.message));
    } catch (e) {
      Log().error('PdfTranslate: unexpected error', error: e);
      return Err(AppError.unknown(e));
    }
  }

  /// 检查翻译环境是否就绪。
  ///
  /// 返回 Ok(null) 表示就绪，Ok(errorMsg) 表示有问题但可修复，Err 表示严重错误。
  Future<Result<String?>> checkEnvironment() async {
    try {
      // Auto-detect Python (prefer bundled)
      final python = await resolvePythonExe(configuredPath: _configuredPython);
      if (python == null) {
        return Ok('未找到 Python，请安装 Python 3.10+ 或在设置中配置路径');
      }

      // Check Python
      final pythonResult = await Process.run(
        python, ['--version'],
      ).timeout(const Duration(seconds: 10));
      if (pythonResult.exitCode != 0) {
        return Ok('未找到 Python ($python)，请安装 Python 3.10+');
      }

      // Check pdf2zh (bundled in scripts/)
      final scriptsDir = _scriptsDir;
      const verifyCode = r'''
import sys; sys.path.insert(0, r'__SCRIPTS_DIR__')
from pdf2zh_next.high_level import do_translate_async_stream
from pdf2zh_next.config.translate_engine_model import DeepSeekSettings
''';
      final code = verifyCode.replaceAll(
          '__SCRIPTS_DIR__', scriptsDir.replaceAll('\\', '\\\\'));

      final depResult = await Process.run(
        python, ['-c', code],
      ).timeout(const Duration(seconds: 15));
      if (depResult.exitCode != 0) {
        return Ok('pdf2zh 依赖缺失，请确认已安装: pip install babeldoc pymupdf openai tomlkit');
      }

      Log().info('PdfTranslate: environment ready');
      return const Ok(null);
    } on ProcessException catch (e) {
      return Ok('无法执行 Python: ${e.message}');
    } catch (e) {
      return Err(AppError.unknown(e));
    }
  }
}

/// Internal exception for translation subprocess errors.
class _TranslationException implements Exception {
  final String message;
  final String details;
  const _TranslationException(this.message, this.details);

  @override
  String toString() => 'TranslationException: $message';
}

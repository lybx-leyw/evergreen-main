import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_config_notifier.dart';
import '../../../core/log.dart';
import '../../../core/result.dart';
import '../../../core/services/pdf_translate_service.dart';
import '../../../core/connectivity/connection_manager.dart';
import '../../../core/utils/python_env.dart';
import '../models/translation_job.dart';
import '../models/translation_history.dart';
import '../models/translation_enums.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Service Provider
// ═══════════════════════════════════════════════════════════════════════════

final pdfTranslateServiceProvider = Provider<PdfTranslateService>((ref) {
  final scriptDir = p.join(Directory.current.path, 'scripts');
  final config = ref.watch(appConfigProvider);
  return PdfTranslateService(
    scriptPath: p.join(scriptDir, 'pdf_translate.py'),
    pythonExe: config.pythonExe,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Settings Providers
// ═══════════════════════════════════════════════════════════════════════════

final translateLangInProvider = StateProvider<String>((ref) =>
    AppConfig.translateLangIn ?? 'en');

final translateLangOutProvider = StateProvider<String>((ref) =>
    AppConfig.translateLangOut ?? 'zh');

// ═══════════════════════════════════════════════════════════════════════════
// Job Provider
// ═══════════════════════════════════════════════════════════════════════════

/// 单个翻译任务状态管理。
class TranslateNotifier extends StateNotifier<TranslationJob?> {
  final PdfTranslateService _service;
  final String _apiKey;
  final String _model;
  final String? _thinking;

  final String? _pythonExe;

  TranslateNotifier(this._service, {
    required String apiKey,
    required String model,
    String? thinking,
    String? pythonExe,
  })  : _apiKey = apiKey,
        _model = model,
        _thinking = thinking,
        _pythonExe = pythonExe,
        super(null);

  bool get isIdle => state == null || state!.status == TranslationStatus.idle;
  bool get isActive => state?.isActive ?? false;

  /// 开始翻译一个文件。
  Future<void> startJob({
    required String inputPath,
    required String inputName,
    required String langIn,
    required String langOut,
  }) async {
    final jobId = const Uuid().v4();
    state = TranslationJob(
      id: jobId,
      inputPath: inputPath,
      inputName: inputName,
      langIn: langIn,
      langOut: langOut,
      status: TranslationStatus.preparing,
    );

    // Check & auto-install Python + pdf2zh deps
    final scriptsDir = p.join(Directory.current.path, 'scripts');
    final pyEnv = PythonEnv(python: _pythonExe);
    final envErr = await pyEnv.ensurePdf2zhReady(
      scriptsDir,
      onProgress: (msg) {
        if (mounted && state?.id == jobId) {
          state = state!.copyWith(progressMessage: msg);
        }
      },
    );
    if (envErr != null) {
      if (mounted && state?.id == jobId) {
        state = state!.copyWith(
          status: TranslationStatus.error,
          errorMessage: envErr,
        );
      }
      return;
    }

    // Start translation
    final outputDir = p.join(
      p.dirname(inputPath),
      'translated',
    );

    if (mounted && state?.id == jobId) {
      state = state!.copyWith(status: TranslationStatus.translating);
    }

    final result = await _service.translate(
      inputPath: inputPath,
      outputDir: outputDir,
      apiKey: _apiKey,
      model: _model,
      thinking: _thinking,
      langIn: langIn,
      langOut: langOut,
      onProgress: (current, total, message) {
        if (mounted && state?.id == jobId) {
          state = state!.copyWith(
            currentPage: current,
            totalPages: total,
            progressMessage: message,
          );
        }
      },
      onStage: (stage, message) {
        if (mounted && state?.id == jobId) {
          state = state!.copyWith(
            currentStage: TranslationJob.stageFromString(stage),
            progressMessage: message,
          );
        }
      },
    );

    if (!mounted) return;

    if (result.isErr) {
      state = state?.copyWith(
        status: TranslationStatus.error,
        errorMessage: (result as Err).error.userMessage,
      );
    } else {
      state = state?.copyWith(
        status: TranslationStatus.done,
        result: (result as Ok<PdfTranslateResult>).value,
      );
    }
  }

  void reset() => state = null;
}

/// 归一化 thinking 值。DeepSeekSettings 仅接受 'enabled'/'disabled'/null。
String? _normalizeThinking(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw == 'enabled' || raw == 'disabled') return raw;
  // 兼容旧值: 'true'/'false'/'on'/'off' 等 → 映射为 enabled/disabled
  final lower = raw.toLowerCase();
  if (lower == 'true' || lower == 'on' || lower == '1') return 'enabled';
  if (lower == 'false' || lower == 'off' || lower == '0') return 'disabled';
  return 'enabled'; // 兜底
}

final translateJobProvider =
    StateNotifierProvider<TranslateNotifier, TranslationJob?>((ref) {
  final service = ref.watch(pdfTranslateServiceProvider);
  final config = ref.watch(appConfigProvider);
  return TranslateNotifier(
    service,
    apiKey: AppConfig.deepseekApiKey ?? '',
    model: AppConfig.deepseekModel ?? 'deepseek-chat',
    thinking: _normalizeThinking(AppConfig.deepseekThinking),
    pythonExe: config.pythonExe,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Batch Provider
// ═══════════════════════════════════════════════════════════════════════════

class BatchState {
  final List<String> filePaths;
  final List<String> fileNames;
  final int currentIndex;
  final List<BatchProgress> results;
  final bool isRunning;

  /// Current file's page-level progress (updated in real-time).
  final int currentFilePage;
  final int currentFileTotal;
  final String? currentFileMessage;

  const BatchState({
    this.filePaths = const [],
    this.fileNames = const [],
    this.currentIndex = -1,
    this.results = const [],
    this.isRunning = false,
    this.currentFilePage = 0,
    this.currentFileTotal = 0,
    this.currentFileMessage,
  });

  BatchState copyWith({
    List<String>? filePaths,
    List<String>? fileNames,
    int? currentIndex,
    List<BatchProgress>? results,
    bool? isRunning,
    int? currentFilePage,
    int? currentFileTotal,
    String? currentFileMessage,
  }) =>
      BatchState(
        filePaths: filePaths ?? this.filePaths,
        fileNames: fileNames ?? this.fileNames,
        currentIndex: currentIndex ?? this.currentIndex,
        results: results ?? this.results,
        isRunning: isRunning ?? this.isRunning,
        currentFilePage: currentFilePage ?? this.currentFilePage,
        currentFileTotal: currentFileTotal ?? this.currentFileTotal,
        currentFileMessage: currentFileMessage ?? this.currentFileMessage,
      );

  int get totalFiles => filePaths.length;
  bool get isEmpty => filePaths.isEmpty;
  int get doneCount => results.where((r) => r.status == TranslationStatus.done).length;
  int get errorCount => results.where((r) => r.status == TranslationStatus.error).length;

  /// Overall batch progress (0.0–1.0), including partial progress of current file.
  double get overallProgress {
    if (totalFiles == 0) return 0;
    final base = doneCount / totalFiles;
    if (currentIndex >= 0 && currentIndex < totalFiles && currentFileTotal > 0) {
      return base + (currentFilePage / currentFileTotal) / totalFiles;
    }
    return base;
  }
}

class BatchNotifier extends StateNotifier<BatchState> {
  final PdfTranslateService _service;
  final String _apiKey;
  final String _model;
  final String? _thinking;
  final String? _pythonExe;

  BatchNotifier(this._service, {
    required String apiKey,
    required String model,
    String? thinking,
    String? pythonExe,
  })  : _apiKey = apiKey,
        _model = model,
        _thinking = thinking,
        _pythonExe = pythonExe,
        super(const BatchState());

  void setFiles(List<String> paths) {
    state = BatchState(
      filePaths: paths,
      fileNames: paths.map((p) => p.split(RegExp(r'[/\\]')).last).toList(),
    );
  }

  void clear() => state = const BatchState();

  Future<void> startBatch(String langIn, String langOut) async {
    if (state.filePaths.isEmpty) return;

    // Check & auto-install Python + pdf2zh deps once before batch
    final scriptsDir = p.join(Directory.current.path, 'scripts');
    final pyEnv = PythonEnv(python: _pythonExe);
    final envErr = await pyEnv.ensurePdf2zhReady(scriptsDir);
    if (envErr != null) {
      state = state.copyWith(
        results: [
          BatchProgress(
            fileIndex: 0,
            totalFiles: state.filePaths.length,
            fileName: state.fileNames.first,
            status: TranslationStatus.error,
            errorMessage: envErr,
          ),
        ],
        isRunning: false,
      );
      return;
    }

    state = state.copyWith(
      isRunning: true,
      currentIndex: 0,
      results: [],
      currentFilePage: 0,
      currentFileTotal: 0,
      currentFileMessage: null,
    );

    final completed = <BatchProgress>[];

    for (var i = 0; i < state.filePaths.length; i++) {
      if (!mounted) return;

      state = state.copyWith(
        currentIndex: i,
        currentFilePage: 0,
        currentFileTotal: 0,
        currentFileMessage: '准备翻译...',
      );

      final filePath = state.filePaths[i];
      final fileName = state.fileNames[i];
      final outputDir = p.join(p.dirname(filePath), 'translated');

      final result = await _service.translate(
        inputPath: filePath,
        outputDir: outputDir,
        apiKey: _apiKey,
        model: _model,
        thinking: _thinking,
        langIn: langIn,
        langOut: langOut,
        onProgress: (current, total, message) {
          if (mounted) {
            state = state.copyWith(
              currentFilePage: current,
              currentFileTotal: total,
              currentFileMessage: message,
            );
          }
        },
      );

      // File completed — add to results immediately
      if (result.isErr) {
        final bp = BatchProgress(
          fileIndex: i,
          totalFiles: state.filePaths.length,
          fileName: fileName,
          status: TranslationStatus.error,
          errorMessage: (result as Err).error.userMessage,
        );
        completed.add(bp);
      } else {
        final value = (result as Ok<PdfTranslateResult>).value;
        completed.add(BatchProgress(
          fileIndex: i,
          totalFiles: state.filePaths.length,
          fileName: fileName,
          status: TranslationStatus.done,
          result: value,
        ));
      }

      if (mounted) {
        state = state.copyWith(
          results: [...completed],
          currentFileMessage: completed.last.status == TranslationStatus.done
              ? '${fileName} — 翻译完成'
              : '${fileName} — 翻译失败',
        );
      }
    }

    if (mounted) {
      state = state.copyWith(isRunning: false);
    }
  }
}

final translateBatchProvider =
    StateNotifierProvider<BatchNotifier, BatchState>((ref) {
  final service = ref.watch(pdfTranslateServiceProvider);
  final config = ref.watch(appConfigProvider);
  return BatchNotifier(
    service,
    apiKey: AppConfig.deepseekApiKey ?? '',
    model: AppConfig.deepseekModel ?? 'deepseek-chat',
    thinking: _normalizeThinking(AppConfig.deepseekThinking),
    pythonExe: config.pythonExe,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// History Provider
// ═══════════════════════════════════════════════════════════════════════════

const _historyKey = 'translate_history';

class HistoryNotifier extends StateNotifier<List<TranslationHistory>> {
  HistoryNotifier() : super([]);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyKey) ?? [];
      state = raw
          .map((s) => TranslationHistory.fromJson(
              jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log().warn('Failed to load translation history', error: e);
      state = [];
    }
  }

  Future<void> add(TranslationHistory entry) async {
    state = [entry, ...state];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((h) => h.id != id).toList();
    await _persist();
  }

  Future<void> clear() async {
    state = [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = state.map((h) => jsonEncode(h.toJson())).toList();
      await prefs.setStringList(_historyKey, raw);
    } catch (e) {
      Log().warn('Failed to persist translation history', error: e);
    }
  }
}

final translateHistoryProvider =
    StateNotifierProvider<HistoryNotifier, List<TranslationHistory>>((ref) {
  final notifier = HistoryNotifier();
  notifier.load();
  return notifier;
});

// ═══════════════════════════════════════════════════════════════════════════
// Connectivity Check
// ═══════════════════════════════════════════════════════════════════════════

/// PDF 翻译环境连接检查。
Future<ConnectionResult> checkPdfTranslateConnection(
    PdfTranslateService service) async {
  final start = DateTime.now();
  try {
    final result = await service.checkEnvironment();
    final elapsed = DateTime.now().difference(start);
    if (result.isErr) {
      return ConnectionResult(
        service: 'PDF Translate',
        ok: false,
        message: (result as Err).error.userMessage,
        elapsed: elapsed,
      );
    }
    final msg = (result as Ok<String?>).value;
    if (msg != null) {
      return ConnectionResult(
        service: 'PDF Translate',
        ok: false,
        message: msg,
        elapsed: elapsed,
      );
    }
    return ConnectionResult(
      service: 'PDF Translate',
      ok: true,
      message: '就绪',
      elapsed: elapsed,
    );
  } catch (e) {
    return ConnectionResult(
      service: 'PDF Translate',
      ok: false,
      message: '检查失败: $e',
      elapsed: DateTime.now().difference(start),
    );
  }
}

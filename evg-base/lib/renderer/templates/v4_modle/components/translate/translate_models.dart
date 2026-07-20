/// PDF 翻译模块 UI 数据模型。
///
/// core 层已有 PdfTranslateResult / EnvStatus / QueueEvent。
/// 本文件只保留 UI 层专用类型。
library;

/// 翻译任务状态。
enum TranslationStatus {
  idle,
  queued,
  preparing,
  translating,
  done,
  error;

  bool get isActive => this == preparing || this == translating;
  bool get isTerminal => this == done || this == error;
}

/// 翻译阶段枚举。
enum TranslateStage {
  init, parse, layout, ocr, translate, cache,
  font, summary, cleanup, output, merge, embed, done, error,
}

/// 单文件翻译任务 — 不可变值对象（UI 层使用）。
class TranslationJob {
  final String id;
  final String inputPath;
  final String inputName;
  final String langIn;
  final String langOut;
  final TranslationStatus status;
  final int currentPage;
  final int totalPages;
  final String? progressMessage;
  final String? resultDualPdf;
  final String? resultMonoPdf;
  final double resultSeconds;
  final int resultTokens;
  final String? errorMessage;
  final TranslateStage currentStage;

  TranslationJob({
    required this.id,
    required this.inputPath,
    required this.inputName,
    required this.langIn,
    required this.langOut,
    this.status = TranslationStatus.idle,
    this.currentPage = 0,
    this.totalPages = 0,
    this.progressMessage,
    this.resultDualPdf,
    this.resultMonoPdf,
    this.resultSeconds = 0,
    this.resultTokens = 0,
    this.errorMessage,
    this.currentStage = TranslateStage.init,
  });

  double get progress =>
      totalPages > 0 ? currentPage / totalPages : 0.0;

  bool get isActive => status.isActive;
  bool get isTerminal => status.isTerminal;

  TranslationJob copyWith({
    String? id, String? inputPath, String? inputName,
    String? langIn, String? langOut, TranslationStatus? status,
    int? currentPage, int? totalPages, String? progressMessage,
    String? resultDualPdf, String? resultMonoPdf,
    double? resultSeconds, int? resultTokens,
    String? errorMessage, TranslateStage? currentStage,
  }) {
    return TranslationJob(
      id: id ?? this.id,
      inputPath: inputPath ?? this.inputPath,
      inputName: inputName ?? this.inputName,
      langIn: langIn ?? this.langIn,
      langOut: langOut ?? this.langOut,
      status: status ?? this.status,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      progressMessage: progressMessage ?? this.progressMessage,
      resultDualPdf: resultDualPdf ?? this.resultDualPdf,
      resultMonoPdf: resultMonoPdf ?? this.resultMonoPdf,
      resultSeconds: resultSeconds ?? this.resultSeconds,
      resultTokens: resultTokens ?? this.resultTokens,
      errorMessage: errorMessage ?? this.errorMessage,
      currentStage: currentStage ?? this.currentStage,
    );
  }

  static TranslateStage stageFromString(String name) {
    return switch (name) {
      'stage_init' => TranslateStage.init,
      'stage_parse' => TranslateStage.parse,
      'stage_layout' => TranslateStage.layout,
      'stage_ocr' => TranslateStage.ocr,
      'stage_translate' => TranslateStage.translate,
      'stage_cache' => TranslateStage.cache,
      'stage_font' => TranslateStage.font,
      'stage_summary' => TranslateStage.summary,
      'stage_cleanup' => TranslateStage.cleanup,
      'stage_output' => TranslateStage.output,
      'stage_merge' => TranslateStage.merge,
      'stage_embed' => TranslateStage.embed,
      _ => TranslateStage.translate,
    };
  }
}

/// 队列整体状态快照，供 UI 渲染。
class QueueState {
  final List<TranslationJob> waiting;
  final List<TranslationJob> active;
  final List<TranslationJob> completed;
  final bool isRunning;
  final int maxParallel;

  const QueueState({
    this.waiting = const [],
    this.active = const [],
    this.completed = const [],
    this.isRunning = false,
    this.maxParallel = 3,
  });

  int get totalFiles => waiting.length + active.length + completed.length;
  int get doneCount => completed.where((j) => j.status == TranslationStatus.done).length;
  int get errorCount => completed.where((j) => j.status == TranslationStatus.error).length;

  double get overallProgress {
    if (totalFiles == 0) return 0;
    final base = doneCount / totalFiles;
    double activeProgress = 0;
    for (final job in active) {
      if (job.totalPages > 0) activeProgress += job.currentPage / job.totalPages;
    }
    return (base * totalFiles + activeProgress) / totalFiles;
  }
}

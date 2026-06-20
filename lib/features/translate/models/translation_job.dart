import 'translation_enums.dart';

/// Known babeldoc translation stages in order, for pipeline visualization.
enum TranslateStage {
  init,
  parse,
  layout,
  ocr,
  translate,
  cache,
  font,
  summary,
  cleanup,
  output,
  merge,
  embed,
  done,
  error,
}

/// 单文件翻译任务状态——不可变值对象。
///
/// 使用 [copyWith] 创建新实例，确保 Riverpod 能检测到状态变化。
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
  final PdfTranslateResult? result;
  final String? errorMessage;
  final DateTime createdAt;

  /// Current stage in the translation pipeline.
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
    this.result,
    this.errorMessage,
    DateTime? createdAt,
    this.currentStage = TranslateStage.init,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress =>
      totalPages > 0 ? currentPage / totalPages : 0.0;

  bool get isActive => status.isActive;
  bool get isTerminal => status.isTerminal;

  /// Create a copy with updated fields.
  TranslationJob copyWith({
    String? id,
    String? inputPath,
    String? inputName,
    String? langIn,
    String? langOut,
    TranslationStatus? status,
    int? currentPage,
    int? totalPages,
    String? progressMessage,
    PdfTranslateResult? result,
    String? errorMessage,
    TranslateStage? currentStage,
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
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      currentStage: currentStage ?? this.currentStage,
    );
  }

  /// Map a babeldoc stage name (e.g. "stage_translate") to [TranslateStage].
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
      _ => TranslateStage.translate, // fallback for unknown stages
    };
  }
}

/// 翻译完成后的结果。
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
  String get previewPath => dualPdfPath ?? monoPdfPath ?? '';
}

/// 批量翻译进度。
class BatchProgress {
  final int fileIndex;
  final int totalFiles;
  final String fileName;
  final TranslationStatus status;
  final int currentPage;
  final int totalPages;
  final String? errorMessage;
  final PdfTranslateResult? result;

  const BatchProgress({
    required this.fileIndex,
    required this.totalFiles,
    required this.fileName,
    this.status = TranslationStatus.translating,
    this.currentPage = 0,
    this.totalPages = 0,
    this.errorMessage,
    this.result,
  });
}

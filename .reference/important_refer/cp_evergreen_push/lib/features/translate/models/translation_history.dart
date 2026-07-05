/// 已完成翻译的历史记录。
class TranslationHistory {
  final String id;
  final String fileName;
  final String langIn;
  final String langOut;
  final String? dualPdfPath;
  final double totalSeconds;
  final int totalTokens;
  final DateTime completedAt;

  const TranslationHistory({
    required this.id,
    required this.fileName,
    required this.langIn,
    required this.langOut,
    this.dualPdfPath,
    this.totalSeconds = 0,
    this.totalTokens = 0,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'langIn': langIn,
        'langOut': langOut,
        'dualPdfPath': dualPdfPath,
        'totalSeconds': totalSeconds,
        'totalTokens': totalTokens,
        'completedAt': completedAt.toIso8601String(),
      };

  factory TranslationHistory.fromJson(Map<String, dynamic> json) =>
      TranslationHistory(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        langIn: json['langIn'] as String,
        langOut: json['langOut'] as String,
        dualPdfPath: json['dualPdfPath'] as String?,
        totalSeconds: (json['totalSeconds'] as num?)?.toDouble() ?? 0,
        totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
        completedAt: DateTime.parse(json['completedAt'] as String),
      );

  String get languagePair => '$langIn → $langOut';
  String get durationText =>
      '${totalSeconds.toStringAsFixed(1)}s';
}

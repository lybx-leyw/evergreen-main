/// 全流程追溯记录模型。
///
/// 记录每次 AI 交互的完整上下文，
/// 包括触发方式、调研结果、用户决策、最终影响。
library;

import 'tech_document.dart';

/// AI 交互触发方式。
enum TraceTriggerType {
  /// 用户输入 @ai 触发。
  atAiManual,

  /// 工具栏"分析"按钮触发。
  toolbarAnalyze,

  /// 幽灵文本自动补全。
  ghostAutoComplete,

  /// 幽灵文本 Tab 采纳。
  ghostTabAdopt,
}

/// AI 交互决策。
enum TraceDecision {
  /// 用户接受（Keep）。
  accepted,

  /// 用户拒绝（Discard）。
  rejected,

  /// 部分接受。
  partial,

  /// 仅查看，未操作。
  viewed,
}

/// 全流程追溯记录。
///
/// 一次 AI 交互产生一条 [TraceRecord]。
/// 通过 `traceRecordId` 关联到 [TechVersion]。
class TraceRecord {
  /// 记录唯一 ID。
  final String id;

  /// 关联的文档 ID。
  final String documentId;

  /// 触发方式。
  final TraceTriggerType triggerType;

  /// 触发时的文档内容快照。
  final String contentSnapshot;

  /// 用户指令（@ai 后的文本，或系统触发说明）。
  final String userQuery;

  /// AI 调研查询列表。
  final List<String> researchQueries;

  /// AI 返回的分析报告（序列化为 JSON 字符串）。
  final String? analysisReportJson;

  /// AI 分析报告（解析后，仅内存使用）。
  final TechAnalysisReport? analysisReport;

  /// 用户最终决策。
  final TraceDecision? decision;

  /// 是否生成了 diff 提案。
  final bool diffProposed;

  /// 是否全部 Keep（diff 确认）。
  final bool diffAllKept;

  /// 创建时间。
  final DateTime createdAt;

  /// 完成时间。
  final DateTime? completedAt;

  TraceRecord({
    required this.id,
    required this.documentId,
    required this.triggerType,
    required this.contentSnapshot,
    this.userQuery = '',
    this.researchQueries = const [],
    this.analysisReportJson,
    this.analysisReport,
    this.decision,
    this.diffProposed = false,
    this.diffAllKept = false,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 是否已完成（有决策结果）。
  bool get isCompleted => decision != null;

  /// 从 JSON 反序列化。
  factory TraceRecord.fromJson(Map<String, dynamic> json) {
    TechAnalysisReport? report;
    if (json['analysisReportJson'] is String) {
      report = TechAnalysisReport.fromJsonString(json['analysisReportJson'] as String);
    }

    return TraceRecord(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      triggerType: _parseTriggerType(json['triggerType'] as String?),
      contentSnapshot: json['contentSnapshot'] as String? ?? '',
      userQuery: json['userQuery'] as String? ?? '',
      researchQueries: _asStringList(json['researchQueries']),
      analysisReportJson: json['analysisReportJson'] as String?,
      analysisReport: report,
      decision: _parseDecision(json['decision'] as String?),
      diffProposed: json['diffProposed'] as bool? ?? false,
      diffAllKept: json['diffAllKept'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'triggerType': triggerType.name,
        'contentSnapshot': contentSnapshot,
        'userQuery': userQuery,
        'researchQueries': researchQueries,
        if (analysisReportJson != null) 'analysisReportJson': analysisReportJson,
        if (decision != null) 'decision': decision!.name,
        'diffProposed': diffProposed,
        'diffAllKept': diffAllKept,
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  static TraceTriggerType _parseTriggerType(String? s) {
    if (s == null) return TraceTriggerType.atAiManual;
    return TraceTriggerType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => TraceTriggerType.atAiManual,
    );
  }

  static TraceDecision? _parseDecision(String? s) {
    if (s == null) return null;
    return TraceDecision.values.firstWhere(
      (e) => e.name == s,
      orElse: () => TraceDecision.viewed,
    );
  }

  static List<String> _asStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}

/// 文档版本追溯服务。
///
/// 管理 [TechVersion] 和 [TraceRecord] 的持久化，
/// 提供版本时间线查询能力。
///
/// 存储路径：`.greenix/workspaces/<id>/traces/`
library;

import 'dart:convert';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_version.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/trace_record.dart';

/// 版本时间线条目。
///
/// 将 [TechVersion] 与关联的 [TraceRecord] 合并展示。
class VersionTimelineEntry {
  final TechVersion version;
  final TraceRecord? traceRecord;

  const VersionTimelineEntry({required this.version, this.traceRecord});

  /// 人类可读的变更描述。
  String get changeLabel {
    final desc = version.description;
    if (desc != null && desc.isNotEmpty) return desc;
    switch (version.changeType) {
      case VersionChangeType.manualEdit:
        return '手动编辑';
      case VersionChangeType.aiRevision:
        return 'AI 改写采纳';
      case VersionChangeType.ghostAdopt:
        return '幽灵文本采纳';
      case VersionChangeType.initial:
        return '初始版本';
    }
  }

  /// 关联的 AI 分析报告摘要。
  String? get aiSummary => traceRecord?.analysisReport?.understanding;
}

/// 文档追溯服务。
///
/// 内存中维护版本列表和追溯记录列表。
/// 实际持久化由调用方负责（通过 `exportJson` 序列化）。
class DocTraceService {
  final String documentId;
  final List<TechVersion> _versions = [];
  final List<TraceRecord> _traceRecords = [];

  DocTraceService({required this.documentId});

  // ═══════ 版本管理 ═══════

  /// 记录一个新版本。
  void recordVersion({
    required String fullContent,
    String? previousContent,
    String? traceRecordId,
    VersionChangeType changeType = VersionChangeType.manualEdit,
    String? description,
  }) {
    final versionNumber = _versions.length + 1;
    String diff = '';
    if (previousContent != null) {
      diff = _computeSimpleDiff(previousContent, fullContent);
    }

    _versions.add(TechVersion(
      id: 'v-$documentId-$versionNumber',
      documentId: documentId,
      versionNumber: versionNumber,
      fullContent: fullContent,
      diffFromPrevious: diff,
      changeType: changeType,
      traceRecordId: traceRecordId,
      description: description,
    ));
  }

  /// 获取所有版本（按时间正序）。
  List<TechVersion> get versions => List.unmodifiable(_versions);

  /// 获取最新版本。
  TechVersion? get latestVersion =>
      _versions.isEmpty ? null : _versions.last;

  /// 获取指定版本号。
  TechVersion? getVersion(int versionNumber) {
    if (versionNumber < 1 || versionNumber > _versions.length) return null;
    return _versions[versionNumber - 1];
  }

  /// 版本总数。
  int get versionCount => _versions.length;

  // ═══════ 追溯记录管理 ═══════

  /// 记录一次 AI 交互。
  TraceRecord recordTrace({
    required TraceTriggerType triggerType,
    required String contentSnapshot,
    String userQuery = '',
    List<String> researchQueries = const [],
    String? analysisReportJson,
    TechAnalysisReport? analysisReport,
  }) {
    final record = TraceRecord(
      id: 'trace-$documentId-${_traceRecords.length + 1}-'
          '${DateTime.now().millisecondsSinceEpoch}',
      documentId: documentId,
      triggerType: triggerType,
      contentSnapshot: contentSnapshot,
      userQuery: userQuery,
      researchQueries: researchQueries,
      analysisReportJson: analysisReportJson,
      analysisReport: analysisReport,
    );
    _traceRecords.add(record);
    return record;
  }

  /// 记录决策结果。
  void recordDecision(String traceId, TraceDecision decision) {
    final idx = _traceRecords.indexWhere((t) => t.id == traceId);
    if (idx < 0) return;

    final old = _traceRecords[idx];
    _traceRecords[idx] = TraceRecord(
      id: old.id,
      documentId: old.documentId,
      triggerType: old.triggerType,
      contentSnapshot: old.contentSnapshot,
      userQuery: old.userQuery,
      researchQueries: old.researchQueries,
      analysisReportJson: old.analysisReportJson,
      analysisReport: old.analysisReport,
      decision: decision,
      diffProposed: old.diffProposed,
      diffAllKept: old.diffAllKept,
      createdAt: old.createdAt,
      completedAt: DateTime.now(),
    );
  }

  /// 标记 diff 提案和确认结果。
  void recordDiffResult(String traceId, {required bool allKept}) {
    final idx = _traceRecords.indexWhere((t) => t.id == traceId);
    if (idx < 0) return;

    final old = _traceRecords[idx];
    _traceRecords[idx] = TraceRecord(
      id: old.id,
      documentId: old.documentId,
      triggerType: old.triggerType,
      contentSnapshot: old.contentSnapshot,
      userQuery: old.userQuery,
      researchQueries: old.researchQueries,
      analysisReportJson: old.analysisReportJson,
      analysisReport: old.analysisReport,
      decision: old.decision,
      diffProposed: true,
      diffAllKept: allKept,
      createdAt: old.createdAt,
      completedAt: old.completedAt,
    );
  }

  /// 获取所有追溯记录。
  List<TraceRecord> get traceRecords => List.unmodifiable(_traceRecords);

  // ═══════ 时间线查询 ═══════

  /// 构建版本时间线（版本 + 关联追溯记录）。
  List<VersionTimelineEntry> buildTimeline() {
    final entries = <VersionTimelineEntry>[];
    for (final v in _versions) {
      TraceRecord? trace;
      if (v.traceRecordId != null) {
        trace = _traceRecords.cast<TraceRecord?>().firstWhere(
          (t) => t?.id == v.traceRecordId,
          orElse: () => null,
        );
      }
      entries.add(VersionTimelineEntry(version: v, traceRecord: trace));
    }
    return entries;
  }

  /// 导出全部数据为 JSON（用于文件持久化）。
  Map<String, dynamic> exportJson() => {
        'documentId': documentId,
        'versions': _versions.map((v) => v.toJson()).toList(),
        'traceRecords': _traceRecords.map((t) => t.toJson()).toList(),
        'exportedAt': DateTime.now().toIso8601String(),
      };

  /// 从 JSON 导入（用于文件恢复）。
  factory DocTraceService.fromJson(
      String documentId, Map<String, dynamic> json) {
    final service = DocTraceService(documentId: documentId);
    final versions = (json['versions'] as List<dynamic>?)
            ?.map((e) => TechVersion.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final traces = (json['traceRecords'] as List<dynamic>?)
            ?.map((e) => TraceRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    // 绕过 final 限制使用级联
    service._versions.addAll(versions);
    service._traceRecords.addAll(traces);
    return service;
  }

  // ═══════ 内部 ═══════

  /// 简单文本 diff（基于行对比）。
  ///
  /// 不依赖 diff_match_patch——仅用于版本记录的轻量级对比。
  static String _computeSimpleDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final buf = StringBuffer();

    // 找到共同前缀
    int prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }

    // 找到共同后缀
    int oldSuffix = oldLines.length - 1;
    int newSuffix = newLines.length - 1;
    while (oldSuffix >= prefix &&
        newSuffix >= prefix &&
        oldLines[oldSuffix] == newLines[newSuffix]) {
      oldSuffix--;
      newSuffix--;
    }

    // 删除的行
    for (int i = prefix; i <= oldSuffix; i++) {
      buf.writeln('- ${oldLines[i]}');
    }
    // 新增的行
    for (int i = prefix; i <= newSuffix; i++) {
      buf.writeln('+ ${newLines[i]}');
    }

    return buf.toString().trimRight();
  }
}

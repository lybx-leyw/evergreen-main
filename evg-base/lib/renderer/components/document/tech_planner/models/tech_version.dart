/// 文档版本快照模型。
///
/// 记录每次文档修改的完整快照，用于版本时间线追溯。
library;

/// 版本变更类型。
enum VersionChangeType {
  /// 用户手动编辑。
  manualEdit,

  /// AI 改写采纳（diff merge）。
  aiRevision,

  /// AI 幽灵文本采纳（Tab 确认）。
  ghostAdopt,

  /// 初始版本。
  initial,
}

/// 文档版本快照。
///
/// 每次发生修改时保存一份 [TechVersion]，包含
/// 完整文档内容和关联的追溯记录 ID。
class TechVersion {
  /// 版本唯一 ID。
  final String id;

  /// 关联的文档 ID。
  final String documentId;

  /// 版本序号（自增）。
  final int versionNumber;

  /// 该版本的完整文档内容。
  final String fullContent;

  /// 相对于上一版本的 diff 文本（patch 格式，首个版本为空）。
  final String diffFromPrevious;

  /// 变更类型。
  final VersionChangeType changeType;

  /// 关联的追溯记录 ID（如 AI 交互记录）。
  final String? traceRecordId;

  /// 变更说明。
  final String? description;

  /// 创建时间。
  final DateTime createdAt;

  TechVersion({
    required this.id,
    required this.documentId,
    required this.versionNumber,
    required this.fullContent,
    this.diffFromPrevious = '',
    this.changeType = VersionChangeType.manualEdit,
    this.traceRecordId,
    this.description,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从 JSON 反序列化。
  factory TechVersion.fromJson(Map<String, dynamic> json) {
    return TechVersion(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      versionNumber: json['versionNumber'] as int? ?? 0,
      fullContent: json['fullContent'] as String? ?? '',
      diffFromPrevious: json['diffFromPrevious'] as String? ?? '',
      changeType: _parseChangeType(json['changeType'] as String?),
      traceRecordId: json['traceRecordId'] as String?,
      description: json['description'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'versionNumber': versionNumber,
        'fullContent': fullContent,
        'diffFromPrevious': diffFromPrevious,
        'changeType': changeType.name,
        if (traceRecordId != null) 'traceRecordId': traceRecordId,
        if (description != null) 'description': description,
        'createdAt': createdAt.toIso8601String(),
      };

  static VersionChangeType _parseChangeType(String? s) {
    if (s == null) return VersionChangeType.manualEdit;
    return VersionChangeType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => VersionChangeType.manualEdit,
    );
  }
}

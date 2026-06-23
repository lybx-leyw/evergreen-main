/// Palace 回响调度模型（第二阶段用，第一阶段仅定义骨架）。
///
/// 回响调度记录每一条教训/关键事件的间隔重复状态——
/// 类似 WordPecker 的 FSRS 卡片，但对认知内容而非单词。
library;

/// 回响调度条目——一条教训或事件的间隔重复状态。
class EchoSchedule {
  /// 关联的事件或教训 ID。
  final String targetId;

  /// 是事件还是教训。
  final EchoTargetType targetType;

  /// 上次回顾时间。
  final DateTime? lastReviewedAt;

  /// 下次计划回顾时间。
  final DateTime? nextReviewAt;

  /// 回顾间隔天数（如 1, 3, 7, 30, 90, 180, 365）。
  final int intervalDays;

  /// 当前回顾次数（用于计算下一次间隔）。
  final int reviewCount;

  /// 上次评分（0-4，同 FSRS）。
  final int? lastRating;

  const EchoSchedule({
    required this.targetId,
    required this.targetType,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.intervalDays = 1,
    this.reviewCount = 0,
    this.lastRating,
  });

  /// 是否到了该回顾的时间。
  bool get isDue {
    if (nextReviewAt == null) return true;
    return DateTime.now().isAfter(nextReviewAt!);
  }
}

/// 回响目标类型。
enum EchoTargetType { event, lesson }

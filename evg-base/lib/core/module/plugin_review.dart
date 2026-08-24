/// 插件审核与评分聚合（M5-2，纯逻辑）。
///
/// 市场层负责「信任」：用户安装前，平台要给一个可审计的信任信号。
/// 本文件只做可单测的审核队列与评分聚合，不含网络抓取（在主包完成）。
///
/// 设计要点（来自 plugin-ecosystem.md §3 生态三则）：
/// - fail-closed：未知来源 / 缺字段的审核记录抛 [FormatException]，不会静默放行。
/// - 未知字段静默忽略。
/// - 评分聚合为纯函数，空集合返回 [ReviewAggregate.empty]（平均分 null，不制造假 0 分）。
library;

import 'dart:convert';

/// 单条用户/机器人评价。
class PluginReview {
  /// 评价者标识（用户 ID / 来源名）。
  final String author;

  /// 1–5 星（含边界）。
  final int stars;

  /// 可选文字评价。
  final String? comment;

  /// 评价来源（如 'user' / 'marketplace-bot'）。
  final String source;

  const PluginReview({
    required this.author,
    required this.stars,
    this.comment,
    this.source = 'user',
  });

  factory PluginReview.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as String?;
    if (author == null || author.isEmpty) {
      throw FormatException('review 缺少 author');
    }
    final stars = json['stars'] as int?;
    if (stars == null || stars < 1 || stars > 5) {
      throw FormatException('review $author 的 stars 必须在 1–5: $stars');
    }
    return PluginReview(
      author: author,
      stars: stars,
      comment: json['comment'] as String?,
      source: json['source'] as String? ?? 'user',
    );
  }

  Map<String, dynamic> toJson() => {
        'author': author,
        'stars': stars,
        if (comment != null) 'comment': comment,
        'source': source,
      };
}

/// 评分聚合结果（纯数据）。
class ReviewAggregate {
  /// 平均分（1–5），无评价时为 null。
  final double? average;

  /// 各星级计数（索引 0 → 1 星，……索引 4 → 5 星）。
  final List<int> histogram;

  /// 总评价数。
  final int count;

  const ReviewAggregate({
    required this.average,
    required this.histogram,
    required this.count,
  });

  /// 无评价时的规范空值。
  static const ReviewAggregate empty = ReviewAggregate(
    average: null,
    histogram: [0, 0, 0, 0, 0],
    count: 0,
  );

  /// 平均星数向下取整的安全展示档（1–5），无评价返回 null。
  int? get roundedStars {
    if (average == null) return null;
    return average!.round().clamp(1, 5);
  }

  @override
  String toString() =>
      'ReviewAggregate(avg=$average, n=$count)';
}

/// 聚合一组评价（纯函数，fail-closed 透传非法单条）。
ReviewAggregate aggregateReviews(List<PluginReview> reviews) {
  if (reviews.isEmpty) return ReviewAggregate.empty;
  final hist = [0, 0, 0, 0, 0];
  var sum = 0;
  for (final r in reviews) {
    // stars 在 fromJson 已校验 1–5，这里直接索引。
    hist[r.stars - 1] += 1;
    sum += r.stars;
  }
  final avg = sum / reviews.length;
  return ReviewAggregate(
    average: double.parse(avg.toStringAsFixed(2)),
    histogram: hist,
    count: reviews.length,
  );
}

/// 审核状态（fail-closed：默认 [pending] 即不信任、不展示）。
enum ReviewStatus {
  /// 待审（默认，未决等同于拒绝曝光）。
  pending,

  /// 已通过，可在市场暴露。
  approved,

  /// 已拒绝（含安全黑名单）。
  rejected,
}

/// 审核记录（单个插件在市场侧的信任快照）。
class ReviewRecord {
  final String pluginId;
  final ReviewStatus status;

  /// 触发状态的原因（如 'manual' / 'bot-clean' / 'blocklist-hash'）。
  final String reason;

  /// 关联的评分聚合（可空，审核通过后才可能有分）。
  final ReviewAggregate? aggregate;

  const ReviewRecord({
    required this.pluginId,
    required this.status,
    required this.reason,
    this.aggregate,
  });

  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    final pluginId = json['pluginId'] as String?;
    if (pluginId == null || pluginId.isEmpty) {
      throw FormatException('review record 缺少 pluginId');
    }
    final statusRaw = json['status'] as String?;
    final status = _parseReviewStatus(statusRaw);
    if (status == null) {
      throw FormatException('review record $pluginId 的 status 非法: $statusRaw');
    }
    final aggRaw = json['aggregate'] as Map<String, dynamic>?;
    final aggregate = aggRaw == null ? null : _aggregateFromJson(aggRaw);
    return ReviewRecord(
      pluginId: pluginId,
      status: status,
      reason: json['reason'] as String? ?? 'manual',
      aggregate: aggregate,
    );
  }

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'status': status.name,
        'reason': reason,
        if (aggregate != null) 'aggregate': _aggregateToJson(aggregate!),
      };

  /// fail-closed：仅 [approved] 可在市场暴露。
  bool get isExposable => status == ReviewStatus.approved;
}

ReviewStatus? _parseReviewStatus(String? raw) {
  if (raw == null) return null;
  for (final s in ReviewStatus.values) {
    if (s.name == raw) return s;
  }
  return null;
}

Map<String, dynamic> _aggregateToJson(ReviewAggregate a) => {
      'average': a.average,
      'histogram': a.histogram,
      'count': a.count,
    };

ReviewAggregate _aggregateFromJson(Map<String, dynamic> json) {
  final avg = json['average'] as double?;
  final hist = (json['histogram'] as List?)?.cast<int>() ??
      const [0, 0, 0, 0, 0];
  final count = json['count'] as int? ?? 0;
  return ReviewAggregate(
    average: avg,
    histogram: hist.length == 5 ? hist : const [0, 0, 0, 0, 0],
    count: count,
  );
}

/// 审核队列（纯逻辑，fail-closed 默认拒绝）。
///
/// 输入一组原始记录（可能来自多个源），输出「可暴露」的白名单。
/// 规则：
/// - 缺字段 / 非法 status → 透传 [FormatException]（不会静默变成空队列）。
/// - 同 [pluginId] 重复 → 保留最后一条（以最新审核为准）。
/// - 仅 [ReviewStatus.approved] 进入白名单。
class ReviewQueue {
  final Map<String, ReviewRecord> _byId = {};

  /// 默认构造（显式声明，避免隐式构造在 factory 共存时解析歧义）。
  ReviewQueue();

  /// 提交一条记录（覆盖同 id 旧记录）。
  void submit(ReviewRecord record) => _byId[record.pluginId] = record;

  /// 从 JSON 数组批量提交（fail-closed 透传非法单条）。
  void ingest(List<Map<String, dynamic>> raw) {
    for (final item in raw) {
      submit(ReviewRecord.fromJson(item));
    }
  }

  /// 当前队列中全部记录。
  List<ReviewRecord> get all => _byId.values.toList();

  /// 可暴露白名单（approved 且通过评分校验）。
  ///
  /// [minStars] 可选门槛（默认 null 表示不卡平均分）。
  List<ReviewRecord> exposable({double? minStars}) => _byId.values
      .where((r) =>
          r.isExposable &&
          (minStars == null ||
              (r.aggregate?.average ?? 0) >= minStars))
      .toList();

  /// 是否允许某插件暴露（供 UI / 安装器快速查询）。
  bool allows(String pluginId, {double? minStars}) =>
      exposable(minStars: minStars).any((r) => r.pluginId == pluginId);

  /// 取某插件的审核状态（未收录返回 null，供 UI 角标区分「未审核」）。
  ReviewStatus? allStatusOf(String pluginId) => _byId[pluginId]?.status;

  /// 从审核记录 JSON 加载（M5-7）。
  ///
  /// [body] 支持两种形态（fail-closed 透传非法单条）：
  /// - 数组：`[ {record}, ... ]`
  /// - 对象：`{ "records": [ {record}, ... ] }`
  ///
  /// 记录格式见 [ReviewRecord.fromJson]。
  factory ReviewQueue.fromJsonSource(String body) {
    final q = ReviewQueue();
    q.loadJson(body);
    return q;
  }

  /// 从 JSON 字符串增量加载（不清除已有记录，覆盖同 id）。
  void loadJson(String body) {
    final decoded = jsonDecode(body);
    final List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['records'] is List) {
      list = decoded['records'] as List;
    } else {
      throw FormatException(
          '审核记录 JSON 必须是数组或含 records 数组的对象');
    }
    ingest(list.cast<Map<String, dynamic>>());
  }
}

/// 用户评价存储（M5-12，纯逻辑）。
///
/// 仅持有内存中的用户评价，按 [pluginId] 聚合为 [ReviewAggregate]。
/// 持久化通过可选 [sink] 回调完成（主包注入文件写入，本文件不依赖 dart:io）。
class ReviewStore {
  final Map<String, List<PluginReview>> _byId = {};

  /// 落盘回调（可选）：每次提交后收到最新该插件的评价列表 JSON。
  final Future<void> Function(String pluginId, List<Map<String, dynamic>>)? sink;

  ReviewStore({this.sink});

  /// 提交一条用户评价（聚合后触发 [sink]）。
  ///
  /// 注意：[PluginReview.author] 是评价者标识，不是插件 id。
  /// 用 [submitFor] 显式传 [pluginId] 更准确；[submit] 以 [review.author]
  /// 作为聚合键仅作兼容，新代码请用 [submitFor]。
  Future<ReviewAggregate> submit(PluginReview review) async {
    return submitFor(review.author, review);
  }

  /// 按显式 [pluginId] 提交（推荐：避免 author 语义歧义）。
  Future<ReviewAggregate> submitFor(String pluginId, PluginReview review) async {
    final list = _byId.putIfAbsent(pluginId, () => []);
    list.add(review);
    if (sink != null) {
      await sink!(pluginId, list.map((r) => r.toJson()).toList());
    }
    return aggregateReviews(list);
  }

  /// 取某插件的聚合评分（无评价返回 [ReviewAggregate.empty]）。
  ReviewAggregate aggregateOf(String pluginId) {
    final list = _byId[pluginId];
    if (list == null || list.isEmpty) return ReviewAggregate.empty;
    return aggregateReviews(list);
  }

  /// 取全部聚合（供 UI 批量注入 [MarketView.reviewsById]）。
  Map<String, ReviewAggregate> allAggregates() =>
      _byId.map((id, list) => MapEntry(id, aggregateReviews(list)));
}

/// 数据源状态管理器 — 统一追踪各数据源的连通性与新鲜度。
///
/// 将 QuickConnect（连通性检查）与 IDEA1 提案 1（数据更新时间展示）
/// 合并为统一的"数据状态面板"。
library;

import '../storage/database.dart';

/// 单个数据源的状态快照。
class DataSourceStatus {
  /// 显示名称，如 "ZDBK 成绩"。
  final String name;

  /// 分类：ZDBK / Courses / Classroom / Todo / PTA / AI。
  final String category;

  /// WebCacheDatabase 缓存 key（文件缓存的数据源）。内存缓存的数据源为 null。
  final String? cacheKey;

  /// 数据新鲜度 TTL。
  final Duration ttl;

  /// 服务是否可达（连接状态）。
  bool connected;

  /// 上次成功拉取时间（从文件缓存中读取 cachedAt）。
  DateTime? lastFetchedAt;

  /// 上次错误信息。
  String? lastError;

  DataSourceStatus({
    required this.name,
    required this.category,
    this.cacheKey,
    required this.ttl,
    this.connected = false,
    this.lastFetchedAt,
    this.lastError,
  });

  /// 数据是否新鲜（在 TTL 内）。
  bool get isFresh =>
      lastFetchedAt != null &&
      DateTime.now().difference(lastFetchedAt!) < ttl;

  /// 新鲜度标签。
  String get freshnessLabel {
    if (lastFetchedAt == null) return '从未';
    return isFresh ? '新鲜' : '过期';
  }

  /// 相对时间描述。
  String get relativeTime {
    if (lastFetchedAt == null) return '从未更新';
    final diff = DateTime.now().difference(lastFetchedAt!);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

/// 全局数据状态管理器。
///
/// 注册所有数据源，提供独立刷新和全量检查能力。
class DataStatusManager {
  final Map<String, DataSourceStatus> _sources = {};

  /// 注册一个数据源。
  void registerSource(DataSourceStatus source) {
    _sources[source.name] = source;
  }

  /// 注册所有预设数据源。
  void registerDefaults() {
    // ── ZDBK 数据源（文件缓存） ──
    registerSource(DataSourceStatus(
      name: 'ZDBK 成绩',
      category: 'ZDBK',
      cacheKey: 'zdbk_Transcript',
      ttl: CacheTtl.transcript,
    ));
    registerSource(DataSourceStatus(
      name: 'ZDBK 考试',
      category: 'ZDBK',
      cacheKey: 'zdbk_exams',
      ttl: CacheTtl.exams,
    ));
    registerSource(DataSourceStatus(
      name: 'ZDBK 课表',
      category: 'ZDBK',
      cacheKey: null, // 动态 key
      ttl: CacheTtl.timetable,
    ));
    registerSource(DataSourceStatus(
      name: '开课情况',
      category: 'ZDBK',
      cacheKey: null, // 动态 key
      ttl: CacheTtl.courseOfferings,
    ));
    registerSource(DataSourceStatus(
      name: '培养方案',
      category: 'ZDBK',
      cacheKey: 'zdbk_trainingPlans',
      ttl: CacheTtl.trainingPlans,
    ));

    // ── Classroom（文件缓存） ──
    registerSource(DataSourceStatus(
      name: '智云课堂',
      category: 'Classroom',
      cacheKey: 'classroom_courses',
      ttl: const Duration(hours: 1),
    ));

    // ── ZDBK 通知（文件缓存） ──
    registerSource(DataSourceStatus(
      name: '教务通知',
      category: 'ZDBK',
      cacheKey: 'zdbk_notifications',
      ttl: CacheTtl.notifications,
    ));

    // ── Courses API（内存缓存） ──
    registerSource(DataSourceStatus(
      name: '学在浙大 课程',
      category: 'Courses',
      cacheKey: null,
      ttl: const Duration(minutes: 5),
    ));
    registerSource(DataSourceStatus(
      name: '学在浙大 考试',
      category: 'Courses',
      cacheKey: null,
      ttl: const Duration(minutes: 10),
    ));

    // ── Todo / PTA ──
    registerSource(DataSourceStatus(
      name: '待办事项',
      category: 'Todo',
      cacheKey: null,
      ttl: const Duration(minutes: 5),
    ));
    registerSource(DataSourceStatus(
      name: 'PTA 编程题',
      category: 'PTA',
      cacheKey: null,
      ttl: const Duration(minutes: 30),
    ));

    // ── AI 服务（连通性检查） ──
    registerSource(DataSourceStatus(
      name: 'DeepSeek API',
      category: 'AI',
      cacheKey: null,
      ttl: const Duration(minutes: 1),
    ));
    registerSource(DataSourceStatus(
      name: 'DeepSeek OCR',
      category: 'AI',
      cacheKey: null,
      ttl: const Duration(minutes: 1),
    ));
  }

  /// 获取所有已注册的数据源（按分类排序）。
  List<DataSourceStatus> get sources {
    final order = ['ZDBK', 'Courses', 'Classroom', 'Todo', 'PTA', 'AI'];
    final list = _sources.values.toList();
    list.sort((a, b) {
      final ai = order.indexOf(a.category);
      final bi = order.indexOf(b.category);
      if (ai != bi) return ai.compareTo(bi);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// 获取指定名称的数据源。
  DataSourceStatus? source(String name) => _sources[name];

  /// 按分类获取数据源列表。
  List<DataSourceStatus> byCategory(String category) =>
      _sources.values.where((s) => s.category == category).toList();

  /// 获取分类列表（按注册顺序）。
  List<String> get categories {
    final seen = <String>{};
    final result = <String>[];
    for (final s in sources) {
      if (seen.add(s.category)) result.add(s.category);
    }
    return result;
  }

  /// 刷新所有数据源的时间戳。
  ///
  /// 有文件缓存的源从磁盘读取 cachedAt；无文件缓存的源（内存数据/API 连通检查）
  /// 使用当前时间——表示数据源可正常访问。
  void refreshFreshness(WebCacheDatabase db) {
    final now = DateTime.now();
    final isAW = now.month >= 9 || now.month <= 2;
    final year = isAW ? now.year : now.year - 1;
    final semester = isAW ? 3 : 12;

    for (final s in _sources.values) {
      bool found = false;
      if (s.cacheKey != null) {
        final ts = db.getCacheTimestamp(s.cacheKey!);
        if (ts != null) { s.lastFetchedAt = ts; found = true; }
      }
      if (!found) {
        // 动态 key
        for (final k in _dynamicKeys(s.name, year, semester)) {
          final ts = db.getCacheTimestamp(k);
          if (ts != null) { s.lastFetchedAt = ts; found = true; break; }
        }
      }
      // 无文件缓存的源（内存数据/API 连通）：如果还没有时间戳，使用当前时间
      if (!found && s.cacheKey == null) {
        s.lastFetchedAt ??= now;
      }
    }
  }

  /// 为动态 key 的数据源生成可能的缓存 key 列表。
  List<String> _dynamicKeys(String name, int year, int semester) {
    switch (name) {
      case 'ZDBK 课表':
        return ['zdbk_Timetable${year}_$semester'];
      case '开课情况':
        return ['zdbk_courseOfferings_${year}_$semester'];
      default:
        return [];
    }
  }

  /// 更新连通性状态。
  void updateConnectivity(String name, bool connected, {String? error}) {
    final s = _sources[name];
    if (s != null) {
      s.connected = connected;
      s.lastError = error;
    }
  }

  /// 连通的数据源数。
  int get connectedCount =>
      _sources.values.where((s) => s.connected).length;

  /// 新鲜的数据源数。
  int get freshCount =>
      _sources.values.where((s) => s.isFresh).length;

  /// 总数据源数。
  int get totalCount => _sources.length;
}

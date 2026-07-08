/// 数据谱仪器——统一注册、获取、缓存、状态追踪。
///
/// # 公开 API
///
/// ## DataOrchestrator
/// | 方法 | 说明 |
/// |------|------|
/// | `register(type, fetcher)` | 注册数据类型与拉取方式；重复覆盖 |
/// | `registerAll(entries)` | 批量注册 |
/// | `isRegistered(type)` | 是否已注册 |
/// | `unregister(type)` | 注销并清除缓存 |
/// | `get(type)` | 缓存优先：有缓存就返回（过期也返回），无缓存则拉取 |
/// | `refresh(type)` | 强制拉取，合法则覆写缓存，非法返回 null 不覆写 |
/// | `refreshAllStale({types})` | 批量刷新过期数据 |
/// | `invalidate(type)` | 清缓存 |
/// | `allStatuses` | 按分类+名称排序的 [DataSourceStatus] 列表 |
/// | `status(name)` | 按名称查询 [DataSourceStatus] |
/// | `statusByCategory(c)` | 按分类过滤 |
/// | `categories` | 所有分类名 |
/// | `connectedCount` / `freshCount` / `totalCount` | 计数 |
/// | `testConnectivity(name)` | 单源连通性测试 |
/// | `testAllConnectivity()` | 全源测试，返回 Map |
///
/// ## DataSourceStatus（状态快照）
/// | 属性 | 说明 |
/// |------|------|
/// | `name` / `category` / `displayName` | 基本信息 |
/// | `connected` | 连通状态，get / refresh / testConnectivity 自动更新 |
/// | `lastFetchedAt` / `lastError` | 最近拉取时间 / 最近错误 |
/// | `isFresh` | 是否在 TTL 内 |
/// | `freshnessLabel` | "新鲜" / "过期" / "从未" |
/// | `relativeTime` | "3 分钟前" 等人性化时间 |

import 'dart:convert';

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:evergreen_base/core/log.dart';
import 'type.dart';
import 'exceptions.dart';
import 'cache.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceStatus
// ═══════════════════════════════════════════════════════════════════════════

/// 数据源状态快照。
class DataSourceStatus {
  final String name;
  final String category;
  final String displayName;
  final String? cacheKey;
  final Duration ttl;

  bool connected = false;
  DateTime? lastFetchedAt;
  String? lastError;

  DataSourceStatus({
    required this.name,
    required this.category,
    required this.displayName,
    this.cacheKey,
    required this.ttl,
  });

  @visibleForTesting
  set debugLastFetchedAt(DateTime? value) => lastFetchedAt = value;

  bool get isFresh =>
      lastFetchedAt != null &&
      DateTime.now().difference(lastFetchedAt!) < ttl;

  String get freshnessLabel {
    if (lastFetchedAt == null) return '从未';
    return isFresh ? '新鲜' : '过期';
  }

  String get relativeTime {
    if (lastFetchedAt == null) return '从未更新';
    final diff = DateTime.now().difference(lastFetchedAt!);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DataOrchestrator
// ═══════════════════════════════════════════════════════════════════════════

/// 数据谱仪器——持有数据类型、拉取方式、状态信息。
class DataOrchestrator {
  final Map<String, DataType> _types = {};
  final Map<String, Future<dynamic> Function()> _fetchers = {};
  final Map<String, DataSourceStatus> _statuses = {};
  Cache? get _cache => Cache.instanceOrNull;

  // ═══════════════════════════════════════════════════════════════════════
  // 注册
  // ═══════════════════════════════════════════════════════════════════════

  /// 注册数据类型与拉取方式。重复注册同一 name 覆盖旧 fetcher。
  void register<T>(DataType<T> type, Future<T> Function() fetcher) {
    final existed = _fetchers.containsKey(type.name);
    _types[type.name] = type;
    _fetchers[type.name] = fetcher;

    if (!existed) {
      _statuses[type.name] = DataSourceStatus(
        name: type.name,
        category: type.category,
        displayName: type.label,
        cacheKey: type.persistentKey,
        ttl: type.ttl,
      );
      Log().info('DataOrchestrator: 注册 $type (${type.category})');
    } else {
      Log().info('DataOrchestrator: 覆盖注册 $type');
    }
  }

  /// 批量注册。
  void registerAll<T>(Map<DataType<T>, Future<T> Function()> entries) {
    for (final e in entries.entries) {
      register(e.key, e.value);
    }
  }

  bool isRegistered(DataType type) => _fetchers.containsKey(type.name);
  List<String> get registeredTypes => _fetchers.keys.toList();

  /// 注销数据类型并清除缓存。
  void unregister(DataType type) {
    _types.remove(type.name);
    _fetchers.remove(type.name);
    _statuses.remove(type.name);
    _cache?.evict(type.name);
    Log().info('DataOrchestrator: 注销 $type');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 读取
  // ═══════════════════════════════════════════════════════════════════════

  /// 缓存优先获取数据。有缓存就返回（过期也返回），无缓存则拉取。
  Future<T?> get<T>(DataType<T> type) async {
    _requireRegistered(type);

    final entry = _cache?.read(type.name);
    if (entry != null) {
      final (data, cachedAt) = entry;
      _updateStatus(type.name, connected: true, fetchedAt: cachedAt);
      Log().info('DataOrchestrator: 缓存命中（跳过拉取）',
          data: {'name': type.name, 'cachedAt': cachedAt.toIso8601String(),
            'bytes': data.length});
      return _decode<T>(data);
    }

    return _fetchAndCache(type);
  }

  /// 强制重新拉取。合法则覆写缓存，非法返回 null 不覆写。
  Future<T?> refresh<T>(DataType<T> type) async {
    _requireRegistered(type);
    return _fetchAndCache(type);
  }

  /// 启动定时自动刷新（默认每 5 分钟检查一次过期数据）。
  Timer? _refreshTimer;

  void startAutoRefresh({Duration interval = const Duration(minutes: 5)}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) => refreshAllStale());
  }

  /// 停止自动刷新。
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 批量刷新过期数据。可指定 [types] 过滤。
  Future<void> refreshAllStale({List<DataType>? types}) async {
    final names = types != null ? types.map((t) => t.name).toSet() : null;
    for (final entry in _statuses.entries) {
      if (entry.value.isFresh) continue;
      if (names != null && !names.contains(entry.key)) continue;
      final type = _types[entry.key];
      if (type == null) continue;
      try {
        await refresh<dynamic>(type);
      } catch (e) {
        Log().warn('DataOrchestrator: 自动刷新失败',
            data: {'name': entry.key, 'error': e.toString()});
      }
    }
  }

  /// 清除指定类型的缓存（异步完成文件删除）。
  Future<void> invalidate(DataType type) async {
    await _cache?.evict(type.name);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 连通性
  // ═══════════════════════════════════════════════════════════════════════

  /// 单源连通性测试。
  Future<void> testConnectivity(String name) async {
    final fetcher = _fetchers[name];
    if (fetcher == null) return;
    try {
      await fetcher();
      _updateStatus(name, connected: true);
      Log().info('DataOrchestrator: 连通测试通过 ${_types[name]}');
    } catch (e) {
      _updateStatus(name, connected: false, error: e.toString());
      Log().warn('DataOrchestrator: 连通测试失败 ${_types[name]}',
          data: {'error': e.toString()});
    }
  }

  /// 全源连通性测试。
  Future<Map<String, bool>> testAllConnectivity() async {
    final results = <String, bool>{};
    for (final name in _types.keys) {
      await testConnectivity(name);
      results[name] = _statuses[name]?.connected ?? false;
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════════════════════════════════════

  /// 所有状态，按分类 + 名称排序。
  List<DataSourceStatus> get allStatuses {
    final list = _statuses.values.toList();
    list.sort((a, b) {
      final c = a.category.compareTo(b.category);
      return c != 0 ? c : a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  DataSourceStatus? status(String name) => _statuses[name];

  List<DataSourceStatus> statusByCategory(String c) =>
      _statuses.values.where((s) => s.category == c).toList();

  List<String> get categories {
    final seen = <String>{};
    final result = <String>[];
    for (final s in allStatuses) {
      if (seen.add(s.category)) result.add(s.category);
    }
    return result;
  }

  /// 恢复状态时间戳（启动时从磁盘缓存读取）。
  void refreshStatusFromDisk() {
    for (final s in _statuses.values) {
      final entry = _cache?.read(s.name);
      if (entry != null) s.lastFetchedAt = entry.$2;
    }
  }

  int get connectedCount =>
      _statuses.values.where((s) => s.connected).length;
  int get freshCount =>
      _statuses.values.where((s) => s.isFresh).length;
  int get totalCount => _statuses.length;

  // ═══════════════════════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════════════════════

  void _requireRegistered(DataType type) {
    if (!_fetchers.containsKey(type.name)) {
      throw DataTypeNotRegisteredException(type.name);
    }
  }

  void _updateStatus(String name,
      {bool connected = true, DateTime? fetchedAt, String? error}) {
    final s = _statuses[name];
    if (s == null) return;
    s.connected = connected;
    if (fetchedAt != null) s.lastFetchedAt = fetchedAt;
    s.lastError = error;
  }

  Future<T?> _fetchAndCache<T>(DataType<T> type) async {
    final fetcher = _fetchers[type.name]!;
    Log().info('DataOrchestrator: 拉取 $type');
    try {
      final data = await fetcher();

      if (data == null || data is! T) {
        _updateStatus(type.name, connected: false, error: '拉取返回无效数据');
        Log().warn('DataOrchestrator: 拉取返回无效数据 $type');
        return null;
      }

      final now = DateTime.now();
      final encoded = _encode(data);
      await _cache?.write(type.name, encoded);
      Log().info('DataOrchestrator: 缓存写入',
          data: {'name': type.name, 'bytes': encoded.length});
      _updateStatus(type.name, connected: true, fetchedAt: now);
      return data;
    } catch (e) {
      _updateStatus(type.name, connected: false, error: e.toString());
      Log().warn('DataOrchestrator: 拉取失败 $type',
          data: {'error': e.toString()});
      return null;
    }
  }

  String _encode(dynamic data) => data is String ? data : jsonEncode(data);

  T _decode<T>(String raw) {
    if (T == String) return raw as T;
    return jsonDecode(raw) as T;
  }
}

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
/// | `get(type)` | 缓存优先：读磁盘→写内存→返回；无缓存则拉取 |
/// | `fastRead(type)` | 快读：直接从内存返回，不碰磁盘 I/O；未命中 fallback get() |
/// | `fastReadByName(name)` | 快读（字符串名称版） |
/// | `refresh(type)` | 强制拉取，合法则覆写磁盘+内存缓存，非法返回 null 不覆写 |
/// | `refreshAllStale({types})` | 批量刷新过期数据 |
/// | `invalidate(type)` | 清缓存（内存+磁盘） |
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

import 'package:flutter/foundation.dart';
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

/// 内存缓存条目——保存已解码的数据与缓存时间戳，供 [fastRead] 零 I/O 读取。
class _MemCacheEntry {
  final dynamic data;
  final DateTime cachedAt;
  const _MemCacheEntry(this.data, this.cachedAt);
}

/// 数据谱仪器——持有数据类型、拉取方式、状态信息。
class DataOrchestrator {
  final Map<String, DataType> _types = {};
  final Map<String, Future<dynamic> Function()> _fetchers = {};
  final Map<String, DataSourceStatus> _statuses = {};
  final Map<String, _MemCacheEntry> _memCache = {};
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
    _memCache.remove(type.name);
    _cache?.evict(type.name);
    Log().info('DataOrchestrator: 注销 $type');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 读取
  // ═══════════════════════════════════════════════════════════════════════

  /// 缓存优先获取数据。有缓存就返回（过期也返回），无缓存则拉取。
  ///
  /// 仅当 [DataType.persistentKey] 非 null 才走缓存（见 [DataType] 文档：
  /// “不设则不缓存”）。persistentKey 为 null 时每次都重新拉取。
  ///
  /// 磁盘命中后会同步写入内存缓存，使后续 [fastRead] 零 I/O 命中。
  Future<T?> get<T>(DataType<T> type) async {
    _requireRegistered(type);

    if (type.persistentKey != null) {
      final entry = _cache?.read(type.name);
      if (entry != null) {
        final (data, cachedAt) = entry;
        final decoded = _decode<T>(data);
        _memCache[type.name] = _MemCacheEntry(decoded, cachedAt);
        _updateStatus(type.name, connected: true, fetchedAt: cachedAt);
        Log().info('DataOrchestrator: 缓存命中（跳过拉取）',
            data: {'name': type.name, 'cachedAt': cachedAt.toIso8601String(),
              'bytes': data.length});
        return decoded;
      }
    }

    debugPrint('[Orch] get: ${type.name} 无缓存，进入 _fetchAndCache');
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

  /// 按名称查找已注册的 [DataType]（无类型参数版本）。供 Agent Tool 等通过字符串名称查询。
  DataType? typeByName(String name) => _types[name];

  /// 按名称获取数据——等价于 [get] 但通过字符串名称查找 [DataType]。
  /// 供 Agent Tool 等通过字符串名称调用。
  Future<dynamic> getByName(String name) async {
    final t = _types[name];
    if (t == null) throw DataTypeNotRegisteredException(name);
    return get<dynamic>(t);
  }

  /// 快读——直接从内存缓存返回，不走磁盘 I/O。
  ///
  /// 内存未命中时自动 fallback 到 [get]（读磁盘 + 写入内存）。
  /// 供模块页面进入时快速获取已缓存数据，避免每次导航都触发磁盘读取。
  Future<T?> fastRead<T>(DataType<T> type) async {
    _requireRegistered(type);

    final mem = _memCache[type.name];
    if (mem != null) {
      _updateStatus(type.name, connected: true, fetchedAt: mem.cachedAt);
      Log().info('DataOrchestrator: 快读命中',
          data: {'name': type.name});
      return mem.data as T?;
    }

    debugPrint('[Orch] fastRead: ${type.name} 内存未命中，fallback get()');
    return get(type);
  }

  /// 按名称快读——等价于 [fastRead] 但通过字符串名称查找 [DataType]。
  Future<dynamic> fastReadByName(String name) async {
    final t = _types[name];
    if (t == null) throw DataTypeNotRegisteredException(name);
    return fastRead<dynamic>(t);
  }

  /// 按名称强制刷新数据——等价于 [refresh] 但通过字符串名称查找 [DataType]。
  Future<dynamic> refreshByName(String name) async {
    final t = _types[name];
    if (t == null) throw DataTypeNotRegisteredException(name);
    return refresh<dynamic>(t);
  }

  /// 清除指定类型的缓存（异步完成文件删除，同步清除内存缓存）。
  Future<void> invalidate(DataType type) async {
    _memCache.remove(type.name);
    await _cache?.evict(type.name);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 格式打印
  // ═══════════════════════════════════════════════════════════════════════

  /// 打印指定数据源缓存数据的格式。
  ///
  /// 不触发生成拉取，只读缓存。返回树状结构描述：
  /// - 顶层类型 + 键/元素数量
  /// - 每一层的键名、值类型、示例值（截断至 60 字符）
  /// - 数组最多展开前 3 元素，超长显示 `… 还有 N 项`
  ///
  /// 缓存不存在时返回 null。
  String? dumpDataFormat(String name) {
    final entry = _cache?.read(name);
    if (entry == null) {
      Log().info('DataOrchestrator: 格式打印失败（无缓存）',
          data: {'name': name});
      return null;
    }
    try {
      final decoded = jsonDecode(entry.$1);
      final buf = StringBuffer();
      _formatValue(buf, decoded, depth: 0, label: 'orch://$name');
      return buf.toString();
    } catch (e) {
      Log().warn('DataOrchestrator: 格式打印异常',
          data: {'name': name, 'error': e.toString()});
      return '(无法解析的数据)';
    }
  }

  /// 递归格式化某个值的结构到 [buf]。
  void _formatValue(StringBuffer buf, dynamic val,
      {required int depth, String? label}) {
    const indent = '  ';

    void w(String s, {int extra = 0}) {
      buf.write(indent * (depth + extra));
      buf.writeln(s);
    }

    void typeHint(dynamic v) {
      if (v == null) return;
      if (v is String) {
        final s = v.length > 60 ? '${v.substring(0, 57)}…' : v;
        buf.write(' = "$s"');
      } else if (v is num || v is bool) {
        buf.write(' = $v');
      }
    }

    if (val == null) {
      buf.write(label ?? '(null)');
      buf.writeln(': null');
      return;
    }
    if (val is Map) {
      buf.write(label ?? '(Map)');
      buf.writeln(': Map (${val.length} 键)');
      for (final key in val.keys) {
        final v = val[key];
        final keyLabel = '$key';
        if (v is Map) {
          w('$keyLabel:');
          _formatValue(buf, v, depth: depth + 1);
        } else if (v is List) {
          buf.write(indent * (depth + 1));
          buf.write('$keyLabel: ');
          buf.write('List (${v.length} 项)');
          typeHint(v.isEmpty ? null : v.first is Map ? null : v);
          buf.writeln();
          _expandListItems(buf, v, depth: depth + 1);
        } else {
          buf.write(indent * (depth + 1));
          buf.write('$keyLabel: ${_typeName(v)}');
          typeHint(v);
          buf.writeln();
        }
      }
    } else if (val is List) {
      buf.write(label ?? '(List)');
      buf.writeln(': List (${val.length} 项)');
      _expandListItems(buf, val, depth: depth);
    } else {
      buf.write(label ?? '(${_typeName(val)})');
      buf.write(': ${_typeName(val)}');
      typeHint(val);
      buf.writeln();
    }
  }

  void _expandListItems(StringBuffer buf, List list, {required int depth}) {
    const indent = '  ';

    void w(String s, {int extra = 0}) {
      buf.write(indent * (depth + 1 + extra));
      buf.writeln(s);
    }

    final maxExpand = 3;
    for (var i = 0; i < list.length && i < maxExpand; i++) {
      final item = list[i];
      if (item is Map) {
        buf.write(indent * (depth + 1));
        buf.writeln('[$i]: Map (${item.length} 键)');
        // 对 Map 元素只展开第一层键名
        for (final k in item.keys) {
          final v = item[k];
          buf.write(indent * (depth + 2));
          buf.write('$k: ${_typeName(v)}');
          if (v is String) {
            final s = v.length > 30 ? '${v.substring(0, 27)}…' : v;
            buf.write(' = "$s"');
          } else if (v is num || v is bool) {
            buf.write(' = $v');
          }
          buf.writeln();
        }
      } else if (item is List) {
        buf.write(indent * (depth + 1));
        buf.writeln('[$i]: List (${item.length} 项)');
      } else {
        buf.write(indent * (depth + 1));
        buf.write('[$i]: ${_typeName(item)}');
        if (item is String) {
          final s = item.length > 40 ? '${item.substring(0, 37)}…' : item;
          buf.write(' = "$s"');
        } else if (item is num || item is bool) {
          buf.write(' = $item');
        }
        buf.writeln();
      }
    }
    if (list.length > maxExpand) {
      w('… 还有 ${list.length - maxExpand} 项');
    }
  }

  String _typeName(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return 'String';
    if (v is int) return 'int';
    if (v is double) return 'double';
    if (v is num) return 'num';
    if (v is bool) return 'bool';
    if (v is Map) return 'Map';
    if (v is List) return 'List';
    return v.runtimeType.toString();
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
    debugPrint('[Orch] _fetchAndCache: 即将拉取 ${type.name}');
    Log().info('DataOrchestrator: 拉取 $type');
    try {
      final data = await fetcher();
      debugPrint('[Orch] _fetchAndCache: ${type.name} fetcher 返回: ${data != null ? "有数据" : "NULL"}');

      if (data == null || data is! T) {
        _updateStatus(type.name, connected: false, error: '拉取返回无效数据');
        Log().warn('DataOrchestrator: 拉取返回无效数据 $type');
        debugPrint('[Orch] _fetchAndCache: ${type.name} 返回无效数据(NULL或类型不匹配)');
        return null;
      }

      final now = DateTime.now();
      final encoded = _encode(data);
      if (type.persistentKey != null) {
        await _cache?.write(type.name, encoded);
        Log().info('DataOrchestrator: 缓存写入',
            data: {'name': type.name, 'bytes': encoded.length});
      }
      _memCache[type.name] = _MemCacheEntry(data, now);
      _updateStatus(type.name, connected: true, fetchedAt: now);
      return data;
    } catch (e, st) {
      _updateStatus(type.name, connected: false, error: e.toString());
      Log().warn('DataOrchestrator: 拉取失败 $type',
          data: {'error': e.toString()});
      debugPrint('[Orch] _fetchAndCache: ${type.name} 异常: $e\n$st');
      return null;
    }
  }

  String _encode(dynamic data) => data is String ? data : jsonEncode(data);

  T _decode<T>(String raw) {
    if (T == String) return raw as T;
    // jsonDecode 返回 List<dynamic>/Map<String,dynamic>，无法直接 as 具体泛型
    // （如 List<String>），否则运行期抛 TypeError。直接以 dynamic 返回，由调用方按 T 使用。
    return jsonDecode(raw);
  }
}

/// 数据谱仪器——统一注册、获取、缓存、状态追踪。
///
/// # 公开 API
///
/// ## DataOrchestrator
/// | 方法 | 说明 |
/// |------|------|
/// | `register(type, fetcher)` | 注册数据类型与拉取方式；重复覆盖 |
/// | `registerAll(entries)` | 批量注册 |
/// | `registerStream(type, fetcher)` | 注册流式数据类型（与 register 并存，同名互不覆盖） |
/// | `streamOf(type)` / `streamByName(name)` | 取流式数据流（未注册返回 null；自动接线状态映射） |
/// | `dataChangeEvents` | 数据变更事件广播流（与 addDataChangeListener 共享同一 diff 通知源） |
/// | `isRegistered(type)` | 是否已注册（pull 或流式任一） |
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
/// | `connected` | 连通状态，get / refresh / testConnectivity / 流事件 自动更新 |
/// | `lastFetchedAt` / `lastError` | 最近拉取时间 / 最近错误 |
/// | `completed` | 流式数据源是否已完成（onDone 标记，不注销） |
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
import 'data_diff.dart';
import 'session_provider.dart';
import 'plugin/data_source_manifest.dart';

/// 空数据门控触发时的 `lastError` 文案——「源可达但语义空」（fetcher 正常返回但
/// 结果为 null/空容器），与「源不可达/异常」（fetcher 抛异常，`kDataFetchFailedPrefix`）
/// 区分，供消费方/测试区分信号。
const String kDataEmptyReachableError = '源可达但数据为空';

/// 拉取失败（fetcher 抛异常）时的 `lastError` 前缀。
const String kDataFetchFailedPrefix = '拉取失败';

/// 使用静态兜底（[DataType.fallback]）时的 `lastError` 前缀。
const String kDataStaticFallbackPrefix = '使用静态兜底';

/// 会话失效重登成功但重拉仍失败时的 `lastError` 前缀。
const String kDataReloginRetryFailedPrefix = '已重登仍失败';

/// 会话失效但重登本身失败时的 `lastError` 前缀。
const String kDataReloginFailedPrefix = '重登失败';

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

  /// 流式数据源是否已完成（onDone 标记，不注销）。仅 [DataOrchestrator.registerStream]
  /// 注册的流式类型会更新此标志；pull 类型恒为 false。
  bool completed = false;

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
      lastFetchedAt != null && DateTime.now().difference(lastFetchedAt!) < ttl;

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
  final Map<String, Stream<dynamic> Function()> _streamFetchers = {};
  final Map<String, DataSourceStatus> _statuses = {};
  final Map<String, _MemCacheEntry> _memCache = {};

  /// 文件下载声明登记表（name → [DataSourceFileDecl]）。来自 manifest
  /// `dataTypes[].file`（T1 已解析），由 [registerFile] 登记，供 [fileOf] /
  /// [fileByName] 查询。未声明/未登记返回 null。
  final Map<String, DataSourceFileDecl> _fileDecls = {};
  Cache? get _cache => Cache.instanceOrNull;

  /// 会话协调器（可选，默认 null）。设置后，声明了 `sessionProviderId`
  /// （manifest `auth.sessionProvider`）的数据源在拉取失败且错误被判为「会话失效」时，
  /// 会经协调器**单点重登**后重拉一次（主题 A 登录不挤占）。缺省 null 零行为变化。
  ///
  /// app 启动期（或 T9）把 [SessionCoordinator.instance]（或独立实例）赋给本字段，
  /// 使所有数据源共享同一登录锁。
  SessionCoordinator? sessionCoordinator;

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

  /// 注册流式数据类型。与 [register]（pull 单值拉取）并存——二者用不同内部表，
  /// 同名互不覆盖；流式类型进入注册表（[status] / [typeByName] / [allStatuses] 可见），
  /// 状态复用 [DataSourceStatus]（connected/lastError/completed）。
  ///
  /// [fetcher] 为「流工厂」：每次调用返回一条新 [Stream]，供多个订阅者各取所需
  /// （如 `streamOf` / SSE 端点）。流事件自动映射状态：
  /// - onData → `connected=true`（并刷新 lastFetchedAt）
  /// - onError → `connected=false` + `lastError`
  /// - onDone → 标记 `completed=true`（**不注销**，类型仍在注册表）
  void registerStream<T>(DataType<T> type, Stream<T> Function() fetcher) {
    final existed = _statuses.containsKey(type.name);
    _types[type.name] = type;
    _streamFetchers[type.name] = fetcher;

    if (!existed) {
      _statuses[type.name] = DataSourceStatus(
        name: type.name,
        category: type.category,
        displayName: type.label,
        cacheKey: type.persistentKey,
        ttl: type.ttl,
      );
      Log().info('DataOrchestrator: 注册流式 $type (${type.category})');
    } else {
      Log().info('DataOrchestrator: 覆盖注册流式 $type');
    }
  }

  /// 是否已注册（pull 或流式任一）。
  bool isRegistered(DataType type) =>
      _fetchers.containsKey(type.name) ||
      _streamFetchers.containsKey(type.name);

  /// 已注册类型名列表（pull 与流式合并）。
  List<String> get registeredTypes =>
      {..._fetchers.keys, ..._streamFetchers.keys}.toList();

  /// 注销数据类型并清除缓存（同时清除 pull 与流式注册）。
  void unregister(DataType type) {
    _types.remove(type.name);
    _fetchers.remove(type.name);
    _streamFetchers.remove(type.name);
    _statuses.remove(type.name);
    _memCache.remove(type.name);
    _fileDecls.remove(type.name);
    _cache?.evict(type.name);
    Log().info('DataOrchestrator: 注销 $type');
  }

  /// 登记数据源的「文件下载声明」（manifest `dataTypes[].file`，T8a）。
  ///
  /// 由 [registerDataSourcesFromManifest] 在注册 DataType 时调用；[decl] 为
  /// null 时清除该名称的既有登记（重注册/未声明语义收敛）。
  void registerFile(String name, DataSourceFileDecl? decl) {
    if (decl == null) {
      _fileDecls.remove(name);
    } else {
      _fileDecls[name] = decl;
    }
  }

  /// 按 [DataType] 查询文件下载声明；未声明/未登记返回 null。
  DataSourceFileDecl? fileOf(DataType type) => _fileDecls[type.name];

  /// 按名称查询文件下载声明；未声明/未登记返回 null。
  DataSourceFileDecl? fileByName(String name) => _fileDecls[name];

  // ═══════════════════════════════════════════════════════════════════════════
  // 流式访问
  // ═══════════════════════════════════════════════════════════════════════════

  /// 按 [DataType] 取得流式数据流。未注册流式类型时返回 null。
  ///
  /// 返回的流已接线状态映射：onData → connected=true（刷新 lastFetchedAt），
  /// onError → connected=false + lastError，onDone → completed=true（不注销）。
  /// 每次调用都会经 [registerStream] 的流工厂取一条**新**流。
  Stream<T>? streamOf<T>(DataType<T> type) {
    final fetcher = _streamFetchers[type.name];
    if (fetcher == null) return null;
    return _decorateStream<T>(fetcher(), type.name);
  }

  /// 按名称取得流式数据流（无类型参数版本）。未注册返回 null。
  Stream<dynamic>? streamByName(String name) {
    final fetcher = _streamFetchers[name];
    if (fetcher == null) return null;
    return _decorateStream<dynamic>(fetcher(), name);
  }

  /// 给原始流接线状态映射（onData/onError/onDone → DataSourceStatus）。
  ///
  /// 用 `async*` 逐事件转发（而非 `Stream.transform`，避免 `Stream<dynamic>` 与
  /// `Stream<T>` 之间的 Transformer 类型不匹配），在转发前更新状态：
  /// - onData → connected=true（刷新 lastFetchedAt）
  /// - onError → connected=false + lastError，并向订阅者重新抛出该错误
  /// - onDone → completed=true（不注销），流正常结束
  Stream<T> _decorateStream<T>(Stream<dynamic> raw, String name) async* {
    try {
      await for (final data in raw) {
        _updateStatus(name, connected: true, fetchedAt: DateTime.now());
        _statuses[name]?.completed = false; // 新数据 → 流重新活跃
        yield data as T;
      }
      _statuses[name]?.completed = true; // 标记完成，不注销
      Log().info('DataOrchestrator: 流式完成 $name');
    } catch (e) {
      _updateStatus(name, connected: false, error: e.toString());
      rethrow;
    }
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
        Log().info('DataOrchestrator: 缓存命中（跳过拉取）', data: {
          'name': type.name,
          'cachedAt': cachedAt.toIso8601String(),
          'bytes': data.length
        });
        return decoded;
      }
    }

    debugPrint('[Orch] get: ${type.name} 无缓存，进入 _fetchAndCache');
    return _fetchAndCache(type);
  }

  /// 强制重新拉取。合法则覆写缓存，非法返回 null 不覆写。
  ///
  /// [notifyOnChange] 为 true 时，覆写缓存且内容变化（忽略易变字段）会发出
  /// [DataChangeEvent]；默认 false（用户主动刷新/按需拉取不打扰）。
  Future<T?> refresh<T>(DataType<T> type, {bool notifyOnChange = false}) async {
    _requireRegistered(type);
    return _fetchAndCache(type, notifyOnChange: notifyOnChange);
  }

  /// 启动定时自动刷新（默认每 5 分钟检查一次过期数据）。
  ///
  /// 后台循环刷新视为「变更通知源」：覆写缓存且内容变化时发出
  /// [DataChangeEvent]（见 [addDataChangeListener]）。
  Timer? _refreshTimer;

  void startAutoRefresh({Duration interval = const Duration(minutes: 5)}) {
    _refreshTimer?.cancel();
    _refreshTimer =
        Timer.periodic(interval, (_) => refreshAllStale(notifyOnChange: true));
  }

  /// 停止自动刷新。
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 批量刷新过期数据。可指定 [types] 过滤。
  ///
  /// [notifyOnChange] 为 true 时，成功覆写缓存且内容有变化（忽略易变字段）
  /// 会发出 [DataChangeEvent]——后台自动刷新（startAutoRefresh）即走此路径。
  Future<void> refreshAllStale(
      {List<DataType>? types, bool notifyOnChange = true}) async {
    final names = types != null ? types.map((t) => t.name).toSet() : null;
    for (final entry in _statuses.entries) {
      if (entry.value.isFresh) continue;
      if (names != null && !names.contains(entry.key)) continue;
      // 仅刷新 pull 类型；流式类型（registerStream）无 Future fetcher，跳过。
      if (!_fetchers.containsKey(entry.key)) continue;
      final type = _types[entry.key];
      if (type == null) continue;
      try {
        await refresh<dynamic>(type, notifyOnChange: notifyOnChange);
      } catch (e) {
        Log().warn('DataOrchestrator: 自动刷新失败',
            data: {'name': entry.key, 'error': e.toString()});
      }
    }
  }

  /// 按注册顺序强制串行拉取全部数据源（启动期已不再调用，保留给显式全量刷新）。
  /// 单个数据源失败只记录状态，不阻塞后续数据源。
  Future<void> refreshAllSerial(
      {List<DataType>? types, bool notifyOnChange = false}) async {
    final queue = types ?? _types.values.toList(growable: false);
    for (final type in queue) {
      if (!_fetchers.containsKey(type.name)) continue;
      try {
        await refresh<dynamic>(type, notifyOnChange: notifyOnChange);
      } catch (e) {
        Log().warn('DataOrchestrator: 启动串行拉取失败',
            data: {'name': type.name, 'error': e.toString()});
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
      Log().info('DataOrchestrator: 快读命中', data: {'name': type.name});
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
      Log().info('DataOrchestrator: 格式打印失败（无缓存）', data: {'name': name});
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
          typeHint(v.isEmpty
              ? null
              : v.first is Map
                  ? null
                  : v);
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

  int get connectedCount => _statuses.values.where((s) => s.connected).length;
  int get freshCount => _statuses.values.where((s) => s.isFresh).length;
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

  Future<T?> _fetchAndCache<T>(DataType<T> type,
      {bool notifyOnChange = false}) async {
    final fetcher = _fetchers[type.name]!;
    debugPrint('[Orch] _fetchAndCache: 即将拉取 ${type.name}');
    Log().info('DataOrchestrator: 拉取 $type');
    try {
      return await _attemptFetch<T>(type, fetcher, notifyOnChange);
    } catch (e, st) {
      debugPrint('[Orch] _fetchAndCache: ${type.name} 异常: $e\n$st');
      // 会话失效自动重登重拉（主题 A）：仅当声明了 sessionProviderId、注册了
      // provider、且错误被判为「会话失效」时触发；否则走既有降级链（零行为变化）。
      final sid = type.sessionProviderId;
      final coordinator = sessionCoordinator;
      if (sid != null &&
          sid.isNotEmpty &&
          coordinator != null &&
          coordinator.sessionProviderById(sid)?.isSessionExpired(e) == true) {
        final refreshed = await coordinator.refreshSession(sid);
        if (refreshed) {
          Log().info('DataOrchestrator: 会话失效已重登，重拉 $type');
          try {
            return await _attemptFetch<T>(type, fetcher, notifyOnChange);
          } catch (e2, st2) {
            debugPrint('[Orch] 重登后重拉仍失败: ${type.name}: $e2\n$st2');
            return _handleFinalFailure<T>(type, e2,
                prefix: kDataReloginRetryFailedPrefix);
          }
        }
        Log().warn('DataOrchestrator: 会话重登失败 $type',
            data: {'error': e.toString()});
        return _handleFinalFailure<T>(type, e,
            prefix: kDataReloginFailedPrefix);
      }
      return _handleFinalFailure<T>(type, e);
    }
  }

  /// 执行一次拉取并处理成功/空结果（空结果走空数据门控 + 静态兜底）。异常向上抛出，
  /// 由 [_fetchAndCache] 统一处理（含会话重登重拉）。
  Future<T?> _attemptFetch<T>(DataType<T> type,
      Future<dynamic> Function() fetcher, bool notifyOnChange) async {
    final data = await fetcher();
    debugPrint(
        '[Orch] _attemptFetch: ${type.name} fetcher 返回: ${data != null ? "有数据" : "NULL"}');

    if (data == null || data is! T || _isEmptyData(data)) {
      // 静态兜底（第三级降级）：源可达但返回空/无效，且无旧缓存 → 返回兜底。
      if (type.fallback != null && _readBaseline(type) == null) {
        return _applyFallback<T>(type, '$kDataStaticFallbackPrefix（源返回空数据）');
      }
      _updateStatus(type.name,
          connected: false, error: kDataEmptyReachableError);
      Log().warn('DataOrchestrator: 源可达但数据为空 $type（不覆写缓存，保留旧缓存）');
      debugPrint('[Orch] _attemptFetch: ${type.name} 返回无效/空数据(NULL/类型不匹配/空容器)');
      return null;
    }

    // diff 基线：覆写前的旧缓存（磁盘优先，其次内存）——首次拉取为 null
    final baseline = _readBaseline(type);

    final now = DateTime.now();
    final encoded = _encode(data);
    if (type.persistentKey != null) {
      await _cache?.write(type.name, encoded);
      Log().info('DataOrchestrator: 缓存写入',
          data: {'name': type.name, 'bytes': encoded.length});
    }
    _memCache[type.name] = _MemCacheEntry(data, now);
    _updateStatus(type.name, connected: true, fetchedAt: now);

    if (notifyOnChange) {
      _maybeEmitChange(type, baseline, data, now);
    }
    return data;
  }

  /// 拉取最终失败的统一处理（T4 降级链）：静态兜底（若声明且无旧缓存）→ 否则
  /// 标记 `connected=false` + `lastError`（默认前缀 [kDataFetchFailedPrefix]，
  /// 会话重登路径传 `kDataReloginRetryFailedPrefix`/`kDataReloginFailedPrefix`）。
  T? _handleFinalFailure<T>(DataType<T> type, Object e,
      {String prefix = kDataFetchFailedPrefix}) {
    // 静态兜底（第三级降级）：源不可达/异常，且无旧缓存 → 返回兜底。
    if (type.fallback != null && _readBaseline(type) == null) {
      return _applyFallback<T>(type, '$kDataStaticFallbackPrefix（$prefix: $e）');
    }
    _updateStatus(type.name, connected: false, error: '$prefix: $e');
    Log().warn('DataOrchestrator: 拉取失败 $type', data: {'error': e.toString()});
    return null;
  }

  /// 应用静态兜底：标记 `connected=false` + `lastError`（含「使用静态兜底」），
  /// 返回 [DataType.fallback] 强转为 [T]。仅当无旧缓存时由 [_fetchAndCache] 调用。
  T? _applyFallback<T>(DataType<T> type, String reason) {
    _updateStatus(type.name, connected: false, error: reason);
    Log().warn('DataOrchestrator: 拉取失败，使用静态兜底 $type', data: {
      'fallback': type.fallback is Map
          ? 'Map(${(type.fallback as Map).length} 键)'
          : type.fallback?.runtimeType.toString()
    });
    return type.fallback as T?;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 变更通知（后台刷新 diff）
  // ═══════════════════════════════════════════════════════════════════════

  final List<void Function(DataChangeEvent)> _changeListeners = [];

  /// 数据变更事件广播流。与 [addDataChangeListener] 共享同一 diff 通知源
  /// （[_maybeEmitChange] 内部转发，不二次计算 diff、不双写），供 SSE 端点
  /// （`/data/events`）与 renderer 以 `Stream` 形式消费。
  final StreamController<DataChangeEvent> _changeEventsController =
      StreamController<DataChangeEvent>.broadcast(sync: true);

  /// 数据变更事件流（broadcast）。每次 diff 通知（见 [addDataChangeListener]）
  /// 都会转发到本流。
  Stream<DataChangeEvent> get dataChangeEvents =>
      _changeEventsController.stream;

  /// 注册数据变更监听（后台循环刷新覆写缓存且内容变化时回调）。
  void addDataChangeListener(void Function(DataChangeEvent) listener) {
    _changeListeners.add(listener);
  }

  /// 移除数据变更监听。
  void removeDataChangeListener(void Function(DataChangeEvent) listener) {
    _changeListeners.remove(listener);
  }

  /// 读取覆写前的缓存基线（磁盘优先，其次内存）；无缓存返回 null。
  dynamic _readBaseline(DataType type) {
    final entry = _cache?.read(type.name);
    if (entry != null) {
      try {
        return jsonDecode(entry.$1);
      } catch (_) {
        // 非 JSON 字符串缓存（如 String 型数据源），按原文比较
        return entry.$1;
      }
    }
    return _memCache[type.name]?.data;
  }

  /// 对比新旧数据，有实质变化则发出 [DataChangeEvent]。
  void _maybeEmitChange(
      DataType type, dynamic baseline, dynamic newData, DateTime now) {
    if (baseline == null) return; // 首次拉取（无旧缓存）不算变更
    final diff = computeDataDiff(baseline, newData);
    if (!diff.hasChanges) return; // 内容未变（含仅易变字段变化）不打扰
    final event = DataChangeEvent(
      sourceName: type.name,
      displayName: type.label,
      diff: diff,
      at: now,
    );
    Log().info('DataOrchestrator: 数据变更 ${type.name} → '
        '${diff.summarize()}');
    for (final listener in List.of(_changeListeners)) {
      try {
        listener(event);
      } catch (e) {
        Log().warn('DataOrchestrator: 变更监听器异常',
            data: {'name': type.name, 'error': e.toString()});
      }
    }
    // 桥到广播流（同一 diff 通知源内部转发，不双写、不二次计算 diff）。
    // sync 广播控制器同步派发：单个流订阅者抛异常不应中断其他订阅者/回调，
    // 故包 try/catch 兜底（SSE 端点在内部已自行捕获写入错误）。
    try {
      _changeEventsController.add(event);
    } catch (e) {
      Log().warn('DataOrchestrator: 变更事件流转发异常',
          data: {'name': type.name, 'error': e.toString()});
    }
  }

  String _encode(dynamic data) => data is String ? data : jsonEncode(data);

  /// 空数据门控：拉取结果为空（null / 空白字符串 / 空集合 / 空 Map）时
  /// 视为拉取失败，不覆写磁盘 + 内存缓存，保留旧数据可用（缓存优先策略）。
  ///
  /// 语义：仅判断顶层容器是否为空——`{'courses': []}` 这类「包装了空列表的
  /// 非空 Map」不算空（结构合法，说明该源可达且有返回），由消费方自行处理。
  bool _isEmptyData(dynamic data) {
    if (data == null) return true;
    if (data is String) return data.trim().isEmpty;
    if (data is List) return data.isEmpty;
    if (data is Map) return data.isEmpty;
    if (data is Set) return data.isEmpty;
    return false;
  }

  T _decode<T>(String raw) {
    if (T == String) return raw as T;
    // jsonDecode 返回 List<dynamic>/Map<String,dynamic>，无法直接 as 具体泛型
    // （如 List<String>），否则运行期抛 TypeError。直接以 dynamic 返回，由调用方按 T 使用。
    return jsonDecode(raw);
  }
}

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
/// | `fetchPathOf(name)` | 按名称返回最近一次拉取轨迹（[DataSourceFetchPath]，未拉取过返回 null） |
/// | `fetchPaths` | 全部数据源最近拉取轨迹（看板轮询一次取全） |
///
/// ## DataFetchPhase / DataSourceFetchStep / DataSourceFetchPath（T2e 拉取阶段追踪）
/// | 符号 | 说明 |
/// |------|------|
/// | `DataFetchPhase` | 单次拉取阶段链：queued → cacheLookup → fetching → validating → caching → done / failed |
/// | `DataSourceFetchStep` | 轨迹中的一步：phase + completed + at（真实时间） |
/// | `DataSourceFetchPath` | 最近一次拉取的完整轨迹：steps + isActive + retryCount（含 toJson） |
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

/// 拉取失败但存在真实旧缓存时的 `lastError` 警告级前缀（契约⑤：有真实缓存时
/// 永不报错，失败仅警告——数据仍由缓存展示，错误不升级为硬错误）。仅无缓存且
/// 重试耗尽才用 [kDataFetchFailedPrefix]（真实失败语义）。
const String kDataFetchFailedWithCachePrefix = '拉取失败（已展示缓存数据）';

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
// DataSourceSchedulingSnapshot
// ═══════════════════════════════════════════════════════════════════════════

/// 调度可观测性快照（契约③ 数据中枢看板支撑）——同域后台重试调度状态的只读视图。
///
/// 由 [DataOrchestrator.schedulingSnapshot] 生成；**不触发任何拉取/重试**，纯
/// 读当前调度状态。字段语义：
/// - [isRetrying]：当前是否正在执行同域后台串行重试（`_domainRetryRunning`）。
/// - [pendingRetryNames]：待后台重试队列中的 name 列表（按入队顺序，已去重）。
/// - [lastBackgroundRefreshAt]：最近一次后台重试周期开始时间；null = 从未执行。
/// - [nextRefreshAt]：下一次**时钟对齐**自动刷新 tick 的推算时刻（见
///   [DataOrchestrator.startAutoRefresh]）；自动刷新未启动/已停止时为 null。
///   推算值语义：启动时 = 启动时刻 + 到下一刻度的对齐等待；此后 = 上一次 tick
///   触发时刻 + interval（Timer 相位锁定下与真实到点时间一致，允许事件循环抖动）。
/// - [domainRetryDelay] / [domainRetryMaxAttempts]：调度参数只读回显（供看板展示）。
class DataSourceSchedulingSnapshot {
  final bool isRetrying;
  final List<String> pendingRetryNames;
  final DateTime? lastBackgroundRefreshAt;
  final DateTime? nextRefreshAt;
  final Duration domainRetryDelay;
  final int domainRetryMaxAttempts;

  const DataSourceSchedulingSnapshot({
    required this.isRetrying,
    required this.pendingRetryNames,
    required this.lastBackgroundRefreshAt,
    this.nextRefreshAt,
    required this.domainRetryDelay,
    required this.domainRetryMaxAttempts,
  });

  Map<String, dynamic> toJson() => {
        'isRetrying': isRetrying,
        'pendingRetryNames': pendingRetryNames,
        'lastBackgroundRefreshAt': lastBackgroundRefreshAt?.toIso8601String(),
        'nextRefreshAt': nextRefreshAt?.toIso8601String(),
        'domainRetryDelayMs': domainRetryDelay.inMilliseconds,
        'domainRetryMaxAttempts': domainRetryMaxAttempts,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// DataFetchPhase / DataSourceFetchStep / DataSourceFetchPath
// ═══════════════════════════════════════════════════════════════════════════

/// 数据源单次拉取的阶段链（T2e 数据拉取阶段追踪，供 renderer 看板动态流程图消费）。
///
/// 一次完整的拉取（[DataOrchestrator.get]/[refresh]/[fastRead]）按序经历以下阶段：
/// - [queued]：请求进入（get/refresh/fastRead 被调用）；
/// - [cacheLookup]：缓存查找（磁盘/内存；无缓存声明的类型立即判定未命中）；
/// - [fetching]：真实拉取进行中（fetcher 执行）；
/// - [validating]：结果校验（空数据门控 / 类型检查）；
/// - [caching]：写缓存（磁盘 + 内存）；
/// - [done]：成功完成（含静态兜底返回——兜底也算有结果展示）；
/// - [failed]：最终失败（含重试耗尽、空数据门控返回）。
enum DataFetchPhase {
  queued,
  cacheLookup,
  fetching,
  validating,
  caching,
  done,
  failed,
}

/// 拉取阶段轨迹中的一个步骤——[phase] 阶段 + 该阶段是否已完成 + 到达时间。
///
/// 不变类：所有字段 final；`at` 为该阶段**到达/进入**的时刻（真实
/// [DateTime.now]，契约② 时间真实可信），阶段结束后不再变更。进行中阶段的
/// [completed] 为 false，完成后为 true（构造时按需传 [completed]）。
class DataSourceFetchStep {
  final DataFetchPhase phase;

  /// 该阶段是否已完成（false = 当前进行中）。
  final bool completed;

  /// 到达该阶段的时刻（真实墙钟时间；null 仅可能出现在显式 const 构造时）。
  final DateTime? at;

  const DataSourceFetchStep({
    required this.phase,
    this.completed = false,
    this.at,
  });

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'completed': completed,
        'at': at?.toIso8601String(),
      };
}

/// 某数据源最近一次拉取的完整轨迹（T2e）——供 renderer 看板按源轮询一次取全。
///
/// [steps] 为已发生的阶段序列（含当前进行中的，进行中阶段 [DataSourceFetchStep.completed]
/// 为 false）；[isActive] 是否正在拉取/重试中（含同域后台重试待执行/执行中）；
/// [retryCount] 该源当前轨迹累计的重试次数（与同域后台重试计数对齐：每次后台重试
/// 登记/重新入队 +1，新轨迹归零）。轨迹只保留最近一次，无历史。
class DataSourceFetchPath {
  /// 已发生的阶段序列（只读快照，顺序 = 发生顺序）。
  final List<DataSourceFetchStep> steps;

  /// 是否正在拉取/重试中（fetch 进行中，或同域后台重试待执行/执行中）。
  final bool isActive;

  /// 该源当前轨迹累计重试次数（0 = 尚无重试）。
  final int retryCount;

  const DataSourceFetchPath({
    required this.steps,
    required this.isActive,
    required this.retryCount,
  });

  Map<String, dynamic> toJson() => {
        'steps': steps.map((s) => s.toJson()).toList(),
        'isActive': isActive,
        'retryCount': retryCount,
      };
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

/// 拉取轨迹的可变构建器（T2e）——[DataSourceFetchStep]/[DataSourceFetchPath] 为
/// 不变对象，运行期在构建器内累积 steps，`fetchPathOf`/`fetchPaths` 取快照。
/// 每个数据源只保留一个构建器（最近一次轨迹，无历史，防内存膨胀）。
class _FetchPathBuilder {
  final List<DataSourceFetchStep> steps = [];

  /// 是否正在拉取/重试中（fetch 进行中，或同域后台重试待执行/执行中）。
  bool isActive = false;

  /// 当前轨迹累计重试次数（与同域后台重试登记事件对齐，新轨迹归零）。
  int retryCount = 0;

  DataSourceFetchPath snapshot() => DataSourceFetchPath(
        steps: List.unmodifiable(steps),
        isActive: isActive,
        retryCount: retryCount,
      );
}

/// 数据谱仪器——持有数据类型、拉取方式、状态信息。
class DataOrchestrator {
  final Map<String, DataType> _types = {};
  final Map<String, Future<dynamic> Function()> _fetchers = {};
  final Map<String, Stream<dynamic> Function()> _streamFetchers = {};
  final Map<String, DataSourceStatus> _statuses = {};
  final Map<String, _MemCacheEntry> _memCache = {};

  /// 同域后台重试延迟（主题 A2/T2d）。声明了 [DataType.sessionDomain] 且对应域
  /// provider 不可用（未注册/未声明）的数据源拉取失败后，立即返回失败（不堵塞
  /// 调用方/启动期并行拉取），等待该时长后在后台**串行**重试。缺省 2 秒。
  final Duration domainRetryDelay;

  /// 同域后台重试最大次数（契约④：预设所有数据真实存在，重试次数应 ≥3，实在
  /// 不行才报错）。对每个失败的数据源，后台重试循环**最多**执行该次数（每次失败
  /// 间隔 [domainRetryDelay]）；达到上限后放弃（保留 lastError，不再重试）。
  /// 缺省 3；设为 ≤0 时完全禁用同域后台重试（回到未引入后台重试前的零重试
  /// 语义，失败即放弃）。重试始终在后台 Timer 中串行执行，不堵塞调用方。
  final int domainRetryMaxAttempts;

  /// 待后台重试的数据源 name 队列（同域失败合并登记，按 name 去重）。
  final List<String> _domainRetryQueue = [];
  final Set<String> _inDomainRetryQueue = {};
  Timer? _domainRetryTimer;
  bool _domainRetryRunning = false;

  /// 每个 name 已执行的后台重试次数（name → attempts）。防无限循环的计数依据：
  /// 失败后未达 [domainRetryMaxAttempts] 则重新入队再次重试，达到上限即放弃。
  final Map<String, int> _domainRetryAttempts = {};

  /// 数据拉取阶段轨迹（T2e）——name → 最近一次拉取的轨迹构建器。`unregister`
  /// 时清理；每源只保留一个（最近一次，无历史）。
  final Map<String, _FetchPathBuilder> _fetchPaths = {};

  /// 最近一次后台重试周期开始时间（调度可观测性快照用；null = 从未执行）。
  DateTime? _lastDomainRetryAt;

  DataOrchestrator({
    this.domainRetryDelay = const Duration(seconds: 2),
    this.domainRetryMaxAttempts = 3,
  });

  /// 文件下载声明登记表（name → [DataSourceFileDecl]）。来自 manifest
  /// `dataTypes[].file`（T1 已解析），由 [registerFile] 登记，供 [fileOf] /
  /// [fileByName] 查询。未声明/未登记返回 null。
  final Map<String, DataSourceFileDecl> _fileDecls = {};
  Cache? get _cache => Cache.instanceOrNull;

  /// 会话协调器（可选，默认 null）。设置后，声明了 `sessionProviderId`
  /// （manifest `auth.sessionProvider`）的数据源在拉取失败且错误被判为「会话失效」时，
  /// 会经协调器**单点重登**后重拉一次（主题 A 登录不挤占）。缺省 null 零行为变化。
  ///
  /// 登录锁分组键 = `sessionDomain ?? sessionProviderId`：声明了 `sessionDomain`
  /// （manifest `auth.sessionDomain`，数据来源网站域）时，同一域的数据源共享同一把
  /// 登录锁；未声明时按 `sessionProviderId` 分组（与历史一致）。
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
    // 同域后台重试队列清理：已注销类型不再重试（若正被串行执行则由
    // _runDomainRetries 的 _types 判空跳过），重试计数一并清除。
    _inDomainRetryQueue.remove(type.name);
    _domainRetryQueue.remove(type.name);
    _domainRetryAttempts.remove(type.name);
    // 拉取轨迹清理：已注销类型不再追踪（其后台重试的 refresh 由 _types 判空跳过）。
    _fetchPaths.remove(type.name);
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
    _beginFetchPath(type.name);

    if (type.persistentKey != null) {
      _addCompletedStep(type.name, DataFetchPhase.cacheLookup);
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
        _finishPathDone(type.name);
        return decoded;
      }
    } else {
      // 无缓存声明：缓存查找阶段立即判定未命中（轨迹保持一致形态）。
      _addCompletedStep(type.name, DataFetchPhase.cacheLookup);
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
    _beginFetchPath(type.name);
    return _fetchAndCache(type, notifyOnChange: notifyOnChange);
  }

  /// 启动**时钟对齐**的定时自动刷新（默认每 5 分钟检查一次过期数据）。
  ///
  /// 时钟对齐语义（T2d 追加·契约② 时间真实）：首个 tick **不立即执行**——先用
  /// 单发 Timer 对齐到下一个本地墙上时钟刻度（[interval] 即刻度：5m →
  /// :00/:05/:10…；1h → 下一整点 :00；30s → :00/:30），到点执行一轮
  /// [refreshAllStale]，再转为以该刻度为相位的 periodic 持续刷新（相位锁定，
  /// 不随执行时长漂移）。对齐计算见 [durationToNextClockBoundary]。
  ///
  /// **失败源周期重试（报错 ≠ 终态）**：`refreshAllStale` 对 `isFresh == false`
  /// 的源逐一刷新——报错（connected=false）的源在**每个 tick 都会被再次尝试**，
  /// 直至成功或注销；配合同域后台重试（[domainRetryMaxAttempts] ≥ 3）与「有真实
  /// 缓存永不报错」，数据源报错后仍持续周期恢复机会。
  ///
  /// 后台循环刷新视为「变更通知源」：覆写缓存且内容变化时发出
  /// [DataChangeEvent]（见 [addDataChangeListener]）。期间
  /// [DataSourceSchedulingSnapshot.nextRefreshAt] 给出下一次 tick 的推算时刻。
  Timer? _refreshTimer;

  /// 自动刷新时间刻度（[startAutoRefresh] 的 [interval]，供 [nextRefreshAt] 推算）。
  Duration _autoRefreshInterval = const Duration(minutes: 5);

  /// 最近一次时钟对齐 tick 触发时刻（null = 尚未触发过）。
  DateTime? _lastAutoRefreshTickAt;

  /// 下一次时钟对齐 tick 的推算时刻（null = 自动刷新未启动/已停止）。
  ///
  /// 推算规则（非精确到点保证，注释说明）：启动时 = 启动时刻 + 到下一刻度的等待
  /// 时长（对齐计算值）；此后每个 tick 触发时 = 本次 tick 触发时刻 + [interval]
  /// ——即「上一次 tick 时间 + interval」。Timer 相位锁定下与真实到点时间一致，
  /// 允许事件循环抖动（推算值语义）。
  DateTime? _nextAutoRefreshAt;

  void startAutoRefresh({Duration interval = const Duration(minutes: 5)}) {
    _refreshTimer?.cancel();
    _autoRefreshInterval = interval;
    final delay = durationToNextClockBoundary(DateTime.now(), interval);
    _nextAutoRefreshAt = DateTime.now().add(delay);
    _refreshTimer = Timer(delay, () {
      _runAutoRefreshTick();
      // 首个对齐刻度已触发：转为以该时刻为相位的 periodic（相位锁定）。
      _refreshTimer = Timer.periodic(interval, (_) => _runAutoRefreshTick());
    });
    Log().info('DataOrchestrator: 时钟对齐自动刷新启动', data: {
      'intervalMs': interval.inMilliseconds,
      'firstTickDelayMs': delay.inMilliseconds,
    });
  }

  /// 执行一轮时钟对齐自动刷新，并记录 tick 时刻（供 [nextRefreshAt] 推算）。
  void _runAutoRefreshTick() {
    final now = DateTime.now();
    _lastAutoRefreshTickAt = now;
    // 推算下一 tick：本次 tick 触发时刻 + interval（见 _nextAutoRefreshAt 注释）。
    _nextAutoRefreshAt = now.add(_autoRefreshInterval);
    refreshAllStale(notifyOnChange: true);
  }

  /// 停止自动刷新。
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _nextAutoRefreshAt = null;
    _lastAutoRefreshTickAt = null;
  }

  /// 计算 [now] 到下一个「时钟对齐刻度」的等待时长（纯函数，测试友好）。
  ///
  /// 语义：以 [interval] 为刻度对齐到**本地墙上时钟**边界（5m → :00/:05/:10…；
  /// 1h → 下一整点 :00；30s → :00/:30 秒刻度）。实现：取 [now] 本地时刻自当日
  /// 零点起的毫秒数对 interval 取模，余数补足到下一边界；恰在边界上（余数为 0）
  /// 时返回一个完整 interval（跳到下一刻度，**首 tick 永不立即执行**）。
  /// [interval] <= 0 时返回 [Duration.zero]（不等待，立即触发）。
  @visibleForTesting
  static Duration durationToNextClockBoundary(DateTime now, Duration interval) {
    final ms = interval.inMilliseconds;
    if (ms <= 0) return Duration.zero;
    final dayStart = DateTime(now.year, now.month, now.day);
    final localMs =
        now.millisecondsSinceEpoch - dayStart.millisecondsSinceEpoch;
    final rem = localMs % ms;
    return Duration(milliseconds: rem == 0 ? ms : ms - rem);
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
    _beginFetchPath(type.name);

    final mem = _memCache[type.name];
    if (mem != null) {
      _addCompletedStep(type.name, DataFetchPhase.cacheLookup);
      _updateStatus(type.name, connected: true, fetchedAt: mem.cachedAt);
      Log().info('DataOrchestrator: 快读命中', data: {'name': type.name});
      _finishPathDone(type.name);
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

  /// 读取该名称数据的**真实缓存**（磁盘优先，其次内存），无缓存返回 null。
  ///
  /// 只读，**不触发任何拉取**；供「有真实缓存时永不报错」（契约⑤）的语义判定——
  /// 如 HTTP 端点拉取失败时回退缓存数据（200 + data）而非 502。磁盘缓存仅对
  /// `persistentKey` 非 null 的类型存在；内存缓存覆盖所有类型（含 persistentKey
  /// 为 null 的类型本轮会话内 refresh 过的）。返回 `(data, cachedAt)`，cachedAt
  /// 即最后一次真实写入磁盘/内存的时间标签（契约② 内存与磁盘同步的依据）。
  (dynamic data, DateTime cachedAt)? readCachedByName(String name) {
    final type = _types[name];
    if (type != null && type.persistentKey != null) {
      final entry = _cache?.read(type.name);
      if (entry != null) {
        try {
          return (jsonDecode(entry.$1), entry.$2);
        } catch (_) {
          // 非 JSON 字符串缓存（如 String 型数据源），按原文返回
          return (entry.$1, entry.$2);
        }
      }
    }
    final mem = _memCache[name];
    if (mem != null) return (mem.data, mem.cachedAt);
    return null;
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

  /// 当前调度状态快照（只读，不触发拉取/重试）。供 renderer 数据中枢看板
  /// （契约③）消费：当前是否在后台重试、待重试队列 name 列表、最近一次后台
  /// 刷新时间、下一次时钟对齐自动刷新 tick（[DataSourceSchedulingSnapshot]，
  /// 含 toJson 便于序列化）。
  DataSourceSchedulingSnapshot get schedulingSnapshot =>
      DataSourceSchedulingSnapshot(
        isRetrying: _domainRetryRunning,
        pendingRetryNames: List.of(_domainRetryQueue),
        lastBackgroundRefreshAt: _lastDomainRetryAt,
        nextRefreshAt: _nextAutoRefreshAt,
        domainRetryDelay: domainRetryDelay,
        domainRetryMaxAttempts: domainRetryMaxAttempts,
      );

  // ═══════════════════════════════════════════════════════════════════════
  // 拉取阶段轨迹（T2e 数据拉取阶段追踪）
  // ═══════════════════════════════════════════════════════════════════════

  /// 按 [name] 返回该数据源**最近一次**拉取的阶段轨迹；从未拉取过（或已注销）
  /// 返回 null。快照语义：返回对象是构建时拷贝，后续拉取不影响已取回的对象。
  DataSourceFetchPath? fetchPathOf(String name) {
    final b = _fetchPaths[name];
    if (b == null || b.steps.isEmpty) return null;
    return b.snapshot();
  }

  /// 全部数据源最近一次拉取轨迹（name → [DataSourceFetchPath]）。看板轮询一次
  /// 取全，避免逐源调用 [fetchPathOf]。仅包含已发生过拉取的源；含进行中/重试中。
  Map<String, DataSourceFetchPath> get fetchPaths {
    final result = <String, DataSourceFetchPath>{};
    _fetchPaths.forEach((name, b) {
      if (b.steps.isNotEmpty) result[name] = b.snapshot();
    });
    return result;
  }

  /// 开始一次拉取轨迹（get/refresh/fastRead 进入时）：源无轨迹或上次轨迹已终结
  /// （done/failed 且已完成）且不在重试中 → 新建轨迹并追加 `queued` 完成步骤；
  /// 轨迹仍在进行/重试中则沿用当前轨迹（不重复打 queued）。
  void _beginFetchPath(String name) {
    final b = _fetchPaths.putIfAbsent(name, () => _FetchPathBuilder());
    final last = b.steps.isEmpty ? null : b.steps.last;
    final lastTerminal = last != null &&
        last.completed &&
        (last.phase == DataFetchPhase.done ||
            last.phase == DataFetchPhase.failed);
    if (b.steps.isEmpty || (lastTerminal && !b.isActive)) {
      b.steps.clear();
      b.retryCount = 0;
      b.isActive = true;
      _addCompletedStep(name, DataFetchPhase.queued);
    }
  }

  /// 追加一个**进行中**阶段步骤（completed=false，at=now）。
  void _startStep(String name, DataFetchPhase phase) {
    final b = _fetchPaths[name];
    if (b == null) return;
    b.isActive = true;
    b.steps.add(DataSourceFetchStep(
        phase: phase, completed: false, at: DateTime.now()));
  }

  /// 把最后一个未完成的 [phase] 步骤标记为完成（保留其到达时间 at）。
  void _endStep(String name, DataFetchPhase phase) {
    final b = _fetchPaths[name];
    if (b == null) return;
    for (var i = b.steps.length - 1; i >= 0; i--) {
      final s = b.steps[i];
      if (s.phase == phase && !s.completed) {
        b.steps[i] =
            DataSourceFetchStep(phase: phase, completed: true, at: s.at);
        return;
      }
    }
  }

  /// 追加一个已完成步骤（completed=true，at=now）。
  void _addCompletedStep(String name, DataFetchPhase phase) {
    final b = _fetchPaths[name];
    if (b == null) return;
    b.steps.add(DataSourceFetchStep(
        phase: phase, completed: true, at: DateTime.now()));
  }

  /// 成功完成轨迹：追加 `done` 并收敛 isActive（同域后台重试仍在 → 保持活跃）。
  void _finishPathDone(String name) {
    _addCompletedStep(name, DataFetchPhase.done);
    _setPathActive(name, _isDomainRetrying(name));
  }

  /// 最终失败：追加 `failed` 并收敛 isActive（同域后台重试待执行/执行中 → 活跃）。
  void _appendFailedStep(String name) {
    _addCompletedStep(name, DataFetchPhase.failed);
    _setPathActive(name, _isDomainRetrying(name));
  }

  void _setPathActive(String name, bool active) {
    final b = _fetchPaths[name];
    if (b == null) return;
    b.isActive = active;
  }

  /// 该源当前是否处于同域后台重试中（待执行：在队列里；执行中：_domainRetryRunning
  /// 且已计尝试次数）。用于 [DataSourceFetchPath.isActive] 与失败步骤的活跃判定。
  bool _isDomainRetrying(String name) =>
      _inDomainRetryQueue.contains(name) ||
      (_domainRetryRunning && (_domainRetryAttempts[name] ?? 0) > 0);

  /// 轨迹 retryCount +1（与同域后台重试登记事件对齐；构建器不存在时忽略）。
  void _bumpRetryCount(String name) {
    final b = _fetchPaths[name];
    if (b == null) return;
    b.retryCount++;
  }

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
    _startStep(type.name, DataFetchPhase.fetching);
    try {
      return await _attemptFetch<T>(type, fetcher, notifyOnChange);
    } catch (e, st) {
      debugPrint('[Orch] _fetchAndCache: ${type.name} 异常: $e\n$st');
      // 异常：当前进行中阶段（fetching）标记完成（异常终结），后续按重登/降级链
      // 追加 failed 或重新进入 fetching（会话重登重拉）。
      _endStep(type.name, DataFetchPhase.fetching);
      // 会话失效自动重登重拉（主题 A）：仅当声明了 sessionProviderId、注册了
      // provider、且错误被判为「会话失效」时触发；否则走既有降级链（零行为变化）。
      // 登录锁分组键：优先 sessionDomain（同一网站域的数据源共享一把登录锁），
      // 未声明时回退 sessionProviderId（与历史一致）。
      final sid = type.sessionProviderId;
      final coordinator = sessionCoordinator;
      if (sid != null &&
          sid.isNotEmpty &&
          coordinator != null &&
          coordinator.sessionProviderById(sid)?.isSessionExpired(e) == true) {
        final lockKey = type.sessionDomain ?? sid;
        final refreshed =
            await coordinator.refreshSessionFor(lockKey, sid);
        if (refreshed) {
          Log().info('DataOrchestrator: 会话失效已重登，重拉 $type');
          // 重试链路：保留轨迹，重新进入 fetching 阶段。
          _startStep(type.name, DataFetchPhase.fetching);
          try {
            return await _attemptFetch<T>(type, fetcher, notifyOnChange);
          } catch (e2, st2) {
            debugPrint('[Orch] 重登后重拉仍失败: ${type.name}: $e2\n$st2');
            _endStep(type.name, DataFetchPhase.fetching);
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
    // fetcher 已返回：fetching 完成，进入校验阶段（空数据门控 / 类型检查）。
    _endStep(type.name, DataFetchPhase.fetching);
    _addCompletedStep(type.name, DataFetchPhase.validating);

    if (data == null || data is! T || _isEmptyData(data)) {
      // 静态兜底（第三级降级）：源可达但返回空/无效，且无旧缓存 → 返回兜底。
      if (type.fallback != null && _readBaseline(type) == null) {
        final v = _applyFallback<T>(type, '$kDataStaticFallbackPrefix（源返回空数据）');
        // 兜底也算有结果展示：轨迹收敛为 done（与看板展示语义一致）。
        _finishPathDone(type.name);
        return v;
      }
      _updateStatus(type.name,
          connected: false, error: kDataEmptyReachableError);
      Log().warn('DataOrchestrator: 源可达但数据为空 $type（不覆写缓存，保留旧缓存）');
      debugPrint('[Orch] _attemptFetch: ${type.name} 返回无效/空数据(NULL/类型不匹配/空容器)');
      _appendFailedStep(type.name);
      return null;
    }

    // diff 基线：覆写前的旧缓存（磁盘优先，其次内存）——首次拉取为 null
    final baseline = _readBaseline(type);

    final now = DateTime.now();
    final encoded = _encode(data);
    // 写缓存阶段（磁盘 + 内存）：进行中 → 完成后收敛 done。
    _startStep(type.name, DataFetchPhase.caching);
    if (type.persistentKey != null) {
      await _cache?.write(type.name, encoded);
      Log().info('DataOrchestrator: 缓存写入',
          data: {'name': type.name, 'bytes': encoded.length});
    }
    _memCache[type.name] = _MemCacheEntry(data, now);
    _endStep(type.name, DataFetchPhase.caching);
    _updateStatus(type.name, connected: true, fetchedAt: now);

    if (notifyOnChange) {
      _maybeEmitChange(type, baseline, data, now);
    }
    _finishPathDone(type.name);
    return data;
  }

  /// 拉取最终失败的统一处理（T4 降级链 + 契约⑤）：静态兜底（若声明且无旧缓存）
  /// → 否则标记 `connected=false` + `lastError`。
  ///
  /// 契约⑤（有真实缓存永不报错、失败仅警告）：当 [type] 存在真实旧缓存（磁盘或
  /// 内存，`_readBaseline(type) != null`）时，数据仍由缓存展示——`lastError` 用
  /// 警告级文案（[kDataFetchFailedWithCachePrefix] 前缀，如「拉取失败（已展示
  /// 缓存数据）」），状态可保持 `connected=false` 但错误**不升级为硬错误**；
  /// 仅无缓存且重试耗尽才用 [prefix]（真实失败语义）。空数据门控与静态兜底路径
  /// 不受影响（无缓存且失败才走兜底/报错）。
  T? _handleFinalFailure<T>(DataType<T> type, Object e,
      {String prefix = kDataFetchFailedPrefix}) {
    // 静态兜底（第三级降级）：源不可达/异常，且无旧缓存 → 返回兜底。
    if (type.fallback != null && _readBaseline(type) == null) {
      final v = _applyFallback<T>(type, '$kDataStaticFallbackPrefix（$prefix: $e）');
      // 兜底也算有结果展示：轨迹收敛为 done（与看板展示语义一致）。
      _finishPathDone(type.name);
      return v;
    }
    final hasCache = _readBaseline(type) != null;
    _updateStatus(
      type.name,
      connected: false,
      error: hasCache
          ? '$kDataFetchFailedWithCachePrefix: $e'
          : '$prefix: $e',
    );
    Log().warn('DataOrchestrator: 拉取失败 $type',
        data: {'error': e.toString(), 'servingFromCache': hasCache});
    // 同域后台重试（主题 A2/T2d）：声明了 sessionDomain 但对应域 provider 不可用时，
    // 失败不立即放弃——登记进后台串行重试队列（本路径不阻塞调用方）。
    _scheduleDomainRetry(type);
    // 轨迹：追加 failed；若将登记/正在执行同域后台重试 → isActive=true（重试未终）。
    _appendFailedStep(type.name);
    return null;
  }

  /// 同域后台重试调度——登记 [type] 并（首次）启动延迟 Timer。
  ///
  /// 触发条件：声明了 [DataType.sessionDomain]，且该域 provider 不可用
  /// （`sessionProviderId` 未声明 / coordinator 未设置 / provider 未注册）——
  /// 即会话重登链路不可用时的兜底重试。满足条件则入队（按 name 去重），
  /// 并在队列从空到非空时启动一个 [domainRetryDelay] 的 Timer。
  ///
  /// **不堵塞**：登记本身是同步 O(1)，重试在后台 Timer 中串行执行；
  /// 调用方（含 app 启动期的并行 `get`/`refreshAllStale`）拿到失败结果即继续。
  ///
  /// 防无限循环（契约④）：计数依据 [_domainRetryAttempts]——[_domainRetryRunning]
  /// 为 true（正在执行后台重试）时不再登记；重试循环内由 _runDomainRetries 按
  /// 每个 name 的已重试次数判定：未达 [domainRetryMaxAttempts] 重新入队，
  /// 达到上限即放弃。
  ///
  /// 返回是否本次真正登记入队（已去重/已入队返回 false），供轨迹重试计数对齐。
  bool _scheduleDomainRetry(DataType type) {
    if (_domainRetryRunning) return false;
    if (domainRetryMaxAttempts <= 0) return false; // 配置为不重试
    final domain = type.sessionDomain;
    if (domain == null || domain.isEmpty) return false;
    if (_hasUsableProvider(type)) return false; // 有 provider → 走会话重登，不重复兜底
    if (!_inDomainRetryQueue.add(type.name)) return false; // 已在队列
    // 登记重试计数（0 = 尚未执行过后台重试）；前一轮失败重新入队的 name 已在
    // _runDomainRetries 内维护计数，此处仅新登记（putIfAbsent 幂等）。
    _domainRetryAttempts.putIfAbsent(type.name, () => 0);
    _domainRetryQueue.add(type.name);
    // 轨迹 retryCount +1（该源累计重试次数，与后台重试登记对齐）。
    _bumpRetryCount(type.name);
    _domainRetryTimer ??= Timer(domainRetryDelay, _runDomainRetries);
    Log().info('DataOrchestrator: 同域失败已登记后台重试 $type',
        data: {
          'domain': domain,
          'delayMs': domainRetryDelay.inMilliseconds,
          'maxAttempts': domainRetryMaxAttempts,
        });
    return true;
  }

  /// 该类型是否有可用的会话 provider（重登链路可用则后台重试不介入）。
  bool _hasUsableProvider(DataType type) {
    final sid = type.sessionProviderId;
    if (sid == null || sid.isEmpty) return false;
    final coordinator = sessionCoordinator;
    if (coordinator == null) return false;
    return coordinator.sessionProviderById(sid) != null;
  }

  /// 执行后台串行重试（契约④：重试次数 ≥3，实在不行才报错）：取出队列快照
  /// （清空后逐项 `refresh`），单源失败只记录不阻塞后续；重试成功即覆写缓存 +
  /// 恢复状态，失败且未达 [domainRetryMaxAttempts] 则**重新入队**（等待下一个
  /// [domainRetryDelay] 周期再次重试），达到上限即放弃（保留 lastError）。
  /// 防无限循环依据 [_domainRetryAttempts] 计数：每轮对每个 name 计一次，
  /// 超过上限不再入队。重试始终在后台 Timer 中串行执行，不堵塞调用方。
  Future<void> _runDomainRetries() async {
    _domainRetryTimer = null;
    _domainRetryRunning = true;
    _lastDomainRetryAt = DateTime.now();
    try {
      final names = List.of(_domainRetryQueue);
      _domainRetryQueue.clear();
      _inDomainRetryQueue.clear();
      Log().info('DataOrchestrator: 同域后台串行重试开始',
          data: {'count': names.length});
      for (final name in names) {
        final type = _types[name];
        if (type == null) {
          _domainRetryAttempts.remove(name); // 已被注销，清理计数
          continue;
        }
        if (!_fetchers.containsKey(type.name)) continue;
        final attempt = (_domainRetryAttempts[name] ?? 0) + 1;
        _domainRetryAttempts[name] = attempt;
        dynamic data;
        try {
          Log().info('DataOrchestrator: 后台重试拉取 $type '
              '(第 $attempt 次/最多 $domainRetryMaxAttempts 次)');
          data = await refresh<dynamic>(type);
        } catch (e) {
          // refresh 内部已把 fetcher 异常收敛为 null 返回，正常不会走到；
          // 防御性捕获（如 fetcher 外层的意外异常）。
          Log().warn('DataOrchestrator: 后台重试拉取异常 $type',
              data: {'error': e.toString()});
        }
        if (data != null) {
          // 重试拿到数据（真实或静态兜底）→ 本次失败周期结束，不再重试。
          _domainRetryAttempts.remove(name);
          // 轨迹：重试成功（refresh 已打 done 步骤）→ 收敛 isActive=false。
          _setPathActive(name, false);
          continue;
        }
        Log().warn('DataOrchestrator: 后台重试失败 $type',
            data: {'error': _statuses[name]?.lastError, 'attempt': attempt});
        if (attempt < domainRetryMaxAttempts) {
          // 未达上限：重新入队，等待下一个 Timer 周期再次重试（计数保留）。
          if (_inDomainRetryQueue.add(name)) {
            _domainRetryQueue.add(name);
            // 轨迹 retryCount +1（累计重试次数与登记事件对齐）。
            _bumpRetryCount(name);
          }
        } else {
          // 达到上限：放弃，保留 lastError（不再重试）。
          _domainRetryAttempts.remove(name);
          // 轨迹：重试耗尽 → 终结（failed 步骤已由 _handleFinalFailure 追加）。
          _setPathActive(name, false);
          Log().warn('DataOrchestrator: 同域后台重试已达上限，放弃 $type',
              data: {'attempt': attempt, 'maxAttempts': domainRetryMaxAttempts});
        }
      }
    } finally {
      _domainRetryRunning = false;
      // 队列非空（本轮失败重新入队 / 周期内新登记）→ 启动下一个周期。
      if (_domainRetryQueue.isNotEmpty && _domainRetryTimer == null) {
        _domainRetryTimer = Timer(domainRetryDelay, _runDomainRetries);
      }
    }
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

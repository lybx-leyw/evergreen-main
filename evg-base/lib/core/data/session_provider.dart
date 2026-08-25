/// 平台级会话提供者抽象 + 登录锁/会话协调器（主题 A 核心）。
///
/// 把 ZJU 范本（`zju_session.dart`）的「SSO 登录 → 会话落盘复用 → 会话失效自动重登重放」
/// 泛化为**可注册的 provider**：每个服务声明一个 [SessionProvider.sessionProviderId]
/// （与数据源 manifest `auth.sessionProvider` 对齐），数据层拉取失败且错误被判为
/// 「会话失效」时，经 [SessionCoordinator] **单点重登**后重拉一次。
///
/// # 解决「登录挤占」
/// - **登录锁（Future 共享）**：同一 `sessionProviderId` 的并发 [SessionCoordinator.ensureSession]
///   排队复用同一个 in-flight Future——多插件各自登录互踢的问题被消灭，只触发一次真实登录。
/// - **单点重登**：会话失效后 [SessionCoordinator.refreshSession] 只触发一次
///   [SessionProvider.refreshSession]，其余等待者复用新会话（而非各插件各自重登）。
///
/// 本文件是**机制**（抽象 + 注册表 + 协调器 + 最小示例 provider）；zju 等具体 provider
/// 归 T9 注册。缺省（未声明 auth / 未注册 provider）零行为变化。
library session_provider;

import 'dart:async';

/// 会话提供者——抽象登录 / 会话恢复 / 失效检测 / 重登 / 登出。
///
/// 实现约定：
/// - 所有方法**不抛异常**：[ensureSession]/[refreshSession] 失败返回 `false`，
///   [invalidate] 吞异常；这保证共享 Future 不被单个 provider 的异常污染。
/// - [isSessionExpired] 判断某错误是否为「登录态失效」（如 401/403/会话过期），
///   供数据层在拉取失败时识别是否需要自动重登。
abstract class SessionProvider {
  /// 会话提供者标识（与 manifest `auth.sessionProvider` 对齐，如 `"zju"`）。
  String get sessionProviderId;

  /// 登录 / 恢复会话。已有有效会话时直接返回 true（复用，不重复登录）。
  Future<bool> ensureSession();

  /// 判断 [error] 是否为「登录态失效」（需要重登）。
  bool isSessionExpired(Object error);

  /// 重登（会话失效后）。成功返回 true。
  Future<bool> refreshSession();

  /// 登出 / 清会话。
  Future<void> invalidate();
}

/// 登录锁 / 会话协调器——同一 [SessionProvider] 的并发 `ensureSession`/`refreshSession`
/// 排队复用（Future 共享），杜绝多插件各自登录互踢；会话失效后**单点重登**。
class SessionCoordinator {
  /// 应用级共享实例——app 启动期经此注册 zju 等 provider，所有 DataOrchestrator 复用，
  /// 实现「一处登录、多处复用」。
  static final SessionCoordinator instance = SessionCoordinator();

  SessionCoordinator();

  final Map<String, SessionProvider> _providers = {};
  final Map<String, Future<bool>> _inflightEnsure = {};
  final Map<String, Future<bool>> _inflightRefresh = {};

  /// 注册 provider（按 [id] 索引，覆盖同名旧注册）。
  ///
  /// [id] 应与 manifest `auth.sessionProvider` 对齐（通常等于
  /// [SessionProvider.sessionProviderId]）；调用方也常传 `provider.sessionProviderId`。
  void registerSessionProvider(String id, SessionProvider provider) {
    _providers[id] = provider;
  }

  /// 注销 provider。
  void unregisterSessionProvider(String id) {
    _providers.remove(id);
    _inflightEnsure.remove(id);
    _inflightRefresh.remove(id);
  }

  /// 按 id 查找 provider；未注册返回 null。
  SessionProvider? sessionProviderById(String id) => _providers[id];

  /// 是否已注册。
  bool hasProvider(String id) => _providers.containsKey(id);

  /// 登录 / 恢复会话（登录锁）：并发调用共享同一 in-flight Future，只触发一次真实登录。
  Future<bool> ensureSession(String id) =>
      _dedupe(id, _inflightEnsure, _providers[id], (p) => p.ensureSession());

  /// 单点重登（登录锁）：并发调用共享同一 Future，只触发一次
  /// [SessionProvider.refreshSession]，其余等待者复用新会话。
  Future<bool> refreshSession(String id) =>
      _dedupe(id, _inflightRefresh, _providers[id], (p) => p.refreshSession());

  /// 登出 / 清会话。
  Future<void> invalidate(String id) async {
    final provider = _providers[id];
    if (provider == null) return;
    try {
      await provider.invalidate();
    } catch (_) {
      /* 登出失败不阻断 */
    }
  }

  /// 共享 in-flight Future 的去重核心：
  /// - 已有同 id in-flight Future → 直接返回（复用，不二次登录）；
  /// - 否则立即触发 [action]，完成后从 in-flight 表移除（`identical` 守卫防止旧
  ///   completion 误删新一轮 entry），并把异常收敛为 `false`。
  Future<bool> _dedupe(
    String id,
    Map<String, Future<bool>> inflight,
    SessionProvider? provider,
    Future<bool> Function(SessionProvider) action,
  ) {
    final existing = inflight[id];
    if (existing != null) return existing;
    if (provider == null) return Future.value(false);
    late final Future<bool> fut;
    fut = action(provider)
        .then((v) => v, onError: (_) => false)
        .whenComplete(() {
      if (identical(inflight[id], fut)) inflight.remove(id);
    });
    inflight[id] = fut;
    return fut;
  }
}

/// 最小可测示例 provider——内存态会话，演示 [SessionProvider] 契约与登录锁协同。
///
/// 真实 provider（如 zju 的 SSO/CAS 会话）由 T9 注册；本类仅供测试 / 演示，
/// 各回调缺省为「总是成功 / 永不失效」。
class InMemorySessionProvider implements SessionProvider {
  @override
  final String sessionProviderId;

  final Future<bool> Function() _onEnsure;
  final bool Function(Object error) _onExpired;
  final Future<bool> Function() _onRefresh;

  /// 真实 [ensureSession] 调用次数（登录锁验证用）。
  int ensureCalls = 0;

  /// 真实 [refreshSession] 调用次数（单点重登验证用）。
  int refreshCalls = 0;

  InMemorySessionProvider({
    required this.sessionProviderId,
    Future<bool> Function()? onEnsure,
    bool Function(Object error)? onExpired,
    Future<bool> Function()? onRefresh,
  })  : _onEnsure = onEnsure ?? (() async => true),
        _onExpired = onExpired ?? ((_) => false),
        _onRefresh = onRefresh ?? (() async => true);

  @override
  Future<bool> ensureSession() {
    ensureCalls++;
    return _onEnsure();
  }

  @override
  bool isSessionExpired(Object error) => _onExpired(error);

  @override
  Future<bool> refreshSession() {
    refreshCalls++;
    return _onRefresh();
  }

  @override
  Future<void> invalidate() async {}
}

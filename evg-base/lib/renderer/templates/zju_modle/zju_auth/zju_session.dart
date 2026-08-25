/// zju fetcher 共享会话——数据中枢 fetcher（bootstrap 环境，无 Riverpod）复用。
///
/// B3（2026-08-12）新增：9+ fetcher 共用同一 Dio 与 SSO 会话，避免冷缓存时
/// CAS 并发登录被节流（规划 §5.3 风险缓解）。凭证走 evg-base 设置中枢
/// （ZJU_USERNAME / ZJU_PASSWORD，B1 已迁移）；cookie 落 `.greenix/`（B1）。
library;

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/data/session_provider.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/stream_source.dart';

import 'auth_interceptor.dart';
import 'auth_service.dart';
import 'cookie_store.dart';
import 'debug_interceptor.dart';
import 'network_config.dart';
import 'retry_interceptor.dart';
import 'zjuam_service.dart';
import '../zdbk/services/zdbk_service.dart';

/// 模块级 prefs——供会话过期后的自动重登（[_zjuRelogin]）读取凭证。
/// 由 [ensureZjuSession] 首次调用时赋值（fetcher 注册期传入，见
/// `zju_data_sources.registerZjuDataSources`）。
SharedPreferences? _zjuPrefs;

/// Dio 挂载的持久 cookie jar（模块级共享）——[_zjuRelogin] 重登后必须把新
/// SSO cookie 注入**同一个** jar，CookieManager 才能携带（参考实现同款：
/// auth_provider 持有 jar 字段，login 时 `_cookieJar.saveFromResponse`）。
PersistCookieJar? _zjuCookieJar;

/// 重新走一遍 SSO 登录（AuthInterceptor 会话过期回调）。
///
/// 与 [ensureZjuSession] 首登逻辑完全一致（读凭证 → RSA 登录 → SSO cookie
/// 落盘/注入 → courses 会话），返回是否成功；失败时 AuthInterceptor 将原
/// 错误透传，UI 经 orchestrator.lastError 展示可读信息。
Future<bool> _zjuRelogin() async {
  final prefs = _zjuPrefs;
  final cookieJar = _zjuCookieJar;
  if (prefs == null || cookieJar == null) return false;
  final username = getSetting(prefs, 'ZJU_USERNAME');
  final password = getSetting(prefs, 'ZJU_PASSWORD');
  if (username.isEmpty || password.isEmpty) {
    Log().warn('[zju] relogin 失败：未配置学号密码');
    return false;
  }
  Log().info('[zju] 会话过期，执行 SSO 自动重登…', data: {'username': username});
  final httpClient = HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  try {
    final ssoResult = await ZjuAmService(httpClient).login(username, password);
    final ssoCookie = ssoResult.fold(
      (c) => c,
      (err) {
        Log().warn('[zju] relogin SSO 登录失败', data: {'error': err.userMessage});
        return null;
      },
    );
    if (ssoCookie == null) return false;

    final store = await CookieStore.getInstance();
    await store.setSsoCookie(ssoCookie.value);
    await _injectSsoCookie(cookieJar, ssoCookie.value);

    final login = await AuthService(httpClient, cookieJar).loginCourses(ssoCookie);
    if (!login.ok) {
      Log().warn('[zju] relogin courses 会话换取失败', data: {'error': login.error});
    }
    // 智云课堂 CMC 域会话同步重建——会话过期后 classroom.zju.edu.cn /
    // tgmedia / education / yjapi.cmc.zju.edu.cn 4 域 cookie 一并失效。
    await _ensureClassroomSession(httpClient, cookieJar, ssoCookie.value);
    Log().info('[zju] SSO 自动重登完成');
    return true;
  } catch (e) {
    Log().warn('[zju] relogin 异常', data: {'error': e.toString()});
    return false;
  } finally {
    httpClient.close(force: true);
  }
}

/// 构建带持久 cookie jar 的 Dio，并确保 ZJU SSO 会话可用。
///
/// 优先级：
/// 1. CookieStore 已持久化 SSO cookie → 注入 jar，直接返回（各子系统 cookie
///    若过期由 service 层报「返回网页」并引导重新登录）；
/// 2. 无 cookie → 读凭证（ZJU_USERNAME/ZJU_PASSWORD）→ [ZjuAmService] RSA
///    登录 → [AuthService.loginCourses] 换取 courses 会话 → 落盘后返回。
///
/// 未配置凭证时抛 [StateError]（用户可读中文，数据中枢捕获后置
/// connected=false，UI 经 status.lastError 显示「前往设置填写」引导）。
///
/// Dio 拦截器配置对齐参考 `dioClientProvider`：Debug / CookieManager /
/// AuthInterceptor（会话过期自动重登 + 原请求重放）/ RetryInterceptor
/// （429/502/503/连接错误指数退避重试）。此前只挂 CookieManager，SSO 过期
/// 时 401/403（智云课堂）/ 901（zdbk）直接冒泡导致拉取失败——见日志
/// `课程列表无权限` 与 `DioException bad response 901`。
Future<Dio> ensureZjuSession({required SharedPreferences prefs}) async {
  _zjuPrefs = prefs;
  final cookieJar = PersistCookieJar(storage: FileStorage(cookieJarPath));
  _zjuCookieJar = cookieJar;
  final dio = Dio(BaseOptions(
    connectTimeout: NetworkConfig.connectTimeout,
    receiveTimeout: NetworkConfig.receiveTimeout,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
  ));
  dio.interceptors.addAll([
    DebugInterceptor(maxBodyLength: 500),
    CookieManager(cookieJar),
    AuthInterceptor(dio, cookieJar),
    RetryInterceptor(dio, maxRetries: NetworkConfig.maxRetries),
  ]);
  AuthInterceptor.onRelogin = _zjuRelogin;

  final store = await CookieStore.getInstance();
  final sso = store.ssoCookie;
  if (sso != null && sso.isNotEmpty) {
    Log().info('[zju] ensureZjuSession: 复用持久化 SSO cookie');
    await _injectSsoCookie(cookieJar, sso);
    // 智云课堂 CMC 域会话可能缺失/过期（旧版本从未换取）——总是尝试补全，
    // 失败仅警告不阻塞 courses 会话；后续 classroom 请求由
    // AuthInterceptor relogin 兜底重试。
    final httpClient = HttpClient()
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
    try {
      await _ensureClassroomSession(httpClient, cookieJar, sso);
    } finally {
      httpClient.close(force: true);
    }
    return dio;
  }

  Log().info('[zju] ensureZjuSession: 无持久 cookie，执行 SSO 登录');
  final ssoCookie = await _ssoLogin(prefs);
  await _injectSsoCookie(cookieJar, ssoCookie.value);

  // 换取 courses 会话（courses.zju.edu.cn cookie 落盘到 jar）。
  final httpClient = HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  try {
    final login = await AuthService(httpClient, cookieJar).loginCourses(ssoCookie);
    if (!login.ok) {
      Log().warn('[zju] ensureZjuSession: courses 会话换取失败',
          data: {'error': login.error});
    }
    // 智云课堂 CMC 域会话（4 域 cookie 落盘到 jar）。
    await _ensureClassroomSession(httpClient, cookieJar, ssoCookie.value);
  } finally {
    httpClient.close(force: true);
  }
  Log().info('[zju] ensureZjuSession: SSO 登录完成，返回带 cookie 的 Dio');
  return dio;
}

/// 换取智云课堂 CMC 域会话 cookie 并写入 jar。
///
/// 参考 `AuthService._loginClassroom`：从 tgmedia.cmc.zju.edu.cn 发起
/// CAS 跳转，沿途收集 Set-Cookie 并保存到 classroom.zju.edu.cn /
/// tgmedia / education / yjapi.cmc.zju.edu.cn 4 个域——智云课堂 API
/// 仅认该域会话，只有 `.zju.edu.cn` 的 iPlanetDirectoryPro 会 401/403。
///
/// 失败仅记日志（不阻塞 courses 会话）。
Future<void> _ensureClassroomSession(
  HttpClient httpClient,
  PersistCookieJar cookieJar,
  String ssoValue,
) async {
  final ssoCookie = Cookie('iPlanetDirectoryPro', ssoValue)
    ..domain = '.zju.edu.cn'
    ..path = '/';
  final login =
      await AuthService(httpClient, cookieJar).loginClassroom(ssoCookie);
  if (!login.ok) {
    Log().warn('[zju] ensureZjuSession: 智云课堂会话换取失败',
        data: {'error': login.error});
  } else {
    Log().info('[zju] ensureZjuSession: 智云课堂 CMC 域会话就绪');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ZDBK 教务会话（HttpClient 版，B4-fix 对齐参考 zdbk_provider）
// ═══════════════════════════════════════════════════════════════════════

Future<ZjuZdbkService>? _zdbkSessionFuture;

/// 懒加载共享 ZDBK 教务会话——SSO cookie → HttpClient → [ZjuZdbkService.login]。
///
/// 对齐参考 `zdbk_provider`：`if (!service.isLoggedIn) await service.login(
/// httpClient, auth.ssoCookie!)`。返回已登录的 [ZjuZdbkService]，查询方法
/// 统一传 `service.httpClient`。
///
/// SSO cookie 优先级：持久化 cookie（CookieStore）→ 完整 SSO 登录（[_ssoLogin]）。
/// 会话过期由 service 内部 `_withAutoRelogin` 自动重登，无需重建。
///
/// **失败不缓存**：`_createZdbkSession` 抛错时经 [_guardedZdbkSession] 复位
/// `_zdbkSessionFuture`——否则失败的 future 被 `??=` 永久缓存，之后所有 zdbk
/// fetcher 都 await 同一个失败 future，错误持续复现（只有重登成功/清登录态
/// 才能恢复）。
Future<ZjuZdbkService> ensureZdbkSession({required SharedPreferences prefs}) {
  _zjuPrefs = prefs;
  return _zdbkSessionFuture ??= _guardedZdbkSession(prefs);
}

/// [_createZdbkSession] 失败防护包装：抛错时复位共享缓存并原样重抛。
///
/// 注意：async 函数返回的 future 被 `??=` 立即缓存，内部失败发生在缓存建立
/// **之后**，此时复位 `_zdbkSessionFuture = null` 才真正生效（若在
/// `_createZdbkSession` 内复位会被 `??=` 的赋值覆盖回去）。
Future<ZjuZdbkService> _guardedZdbkSession(SharedPreferences prefs) async {
  try {
    return await _createZdbkSession(prefs);
  } catch (_) {
    _zdbkSessionFuture = null;
    rethrow;
  }
}

Future<ZjuZdbkService> _createZdbkSession(SharedPreferences prefs) async {
  final store = await CookieStore.getInstance();
  var sso = store.ssoCookie;
  if (sso == null || sso.isEmpty) {
    Log().info('[zju] ensureZdbkSession: 无持久 SSO cookie，执行完整 SSO 登录');
    sso = (await _ssoLogin(prefs)).value;
  }

  final httpClient = HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  final service = ZjuZdbkService();
  var ok = await service.login(
    httpClient,
    Cookie('iPlanetDirectoryPro', sso)..domain = '.zju.edu.cn',
  );
  if (!ok && (store.ssoCookie?.isNotEmpty ?? false)) {
    // 持久 SSO cookie 已过期/被服务端踢下线（CAS 无重定向）——读凭证完整
    // SSO 重登一次再重建教务会话，对齐 Dio 路径 AuthInterceptor →
    // [_zjuRelogin] 的「cookie 失效 → 凭证重登」兜底，避免直接报错让用户
    // 手动重登。仍失败才抛错。
    Log().info('[zju] ensureZdbkSession: 持久 SSO cookie 登录失败，凭证重登…');
    sso = (await _ssoLogin(prefs)).value;
    ok = await service.login(
      httpClient,
      Cookie('iPlanetDirectoryPro', sso)..domain = '.zju.edu.cn',
    );
  }
  if (!ok) {
    // 抛 ZdbkAuthError（而非裸 StateError）：zjuIsSessionExpiredError 识别
    // ZdbkAuthError 为会话失效 → DataOrchestrator 经 SessionCoordinator
    // 单点重登（登录锁防挤占）后重拉，而非直接把错误展示给用户。
    throw const ZdbkAuthError('ZDBK 教务登录失败——SSO 会话无效或已过期，请重新登录');
  }
  return service;
}

/// 完整 SSO 登录（读凭证 → RSA 登录 → SSO cookie 落盘），返回 [Cookie]。
///
/// 供 [ensureZjuSession]（courses/classroom Dio 会话）与 [ensureZdbkSession]
/// （教务 HttpClient 会话）复用，避免两处重复实现。
Future<Cookie> _ssoLogin(SharedPreferences prefs) async {
  final username = getSetting(prefs, 'ZJU_USERNAME');
  final password = getSetting(prefs, 'ZJU_PASSWORD');
  if (username.isEmpty || password.isEmpty) {
    throw StateError('未配置浙大学号密码——请先在「设置」中填写 ZJU_USERNAME / ZJU_PASSWORD');
  }

  Log().info('[zju] SSO 登录', data: {'username': username});
  final httpClient = HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  try {
    final ssoResult = await ZjuAmService(httpClient).login(username, password);
    final ssoCookie = ssoResult.fold(
      (c) => c,
      (err) => throw StateError('SSO 登录失败：${err.userMessage}'),
    );
    final store = await CookieStore.getInstance();
    await store.setSsoCookie(ssoCookie.value);
    Log().info('[zju] SSO 登录完成');
    return ssoCookie;
  } finally {
    httpClient.close(force: true);
  }
}

/// 把持久化 SSO cookie 注入 jar（zjuam 域），供 CookieManager 后续携带。
Future<void> _injectSsoCookie(PersistCookieJar jar, String value) async {
  final cookie = Cookie('iPlanetDirectoryPro', value)
    ..domain = '.zju.edu.cn'
    ..path = '/';
  final uri = Uri.parse('https://zjuam.zju.edu.cn');
  await jar.delete(uri);
  await jar.saveFromResponse(uri, [cookie]);
}

/// 生成视频播放所需的 HTTP 请求头（Cookie + Referer）。
///
/// media_kit 在桌面端/安卓端以独立播放器进程拉取视频流，**不会**自动携带
/// Dio 的 cookie jar——而智云课堂视频流（tgmedia.cmc.zju.edu.cn 等 CMC 域）
/// 依赖登录会话，不带 cookie 请求会 401/403 → 黑屏。此处把 jar 中与该域
/// 匹配的 cookie 拼成 `Cookie` 头，由 [VideoPlayerPanel] 通过
/// `Media(httpHeaders: ...)` 注入。
///
/// 返回空 Map 表示 jar 未就绪（如用户尚未登录），此时播放器按原样请求，
/// 失败由 UI 错误提示兜底。
///
/// [jar] 可注入自定义 jar（单测用）；默认取模块级共享 [PersistCookieJar]
/// （[ensureZjuSession] 首次调用后建立）。
Future<Map<String, String>> zjuVideoHttpHeaders({PersistCookieJar? jar}) async {
  final j = jar ?? _zjuCookieJar;
  if (j == null) return const {};
  // 覆盖智云课堂视频流涉及的 CMC 域 + 通配 .zju.edu.cn（iPlanetDirectoryPro）。
  final uris = <Uri>[
    Uri.parse('https://tgmedia.cmc.zju.edu.cn/'),
    Uri.parse('https://yjapi.cmc.zju.edu.cn/'),
    Uri.parse('https://education.cmc.zju.edu.cn/'),
    Uri.parse('https://classroom.zju.edu.cn/'),
  ];
  final cookiePairs = <String>{};
  for (final uri in uris) {
    try {
      final cookies = await j.loadForRequest(uri);
      for (final c in cookies) {
        cookiePairs.add('${c.name}=${c.value}');
      }
    } catch (_) {
      /* 单域读取失败不影响其他域 */
    }
  }
  if (cookiePairs.isEmpty) return const {};
  return {
    'Cookie': cookiePairs.join('; '),
    'Referer': 'https://classroom.zju.edu.cn/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  };
}

// ═══════════════════════════════════════════════════════════════════════
// T9：SessionProvider 封装 + 媒体凭据头 provider（平台会话中心接入）
// ═══════════════════════════════════════════════════════════════════════

/// 判定某错误是否为「登录态失效」（供 [SessionProvider.isSessionExpired] 复用）。
///
/// 覆盖两类 fetcher 抛错形态（探索报告 C.3 + T9 §2）：
/// - Dio 路径（courses / classroom）：[DioException] 的 301/302/303（CAS 重定向）、
///   401/403（智云课堂）、901（zdbk 专属）、响应体 CAS 页特征——与
///   [AuthInterceptor] 的过期判定逐条对齐（AuthInterceptor 重登失败后透传该错误）。
/// - zdbk 路径：[ZdbkAuthError]（zdbk_service 的 `_withAutoRelogin` 耗尽重登后上抛）。
bool zjuIsSessionExpiredError(Object error) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code == 301 || code == 302 || code == 303) return true;
    if (code == 401 || code == 403 || code == 901) return true;
    final data = error.response?.data;
    if (data is String) {
      return data.contains('login_ssologin') ||
          data.contains('cas/login') ||
          data.contains('统一身份认证');
    }
    return false;
  }
  if (error is ZdbkAuthError) return true;
  // 兜底：非本层包装的会话过期异常（按类型名识别，避免误判普通 StateError）。
  return error.toString().contains('ZdbkAuthError');
}

/// 会话失效后的强制重登（[SessionProvider.refreshSession] 复用 [_zjuRelogin]）。
///
/// 相对 [_zjuRelogin]：允许注入 [prefs]（provider 持有）；成功后复位 zdbk 会话
/// 缓存，使下一次 zdbk 拉取用新 SSO cookie 重建教务会话；并兜底处理「jar 未建立」
/// 的纯 zdbk 路径（此时无共享 jar 可注入，仅做完整 SSO 重登 + 落盘）。
Future<bool> zjuRefreshSession({SharedPreferences? prefs}) async {
  if (prefs != null) _zjuPrefs = prefs;
  final jar = _zjuCookieJar;
  if (jar == null) {
    // 纯 zdbk 路径：尚未构建 courses/classroom 共享 jar。仍执行完整 SSO 重登
    // （SSO cookie 落盘 CookieStore），zdbk 会话缓存复位后下次拉取重建。
    try {
      await _ssoLogin(prefs ?? _zjuPrefs!);
      _zdbkSessionFuture = null;
      return true;
    } catch (e) {
      Log().warn('[zju] refreshSession（无 jar）SSO 重登失败',
          data: {'error': e.toString()});
      return false;
    }
  }
  final ok = await _zjuRelogin();
  if (ok) {
    // zdbk 教务会话持旧 SSO cookie（其内部 _relogin 复用 login 时的
    // iPlanetDirectoryPro），SSO 重登后必须丢弃旧会话缓存，下次
    // ensureZdbkSession 用新 cookie 重建。
    _zdbkSessionFuture = null;
  }
  return ok;
}

/// ZJU 会话提供者——把 [ensureZjuSession]/[zjuRefreshSession] 封装为平台
/// [SessionProvider]（core `session_provider.dart` 抽象）。
///
/// 由 `zju_data_sources.registerZjuDataSources` 在数据源注册期经
/// `SessionCoordinator.instance.registerSessionProvider('zju', ...)` 注册；
/// 数据层（DataOrchestrator）拉取失败且错误被判「会话失效」时经
/// [SessionCoordinator] 单点重登后重拉（登录锁防「登录挤占」，见 core）。
class ZjuSessionProvider implements SessionProvider {
  ZjuSessionProvider({required this.prefs});

  final SharedPreferences prefs;

  @override
  String get sessionProviderId => 'zju';

  @override
  Future<bool> ensureSession() async {
    // 共享 jar 已建立（fetcher 懒加载路径已初始化）→ 直接复用；重建 jar 会使
    // `_zjuCookieJar` 指向新实例、与 zju_data_sources 缓存的 Dio 脱节，故避免。
    if (_zjuCookieJar != null) return true;
    try {
      await ensureZjuSession(prefs: prefs);
      return true;
    } catch (e) {
      Log().warn('[zju] SessionProvider.ensureSession 失败',
          data: {'error': e.toString()});
      return false;
    }
  }

  @override
  bool isSessionExpired(Object error) => zjuIsSessionExpiredError(error);

  @override
  Future<bool> refreshSession() => zjuRefreshSession(prefs: prefs);

  @override
  Future<void> invalidate() async {
    try {
      final store = await CookieStore.getInstance();
      await store.clearAll();
    } catch (e) {
      Log().warn('[zju] SessionProvider.invalidate 清 CookieStore 失败',
          data: {'error': e.toString()});
    }
    _zdbkSessionFuture = null;
  }
}

/// 智云课堂媒体凭据头 provider——把 [zjuVideoHttpHeaders] 接入平台抽象
/// [MediaRequestHeadersProvider]，供 `buildMedia`/`resolveStreamHeaders`
/// （`components/shared/stream_playback.dart`）为 media_kit `Media` 注入
/// Cookie/Referer/UA（media_kit 独立进程不带 Dio jar，缺头会 401/403 黑屏）。
class ZjuMediaRequestHeadersProvider implements MediaRequestHeadersProvider {
  const ZjuMediaRequestHeadersProvider();

  @override
  Future<Map<String, String>> headersFor(Uri url, {String? sessionProvider}) =>
      zjuVideoHttpHeaders();
}

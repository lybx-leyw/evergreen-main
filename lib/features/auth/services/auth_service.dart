import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';

import '../../../core/log.dart';

/// 登录进度事件。
class AuthProgress {
  final String service;
  final String step;
  final AuthStatus status;
  final String? error;

  const AuthProgress({
    required this.service,
    required this.step,
    required this.status,
    this.error,
  });
}

enum AuthStatus { inProgress, success, failed }

/// 单个服务的登录结果。
class ServiceResult {
  final bool ok;
  final String? error;
  const ServiceResult._({required this.ok, this.error});
  factory ServiceResult.success() => const ServiceResult._(ok: true);
  factory ServiceResult.failure(String error) =>
      ServiceResult._(ok: false, error: error);
}

/// 全部登录结果。
class AuthResult {
  final Map<String, ServiceResult> results;
  AuthResult({required Map<String, ServiceResult> results})
      : results = Map.unmodifiable(results);
  bool get allOk => results.values.every((r) => r.ok);
}

/// 自动登录编排器——管理 ZJU SSO → ZDBK / Courses / Classroom 全链路。
///
/// 替代 `app.dart` 中的 `_loginCourses` / `_loginClassroom` / `_triggerAutoLogin`。
class AuthService {
  final HttpClient _httpClient;
  final PersistCookieJar _cookieJar;
  final void Function(AuthProgress)? onProgress;

  AuthService(
    this._httpClient,
    this._cookieJar, {
    this.onProgress,
  });

  /// 按顺序登录所有 ZJU 子系统，每个服务独立失败。
  Future<AuthResult> loginAll({required Cookie ssoCookie}) async {
    final results = <String, ServiceResult>{};

    // 1. ZDBK（已在外部通过 zdbk.login() 完成，此处只记录）
    _report('ZDBK', '等待教务网服务实例...', AuthStatus.inProgress);

    // 2. Courses
    _report('Courses', '正在登录...', AuthStatus.inProgress);
    results['Courses'] = await _safeLogin(() => _loginCourses(ssoCookie));

    // 3. Classroom
    _report('Classroom', '正在登录...', AuthStatus.inProgress);
    results['Classroom'] =
        await _safeLogin(() => _loginClassroom(ssoCookie));

    // 4. Elife（一卡通）— 暂禁用，见 docs/dev/ecard-auth-notes.md
    // _report('Elife', '正在登录...', AuthStatus.inProgress);
    // results['Elife'] =
    //     await _safeLogin(() => _loginElife(ssoCookie));
    results['Elife'] = ServiceResult.failure(
        'BlueWare token 暂未实现，参见开发文档');

    return AuthResult(results: results);
  }

  /// 单独登录 Courses（供 ConnectionManager 使用）。
  Future<ServiceResult> loginCourses(Cookie ssoCookie) =>
      _safeLogin(() => _loginCourses(ssoCookie));

  /// 单独登录 Classroom（供 ConnectionManager 使用）。
  Future<ServiceResult> loginClassroom(Cookie ssoCookie) =>
      _safeLogin(() => _loginClassroom(ssoCookie));

  Future<ServiceResult> _safeLogin(
      Future<void> Function() fn) async {
    try {
      await fn();
      return ServiceResult.success();
    } catch (e) {
      Log().warn('AuthService login failed', error: e);
      return ServiceResult.failure(e.toString());
    }
  }

  void _report(String service, String step, AuthStatus status,
      {String? error}) {
    onProgress?.call(AuthProgress(
        service: service, step: step, status: status, error: error));
  }

  // ═══════════════════════════════════════════════════════════════════
  // Courses 登录（从 app.dart _loginCourses 搬移）
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _loginCourses(Cookie ssoCookie) async {
    final cookies = <String, String>{};

    void attachCookies(HttpClientRequest req) {
      if (cookies.isNotEmpty) {
        req.headers.set('Cookie',
            cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
    }

    void collectCookies(HttpClientResponse res) {
      res.headers['set-cookie']?.forEach((raw) {
        final semi = raw.indexOf(';');
        final nv = semi > 0 ? raw.substring(0, semi).trim() : raw.trim();
        final eq = nv.indexOf('=');
        if (eq > 0) {
          cookies[nv.substring(0, eq)] = nv.substring(eq + 1);
        }
      });
    }

    Future<String> follow(String url) async {
      Log().debug('Courses redirect', data: {'url': url});
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      attachCookies(req);
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain();
      collectCookies(res);

      final location = res.headers.value('location');
      if (location == null) throw Exception('Courses 跳转中断');
      return location.startsWith('http://')
          ? location.replaceFirst('http://', 'https://')
          : location;
    }

    Future<String?> followWithCookie(String url) async {
      Log().debug('Courses CAS', data: {'url': url});
      cookies[ssoCookie.name] = ssoCookie.value;
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      attachCookies(req);
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain();
      collectCookies(res);

      final location = res.headers.value('location');
      if (location == null) return null;
      return location.startsWith('http://')
          ? location.replaceFirst('http://', 'https://')
          : location;
    }

    var url = 'https://courses.zju.edu.cn/user/index';
    while (Uri.parse(url).host != 'zjuam.zju.edu.cn') {
      url = await follow(url);
    }

    final nextUrl = await followWithCookie(url);
    if (nextUrl == null) throw Exception('Courses CAS 登录失败');
    url = nextUrl;

    while (Uri.parse(url).host != 'courses.zju.edu.cn') {
      url = await follow(url);
    }
    url = await follow(url); // capture session cookie

    if (cookies.isNotEmpty) {
      final list =
          cookies.entries.map((e) => Cookie(e.key, e.value)).toList();
      await _cookieJar.delete(Uri.parse('https://courses.zju.edu.cn'));
      await _cookieJar.saveFromResponse(
          Uri.parse('https://courses.zju.edu.cn'), list);
      Log().info('Courses login: saved ${list.length} cookies');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Classroom 登录（从 app.dart _loginClassroom 搬移）
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _loginClassroom(Cookie ssoCookie) async {
    final cookies = <String, String>{};
    var hopCount = 0;
    const maxHops = 20;

    void attachCookies(HttpClientRequest req) {
      final all = Map<String, String>.from(cookies);
      all[ssoCookie.name] = ssoCookie.value;
      if (all.isNotEmpty) {
        req.headers.set('Cookie',
            all.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
    }

    void collectCookies(HttpClientResponse res) {
      res.headers['set-cookie']?.forEach((raw) {
        final semi = raw.indexOf(';');
        final nv = semi > 0 ? raw.substring(0, semi).trim() : raw.trim();
        final eq = nv.indexOf('=');
        if (eq > 0) {
          cookies[nv.substring(0, eq)] = nv.substring(eq + 1);
        }
      });
    }

    Future<String?> follow(String url) async {
      hopCount++;
      if (hopCount > maxHops) {
        throw Exception('Classroom: 超过最大跳数 $maxHops');
      }
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      attachCookies(req);
      final res = await req.close().timeout(const Duration(seconds: 10));
      collectCookies(res);

      final location = res.headers.value('location');
      if (location != null) {
        return location.startsWith('http://')
            ? location.replaceFirst('http://', 'https://')
            : location;
      }

      // meta-refresh
      try {
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        final meta = RegExp(
                r'meta http-equiv="refresh" content="0;URL=([^"]+)"')
            .firstMatch(body);
        if (meta != null) {
          final u = meta.group(1)!;
          return u.startsWith('http://')
              ? u.replaceFirst('http://', 'https://')
              : u;
        }
      } catch (_) {}

      return null;
    }

    Future<String> followOAuth2(String url) async {
      hopCount++;
      if (hopCount > maxHops) {
        throw Exception('Classroom: OAuth2 超过最大跳数 $maxHops');
      }
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      attachCookies(req);
      final res = await req.close().timeout(const Duration(seconds: 10));
      collectCookies(res);

      final location = res.headers.value('location');
      if (location == null) {
        throw Exception(
            'Classroom OAuth2 中断 at $url (status=${res.statusCode})');
      }
      return location.startsWith('http://')
          ? location.replaceFirst('http://', 'https://')
          : location;
    }

    String? url = 'https://tgmedia.cmc.zju.edu.cn/index.php'
        '?r=auth%2Flogin'
        '&forward=https%3A%2F%2Fclassroom.zju.edu.cn%2F';

    String? next;
    while ((next = await follow(url!)) != null) {
      url = next;
      if (Uri.parse(url!).host == 'zjuam.zju.edu.cn') break;
    }

    if (url == null || Uri.parse(url).host != 'zjuam.zju.edu.cn') {
      throw Exception('Classroom: 未能到达 ZJUAM');
    }

    var oauthHops = 0;
    while (Uri.parse(url!).host == 'zjuam.zju.edu.cn') {
      oauthHops++;
      if (oauthHops > 10) throw Exception('Classroom: OAuth2 跳数超限');
      url = await followOAuth2(url!);
    }

    while (url != null &&
        (next = await follow(url!)) != null) {
      url = next;
    }

    if (cookies.isNotEmpty) {
      final list =
          cookies.entries.map((e) => Cookie(e.key, e.value)).toList();
      for (final domain in [
        'classroom.zju.edu.cn',
        'tgmedia.cmc.zju.edu.cn',
        'education.cmc.zju.edu.cn',
        'yjapi.cmc.zju.edu.cn',
      ]) {
        await _cookieJar.delete(Uri.parse('https://$domain'));
        await _cookieJar.saveFromResponse(
            Uri.parse('https://$domain'), list);
      }
      Log().info('Classroom login: saved ${list.length} cookies');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Elife 登录（一卡通 / BlueWare 新中新平台）
  // 暂禁用 — 见 docs/dev/ecard-auth-notes.md
  // ═══════════════════════════════════════════════════════════════════
  // ignore: unused_element
  Future<void> _loginElife(Cookie ssoCookie) async {
    final cookies = <String, String>{};

    void attach(HttpClientRequest req) {
      cookies[ssoCookie.name] = ssoCookie.value;
      if (cookies.isNotEmpty) {
        req.headers.set('Cookie',
            cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
    }

    void collect(HttpClientResponse res) {
      res.headers['set-cookie']?.forEach((raw) {
        final semi = raw.indexOf(';');
        final nv = semi > 0 ? raw.substring(0, semi).trim() : raw.trim();
        final eq = nv.indexOf('=');
        if (eq > 0) cookies[nv.substring(0, eq)] = nv.substring(eq + 1);
      });
    }

    // 访问 elife 根路径，收集返回的 Set-Cookie
    var url = 'https://elife.zju.edu.cn/';
    for (var hop = 0; hop < 15; hop++) {
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      attach(req);
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain();
      collect(res);

      final location = res.headers.value('location');
      if (location == null) break;

      url = location.startsWith('http://')
          ? location.replaceFirst('http://', 'https://')
          : location;
    }

    if (cookies.isNotEmpty) {
      final list =
          cookies.entries.map((e) => Cookie(e.key, e.value)).toList();
      await _cookieJar.delete(Uri.parse('https://elife.zju.edu.cn'));
      await _cookieJar.saveFromResponse(
          Uri.parse('https://elife.zju.edu.cn'), list);
      Log().info('Elife login: saved ${list.length} cookies');
    }
  }
}

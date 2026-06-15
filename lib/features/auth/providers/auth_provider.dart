import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/network/cookie_manager.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';
import '../services/zjuam_service.dart';

/// Authentication state.
class AuthState {
  final bool isLoggedIn;

  /// The iPlanetDirectoryPro cookie obtained from ZJU SSO login.
  final Cookie? ssoCookie;

  /// SSO cookie 过期时间，从 Set-Cookie 的 Expires / Max-Age 提取。
  /// restoreSession 恢复的 cookie 无此信息时为 null。
  final DateTime? ssoExpiresAt;

  /// Last login error, if any — typed [AppError] for UI display.
  final AppError? error;

  const AuthState({
    this.isLoggedIn = false,
    this.ssoCookie,
    this.ssoExpiresAt,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    Cookie? ssoCookie,
    DateTime? ssoExpiresAt,
    AppError? error,
    bool clearExpiry = false,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      ssoCookie: ssoCookie ?? this.ssoCookie,
      ssoExpiresAt: clearExpiry ? null : (ssoExpiresAt ?? this.ssoExpiresAt),
      error: error,
    );
  }

  /// 从 Cookie 提取过期时间。
  @visibleForTesting
  static DateTime? parseExpiry(Cookie cookie) {
    if (cookie.expires != null) return cookie.expires;
    if (cookie.maxAge != null && cookie.maxAge! > 0) {
      return DateTime.now().add(Duration(seconds: cookie.maxAge!));
    }
    return null;
  }
}

/// Auth provider — manages ZJU SSO login state.
class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;
  final PersistCookieJar _cookieJar;
  final HttpClient _httpClient;

  AuthNotifier(this._dio, this._cookieJar, this._httpClient)
      : super(const AuthState());

  /// Perform RSA login with credentials from AppConfig.
  Future<bool> login() async {
    final username = AppConfig.zjuUsername;
    final password = AppConfig.zjuPassword;

    Log().debug('Login attempt', data: {
      'username': username ?? '(null)',
      'hasPassword': password != null && password.isNotEmpty,
    });

    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      state = state.copyWith(
        error: AppError.configMissing('学号和密码')
          ..recoveryHint = '请先在设置中配置学号和密码',
      );
      return false;
    }

    final service = ZjuAmService(_httpClient);
    final result = await service.login(username, password);

    return result.fold(
      (cookie) async {
        // Persist SSO cookie value in CookieStore
        final cookieStore = await CookieStore.getInstance();
        await cookieStore.setSsoCookie(cookie.value);

        // Inject into Dio's PersistCookieJar
        await _cookieJar.delete(Uri.parse('https://zjuam.zju.edu.cn'));
        await _cookieJar.saveFromResponse(
          Uri.parse('https://zjuam.zju.edu.cn'),
          [cookie],
        );
        Log().debug('Cookie persisted', data: {
          'domain': cookie.domain,
          'path': cookie.path,
        });

        // Set up auth interceptor relogin callback
        AuthInterceptor.onRelogin = () async => login();

        state = AuthState(
          isLoggedIn: true,
          ssoCookie: cookie,
          ssoExpiresAt: AuthState.parseExpiry(cookie),
        );
        return true;
      },
      (error) {
        Log().warn('Login failed', error: error);
        state = AuthState(error: error);
        return false;
      },
    );
  }

  /// Try to restore SSO cookie from persistent storage.
  Future<bool> restoreSession() async {
    final cookieStore = await CookieStore.getInstance();
    final ssoCookie = cookieStore.ssoCookie;
    if (ssoCookie != null && ssoCookie.isNotEmpty) {
      Log().debug('Restoring session from cookie store');
      final cookie = Cookie('iPlanetDirectoryPro', ssoCookie)
        ..domain = '.zju.edu.cn'
        ..path = '/';

      // Inject into Dio's PersistCookieJar
      await _cookieJar.delete(Uri.parse('https://zjuam.zju.edu.cn'));
      await _cookieJar.saveFromResponse(
        Uri.parse('https://zjuam.zju.edu.cn'),
        [cookie],
      );

      AuthInterceptor.onRelogin = () async => login();
      state = AuthState(isLoggedIn: true, ssoCookie: cookie);
      return true;
    }
    Log().debug('No saved session found');
    return false;
  }

  /// Logout — clear SSO cookie.
  Future<void> logout() async {
    final cookieStore = await CookieStore.getInstance();
    await cookieStore.clearSsoCookie();
    state = const AuthState();
    Log().info('User logged out');
  }

  /// Check if login is needed and try to restore or login.
  Future<bool> ensureAuth() async {
    if (state.isLoggedIn) {
      Log().debug('Already logged in');
      return true;
    }

    // Try restoring from disk first
    final restored = await restoreSession();
    if (restored) {
      final valid = await _validateCookie(state.ssoCookie!);
      Log().debug('Restored cookie valid: $valid');
      if (valid) {
        return true;
      }
      Log().info('Restored cookie expired, falling through to login');
    }

    Log().info('Starting fresh login');
    return login();
  }

  /// Quick CAS validation — check if the SSO cookie is still recognized.
  Future<bool> _validateCookie(Cookie cookie) async {
    try {
      final uri = Uri.parse(
          'https://zjuam.zju.edu.cn/cas/login'
          '?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html');
      final req = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      req.followRedirects = false;
      req.cookies.add(cookie);
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain();
      final location = res.headers.value('location');
      return location != null;
    } catch (e) {
      Log().warn('Cookie validation network error (optimistic=true)',
          error: e);
      return true;
    }
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
    super.dispose();
  }
}

/// Shared HttpClient for ZJU services (SSO login + ZDBK).
final httpClientProvider = Provider<HttpClient>((ref) {
  return HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final dio = ref.read(dioClientProvider);
  final cookieJar = ref.read(cookieJarProvider);
  final httpClient = ref.read(httpClientProvider);
  return AuthNotifier(dio, cookieJar, httpClient);
});

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../../../core/log.dart';
import '../utils/html_parser.dart';

/// Dio interceptor that detects ZJU session expiry and triggers auto-relogin.
class AuthInterceptor extends Interceptor {
  final Dio _dio;
  final PersistCookieJar _cookieJar;
  int _reloginAttempts = 0;
  static const int _maxReloginAttempts = 2;

  /// Callback that performs the actual relogin.
  static Future<bool> Function()? onRelogin;

  /// Callback after relogin succeeds — triggers reconnection of all services.
  static Future<void> Function()? onReconnected;

  AuthInterceptor(this._dio, this._cookieJar);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_isSessionExpiredError(err)) {
      Log().warn('Auth session expired in onError', data: {
        'status': err.response?.statusCode,
        'uri': err.requestOptions.uri.toString(),
      });
      _tryRelogin().then((success) {
        if (success) {
          Log().info('Auth relogin success, retrying request');
          _dio.fetch(_cloneOptions(err.requestOptions)).then(
            (r) => handler.resolve(r),
            onError: (e) => handler.next(e as DioException),
          );
        } else {
          Log().warn('Auth relogin failed, passing error through');
          handler.next(err);
        }
      });
    } else {
      handler.next(err);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is String && HtmlParser.isSessionExpired(data)) {
      Log().warn('Auth CAS login page in 200 response', data: {
        'uri': response.requestOptions.uri.toString(),
        'bodySize': data.length,
      });
      _tryRelogin().then((success) {
        if (success) {
          Log().info('Auth relogin success after CAS detection');
          _dio.fetch(_cloneOptions(response.requestOptions)).then(
            (r) => handler.resolve(r),
            onError: (e) => handler.reject(e as DioException),
          );
        } else {
          handler.next(response);
        }
      });
    } else {
      handler.next(response);
    }
  }

  bool _isSessionExpiredError(DioException err) {
    final code = err.response?.statusCode;
    if (code == 301 || code == 302 || code == 303) return true;
    final data = err.response?.data;
    if (data is String) {
      return data.contains('login_ssologin') ||
          data.contains('cas/login') ||
          data.contains('统一身份认证');
    }
    return false;
  }

  Future<bool> _tryRelogin() async {
    if (_reloginAttempts >= _maxReloginAttempts) {
      Log().warn('Auth max relogin attempts reached');
      return false;
    }
    _reloginAttempts++;
    if (onRelogin == null) return false;

    try {
      final ok = await onRelogin!();
      if (ok) {
        _reloginAttempts = 0;
        // 重新登录成功后触发全服务重连
        if (onReconnected != null) {
          unawaited(onReconnected!());
        }
      }
      return ok;
    } catch (e) {
      Log().warn('Auth relogin threw', error: e);
      return false;
    }
  }

  /// Deep copy request options to avoid mutating the original on retry.
  RequestOptions _cloneOptions(RequestOptions opts) {
    return RequestOptions(
      path: opts.path,
      method: opts.method,
      data: opts.data,
      headers: Map.from(opts.headers),
      queryParameters: Map.from(opts.queryParameters),
      extra: Map.from(opts.extra),
      baseUrl: opts.baseUrl,
      connectTimeout: opts.connectTimeout,
      receiveTimeout: opts.receiveTimeout,
      responseType: opts.responseType,
      contentType: opts.contentType,
      followRedirects: opts.followRedirects,
      maxRedirects: opts.maxRedirects,
      validateStatus: opts.validateStatus,
      receiveDataWhenStatusError: opts.receiveDataWhenStatusError,
    );
  }

  void resetReloginCounter() => _reloginAttempts = 0;
}

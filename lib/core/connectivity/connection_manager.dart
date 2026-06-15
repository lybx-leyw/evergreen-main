import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../network/network_config.dart';
import '../config/app_config.dart';
import '../../features/auth/services/auth_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/zdbk/services/zdbk_service.dart';
import '../../features/pintia/services/pintia_service.dart';

/// 单个服务的连接结果。
class ConnectionResult {
  final String service;
  final bool ok;
  final String? message;
  final Duration elapsed;

  const ConnectionResult({
    required this.service,
    required this.ok,
    this.message,
    required this.elapsed,
  });
}

/// 统一连接管理器——一键检查所有服务的连通性。
///
/// 接收直接依赖，不持有 Ref，可在 WidgetRef 和 ProviderRef 环境共用。
/// 支持重试单个服务：通过 [checkOne] 传入服务名称。
class ConnectionManager {
  final HttpClient _httpClient;
  final PersistCookieJar _cookieJar;
  final AuthState _auth;
  final ZdbkService Function() _zdbkService;

  ConnectionManager(
    this._httpClient,
    this._cookieJar,
    this._auth,
    this._zdbkService,
  );

  /// 依次检查所有服务，返回结果列表。
  Future<List<ConnectionResult>> checkAll() async {
    final services = [
      'ZJUAM SSO',
      'ZDBK 教务网',
      'Courses 学在浙大',
      'Classroom 智云课堂',
      'PTA 编程题',
      'DeepSeek AI',
    ];
    final results = <ConnectionResult>[];
    for (final s in services) {
      results.add(await checkOne(s));
    }
    return results;
  }

  /// 重试单个服务，返回该服务的结果。
  Future<ConnectionResult> checkOne(String service) async {
    final sso = _auth.ssoCookie;
    if (sso == null) {
      return ConnectionResult(
        service: service, ok: false, message: 'SSO 未登录', elapsed: Duration.zero,
      );
    }

    switch (service) {
      case 'ZJUAM SSO':
        return _result('ZJUAM SSO', () async {});
      case 'ZDBK 教务网':
        return await _check('ZDBK 教务网', () async {
          final svc = _zdbkService();
          await svc.login(_httpClient, sso);
        });
      case 'Courses 学在浙大':
        return await _check('Courses 学在浙大', () async {
          final authService = AuthService(_httpClient, _cookieJar);
          final r = await authService.loginCourses(sso);
          if (!r.ok) throw Exception(r.error ?? '登录失败');
        });
      case 'Classroom 智云课堂':
        return await _check('Classroom 智云课堂', () async {
          final authService = AuthService(_httpClient, _cookieJar);
          final r = await authService.loginClassroom(sso);
          if (!r.ok) throw Exception(r.error ?? '登录失败');
        });
      case 'PTA 编程题':
        return await _check('PTA 编程题', () async {
          final session = AppConfig.ptaSession;
          if (session == null || session.isEmpty) {
            throw Exception('未配置 PTASession');
          }
          final dio = Dio(BaseOptions(
            connectTimeout: NetworkConfig.connectTimeout,
            receiveTimeout: NetworkConfig.receiveTimeout,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Accept': 'application/json',
            },
          ));
          dio.interceptors.add(CookieManager(_cookieJar));
          final svc = PintiaService(dio, _cookieJar);
          await svc.setSessionCookie(session);
          if (!await svc.hasValidSession()) throw Exception('PTASession 已失效');
        });
      case 'DeepSeek AI':
        return _result('DeepSeek AI', () {
          final key = AppConfig.deepseekApiKey;
          if (key == null || key.isEmpty) throw Exception('未配置 API Key');
        });
      default:
        return ConnectionResult(
          service: service, ok: false, message: '未知服务', elapsed: Duration.zero,
        );
    }
  }

  ConnectionResult _result(String service, void Function() fn) {
    final start = DateTime.now();
    try {
      fn();
      return ConnectionResult(service: service, ok: true, elapsed: DateTime.now().difference(start));
    } catch (e) {
      return ConnectionResult(service: service, ok: false, message: e.toString(), elapsed: DateTime.now().difference(start));
    }
  }

  Future<ConnectionResult> _check(String service, Future<void> Function() fn) async {
    final start = DateTime.now();
    try {
      await fn();
      return ConnectionResult(service: service, ok: true, elapsed: DateTime.now().difference(start));
    } catch (e) {
      return ConnectionResult(service: service, ok: false, message: e.toString(), elapsed: DateTime.now().difference(start));
    }
  }
}

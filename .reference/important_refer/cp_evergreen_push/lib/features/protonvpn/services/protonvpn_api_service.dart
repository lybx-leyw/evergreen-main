/// ProtonVPN REST API client — standalone Dio instance.
///
/// Includes DNS-over-HTTPS fallback (mirrors ProtonVPN's DnsHandler/AlternativeHostHandler)
/// for environments where Proton domains are blocked at the DNS level.
///
/// Reference:
///   .reference/win-app/src/Api/ProtonVPN.Api/ApiClient.cs
///   .reference/win-app/src/Api/ProtonVPN.Api/Handlers/DnsHandler.cs
///   .reference/win-app/src/Configurations/.../DefaultUrlsConfigurationFactory.cs

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'protonvpn_models.dart';

class ProtonVpnApiService {
  late final Dio _dio;

  String? _uid;
  String? _accessToken;

  /// Current effective API host (may differ from default after DOH fallback).
  String _activeHost = _defaultApiHost;

  /// Current effective base URL.
  String get _baseUrl => 'https://$_activeHost';

  static const _defaultApiHost = 'vpn-api.proton.me';
  static const _fallbackApiHost = 'api.protonvpn.ch';

  ProtonVpnApiService() {
    _dio = _createDio();
  }

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://$_activeHost',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: _staticHeaders,
    ));

    dio.interceptors.add(_dohInterceptor());
    dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (_) {},
    ));

    return dio;
  }

  // ═══════════════════════════════════════════════════════════
  // DNS-over-HTTPS interceptor — resolves blocked domains via
  // Google DOH, then connects by IP with the original Host header.
  // ═══════════════════════════════════════════════════════════

  InterceptorsWrapper _dohInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) async {
        // Only intercept DNS-related errors
        if (!_isDnsError(error)) return handler.next(error);

        // If we already tried DOH and it still failed, try fallback host
        if (_activeHost == _fallbackApiHost) return handler.next(error);

        // Try resolving via DOH
        final ip = await _resolveDoh(_activeHost);
        if (ip != null) {
          // Rebuild Dio with the resolved IP + Host header
          _rebuildWithIp(ip);
          // Retry the original request
          try {
            final response = await _retryRequest(error.requestOptions);
            return handler.resolve(response);
          } catch (e) {
            // DOH + IP approach failed too
          }
        }

        // Try fallback host
        final fallbackIp = await _resolveDoh(_fallbackApiHost);
        if (fallbackIp != null) {
          _activeHost = _fallbackApiHost;
          _rebuildWithIp(fallbackIp);
          try {
            final response = await _retryRequest(error.requestOptions);
            return handler.resolve(response);
          } catch (e) {
            // Fallback also failed
          }
        }

        return handler.next(error);
      },
    );
  }

  bool _isDnsError(DioException error) {
    final msg = error.message.toLowerCase();
    return error.type == DioExceptionType.connectionError &&
        (msg.contains('no address associated') ||
            msg.contains('host not found') ||
            msg.contains('failed host lookup') ||
            msg.contains('11001'));
  }

  /// Resolve a hostname via Google DNS-over-HTTPS.
  Future<String?> _resolveDoh(String host) async {
    try {
      final dohDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final resp = await dohDio.get(
        'https://dns.google/resolve',
        queryParameters: {'name': host, 'type': 'A'},
      );
      final answers = resp.data['Answer'] as List<dynamic>?;
      if (answers != null && answers.isNotEmpty) {
        return answers[0]['data'] as String?;
      }
    } catch (_) {
      // DOH itself failed — nothing we can do
    }
    return null;
  }

  /// Rebuild _dio to target a specific IP, injecting the Host header.
  void _rebuildWithIp(String ip) {
    _dio.close();
    _dio = Dio(BaseOptions(
      baseUrl: 'https://$ip',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        ..._staticHeaders,
        'Host': _activeHost,
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (_) {},
    ));

    // Restore auth headers if logged in
    if (_uid != null) {
      _dio.options.headers['x-pm-uid'] = _uid;
      _dio.options.headers['Authorization'] = 'Bearer $_accessToken';
    }
  }

  /// Retry a failed request with the rebuilt Dio.
  Future<Response> _retryRequest(RequestOptions options) async {
    final opts = options.copyWith(
      path: options.path,
      baseUrl: _dio.options.baseUrl,
      headers: Map<String, dynamic>.from(_dio.options.headers),
    );
    return _dio.fetch(opts);
  }

  // ═══════════════════════════════════════════════════════════
  // Static headers
  // ═══════════════════════════════════════════════════════════

  static Map<String, String> get _staticHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-pm-apiversion': '3',
        'x-pm-appversion': 'Evergreen/1.4.0',
        'User-Agent': 'Evergreen/1.4.0 (Flutter)',
      };

  // ═══════════════════════════════════════════════════════════
  // Auth
  // ═══════════════════════════════════════════════════════════

  void setAuth({required String uid, required String accessToken}) {
    _uid = uid;
    _accessToken = accessToken;
    _dio.options.headers['x-pm-uid'] = uid;
    _dio.options.headers['Authorization'] = 'Bearer $accessToken';
  }

  void clearAuth() {
    _uid = null;
    _accessToken = null;
    _dio.options.headers.remove('x-pm-uid');
    _dio.options.headers.remove('Authorization');
  }

  bool get hasAuth => _uid != null && _accessToken != null;

  // ═══════════════════════════════════════════════════════════
  // Endpoints
  // ═══════════════════════════════════════════════════════════

  Future<AuthInfoResponse> authInfo(String username) async {
    final response = await _dio.post('auth/info', data: {
      'Username': username,
      'Intent': 'Proton',
    });
    _ensureOk(response);
    return AuthInfoResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<AuthResponse> authenticate({
    required String username,
    required String clientEphemeral,
    required String clientProof,
    required String srpSession,
  }) async {
    final response = await _dio.post('auth', data: {
      'Username': username,
      'ClientEphemeral': clientEphemeral,
      'ClientProof': clientProof,
      'SRPSession': srpSession,
    });
    _ensureOk(response);
    return AuthResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    if (!hasAuth) return;
    try {
      await _dio.delete('auth');
    } catch (_) {}
    clearAuth();
  }

  Future<ServersResponse> getServers() async {
    final response = await _dio.get(
      'vpn/v2/logicals',
      queryParameters: {
        'SignServer': 'Server.EntryIP,Server.Label',
        'WithEntriesForProtocols':
            'WireGuardUDP,WireGuardTCP,WireGuardTLS,OpenVPNUDP,OpenVPNTCP',
        'SecureCoreFilter': 'all',
        'WithState': 'true',
      },
      options: Options(headers: {
        'x-pm-response-truncation-permitted': 'true',
      }),
    );
    _ensureOk(response);
    return ServersResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getServerLoads() async {
    final response = await _dio.get('vpn/loads');
    _ensureOk(response);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVpnConfig() async {
    final response = await _dio.get('vpn/v2/clientconfig');
    _ensureOk(response);
    return response.data as Map<String, dynamic>;
  }

  Future<UserResponse> getUserInfo() async {
    final response = await _dio.get('core/v4/users');
    _ensureOk(response);
    return UserResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ═══════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════

  void _ensureOk(Response response) {
    final data = response.data;
    if (data is! Map<String, dynamic>) return;
    final code = data['Code'] as int?;
    if (code != null && code != 1000) {
      throw ProtonVpnApiException(
          code, data['Error'] as String? ?? 'Unknown API error');
    }
  }
}

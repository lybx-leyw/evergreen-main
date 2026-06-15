import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_interceptor.dart';
import 'debug_interceptor.dart';
import 'retry_interceptor.dart';
import 'network_config.dart';

/// Provides the shared PersistCookieJar — cookies survive app restarts.
final cookieJarProvider = Provider<PersistCookieJar>((ref) {
  return PersistCookieJar(storage: FileStorage('.cookies'));
});

/// Provides a configured Dio HTTP client through Riverpod.
final dioClientProvider = Provider<Dio>((ref) {
  final cookieJar = ref.read(cookieJarProvider);

  final dio = Dio(BaseOptions(
    connectTimeout: NetworkConfig.connectTimeout,
    receiveTimeout: NetworkConfig.receiveTimeout,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
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

  return dio;
});

/// Streamlined client for CLI tools (no Riverpod, minimal config).
Dio createCliDio() {
  return Dio(BaseOptions(
    connectTimeout: NetworkConfig.connectTimeout,
    receiveTimeout: NetworkConfig.receiveTimeout,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    },
  ));
}

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:evergreen_base/core/utils/greenix_path.dart';

import 'auth_interceptor.dart';
import 'debug_interceptor.dart';
import 'retry_interceptor.dart';
import 'network_config.dart';

/// Provides the shared PersistCookieJar — cookies survive app restarts.
/// 落盘到 [cookieJarPath]（`.greenix/.cookies`，由 initGreenixPaths 解析）。
///
/// 自参考工程 `cp_evergreen_push/lib/core/network/dio_client.dart` 改造：
/// provider 名加 `zju` 前缀避免与全局 providers 冲突；路径走 evg-base greenix。
final zjuCookieJarProvider = Provider<PersistCookieJar>((ref) {
  return PersistCookieJar(storage: FileStorage(cookieJarPath));
});

/// Provides a configured Dio HTTP client through Riverpod.
final zjuDioClientProvider = Provider<Dio>((ref) {
  final cookieJar = ref.read(zjuCookieJarProvider);

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

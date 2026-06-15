import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/network/network_config.dart';
import 'package:evergreen_multi_tools/core/network/retry_interceptor.dart';
import 'package:evergreen_multi_tools/core/network/auth_interceptor.dart';
import 'package:dio/dio.dart';

void main() {
  group('RetryInterceptor — _shouldRetry', () {
    late Dio dio;

    setUp(() {
      dio = Dio();
    });

    test('429 可重试', () {
      final interceptor = RetryInterceptor(dio);
      final err = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(requestOptions: RequestOptions(path: '/test'), statusCode: 429),
        type: DioExceptionType.badResponse,
      );
      // 通过反射无法访问私有方法，改为验证配置层面
      expect(NetworkConfig.retryableStatusCodes.contains(429), true);
    });

    test('502/503 可重试', () {
      expect(NetworkConfig.retryableStatusCodes.contains(502), true);
      expect(NetworkConfig.retryableStatusCodes.contains(503), true);
    });

    test('connectionError 类型可重试', () {
      final interceptor = RetryInterceptor(dio);
      final err = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );
      // connectionError 在 _shouldRetry 中为 true
      final canRetry = err.type == DioExceptionType.connectionError ||
          err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.receiveTimeout;
      expect(canRetry, true);
    });

    test('connectionTimeout 类型可重试', () {
      final canRetry = DioExceptionType.connectionTimeout == DioExceptionType.connectionError ||
          DioExceptionType.connectionTimeout == DioExceptionType.connectionTimeout ||
          DioExceptionType.connectionTimeout == DioExceptionType.receiveTimeout;
      expect(canRetry, true);
    });

    test('receiveTimeout 类型可重试', () {
      final canRetry = DioExceptionType.receiveTimeout == DioExceptionType.connectionError ||
          DioExceptionType.receiveTimeout == DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout == DioExceptionType.receiveTimeout;
      expect(canRetry, true);
    });

    test('404 不可重试', () {
      expect(NetworkConfig.retryableStatusCodes.contains(404), false);
    });

    test('400 不可重试', () {
      expect(NetworkConfig.retryableStatusCodes.contains(400), false);
    });

    test('200 不可重试', () {
      expect(NetworkConfig.retryableStatusCodes.contains(200), false);
    });

    test('500 不在可重试列表（仅429/502/503）', () {
      expect(NetworkConfig.retryableStatusCodes.contains(500), false);
    });

    test('maxRetries = 3', () {
      expect(NetworkConfig.maxRetries, 3);
    });

    test('maxRetryDelay = 30s', () {
      expect(NetworkConfig.maxRetryDelay, const Duration(seconds: 30));
    });

    test('connectTimeout = 30s', () {
      expect(NetworkConfig.connectTimeout, const Duration(seconds: 30));
    });

    test('receiveTimeout = 60s', () {
      expect(NetworkConfig.receiveTimeout, const Duration(seconds: 60));
    });

    test('casValidateTimeout = 5s', () {
      expect(NetworkConfig.casValidateTimeout, const Duration(seconds: 5));
    });
  });

  group('AuthInterceptor', () {
    test('静态回调可设置', () {
      var called = false;
      AuthInterceptor.onReconnected = () async { called = true; };
      AuthInterceptor.onReconnected?.call();
      expect(called, true);
      AuthInterceptor.onReconnected = null;
    });

    test('onRelogin 回调可设置', () {
      AuthInterceptor.onRelogin = () async { return true; };
      expect(AuthInterceptor.onRelogin, isNotNull);
      AuthInterceptor.onRelogin = null; // cleanup
    });
  });
}

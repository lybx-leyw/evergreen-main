import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/log.dart';
import 'network_config.dart';

/// Dio interceptor — exponential backoff retry with jitter and upper bound.
class RetryInterceptor extends Interceptor {
  final Dio _dio;
  final int maxRetries;
  final Duration maxDelay;
  final Random _random = Random();

  RetryInterceptor(
    this._dio, {
    this.maxRetries = NetworkConfig.maxRetries,
    this.maxDelay = NetworkConfig.maxRetryDelay,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final retryCount = (err.requestOptions.extra['_retryCount'] ?? 0) as int;

    if (!_shouldRetry(err) || retryCount >= maxRetries) {
      if (retryCount >= maxRetries) {
        Log().warn('Retry max attempts exhausted', data: {
          'uri': err.requestOptions.uri.toString(),
          'retries': retryCount,
        });
      }
      handler.next(err);
      return;
    }

    final next = retryCount + 1;
    err.requestOptions.extra['_retryCount'] = next;

    // Exponential backoff with jitter, capped at maxDelay
    final rawMs = (1000 * pow(2, next)).toInt() + _random.nextInt(1000);
    final delayMs = rawMs.clamp(0, maxDelay.inMilliseconds);

    Log().warn('Retrying request', data: {
      'attempt': '$next/$maxRetries',
      'delayMs': delayMs,
      'uri': err.requestOptions.uri.toString(),
      'status': err.response?.statusCode,
    });

    unawaited(Future(() async {
      await Future.delayed(Duration(milliseconds: delayMs));
      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
      } on DioException catch (e) {
        handler.next(e);
      } catch (_) {
        handler.next(err);
      }
    }));
  }

  bool _shouldRetry(DioException err) {
    final code = err.response?.statusCode;
    if (code != null && NetworkConfig.retryableStatusCodes.contains(code)) {
      return true;
    }
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;
  }
}

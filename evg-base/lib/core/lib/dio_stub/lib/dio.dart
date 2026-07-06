/// Dio stub for core module isolation.
library dio;

// ═══════ Minimal Dio types for compilation ═══════

/// HTTP client stub — used by services/ tests and example.
class Dio {
  Dio();
}

/// Base options for requests.
class BaseOptions {
  final String? baseUrl;
  final Duration? connectTimeout;
  final Duration? receiveTimeout;
  final Map<String, dynamic>? headers;
  final String? contentType;

  BaseOptions({
    this.baseUrl,
    this.connectTimeout,
    this.receiveTimeout,
    this.headers,
    this.contentType,
  });
}

/// Per-request options.
class Options {
  final String? method;
  final ResponseType? responseType;
  final Map<String, dynamic>? headers;
  final Duration? receiveTimeout;

  Options({
    this.method,
    this.responseType,
    this.headers,
    this.receiveTimeout,
  });
}

/// Response type hint.
enum ResponseType { bytes, json, plain, stream }

/// Dio-specific exception.
class DioException implements Exception {
  final DioExceptionType type;
  final Response? response;

  DioException({required this.type, this.response});

  @override
  String toString() => 'DioException: $type';
}

enum DioExceptionType {
  connectionTimeout,
  receiveTimeout,
  sendTimeout,
  cancel,
  response,
  badResponse,
  other,
}

class Response<T> {
  final T? data;
  final int? statusCode;
  final String? statusMessage;
  final Map<String, dynamic>? headers;

  Response({
    this.data,
    this.statusCode,
    this.statusMessage,
    this.headers,
  });
}

/// Dio stub for agent module isolation.
library dio;

// ═══════ Minimal Dio types for compilation ═══════

class Dio {
  Dio([dynamic options]);

  Future<Response> post(String path, {dynamic data, Options? options}) async {
    throw UnimplementedError('Dio stub — use real Dio in Flutter environment');
  }

  Future<Response> get(String path, {Options? options}) async {
    throw UnimplementedError('Dio stub — use real Dio in Flutter environment');
  }
}

class Options {
  final Map<String, String>? headers;
  final String? contentType;
  final ResponseType? responseType;
  final Duration? receiveTimeout;

  Options({
    this.headers,
    this.contentType,
    this.responseType,
    this.receiveTimeout,
  });
}

enum ResponseType { json, stream, bytes, plain }

class Response {
  final int statusCode;
  final dynamic data;
  final String? statusMessage;

  Response({
    required this.statusCode,
    this.data,
    this.statusMessage,
  });
}

class DioException implements Exception {
  final Response? response;
  final String? message;

  DioException({this.response, this.message});

  @override
  String toString() => 'DioException: $message';
}

class BaseOptions {
  final String? baseUrl;
  final Duration? connectTimeout;

  BaseOptions({this.baseUrl, this.connectTimeout});
}

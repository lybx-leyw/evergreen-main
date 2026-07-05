import 'dart:convert';

import 'package:dio/dio.dart';

/// A stubbed Dio HTTP response.
class MockResponse {
  final dynamic body;
  final int statusCode;
  final Map<String, String>? headers;

  const MockResponse({
    required this.body,
    this.statusCode = 200,
    this.headers,
  });
}

/// Mock Dio adapter — intercepts requests and returns stubbed responses.
///
/// Usage:
/// ```dart
/// final adapter = MockDioAdapter();
/// adapter.stub('https://api.example.com/data', MockResponse(
///   body: {'result': 'ok'},
/// ));
/// final dio = Dio()..httpClientAdapter = adapter;
/// ```
class MockDioAdapter implements HttpClientAdapter {
  final Map<String, MockResponse> _responses = {};
  final Map<String, DioException> _errors = {};
  final List<String> _requestLog = [];

  /// Stub a successful response for a URL.
  void stub(String url, MockResponse response) {
    _responses[url] = response;
  }

  /// Stub an error for a URL (simulating network failure).
  void stubError(String url, DioException error) {
    _errors[url] = error;
  }

  /// Check that a URL was requested.
  bool wasRequested(String url) => _requestLog.contains(url);

  /// All requested URLs.
  List<String> get requestLog => List.unmodifiable(_requestLog);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future? cancelFuture,
  ) async {
    final url = options.uri.toString();
    _requestLog.add(url);

    // Check for stubbed error first
    if (_errors.containsKey(url)) {
      throw _errors[url]!;
    }

    // Check for stubbed response
    if (_responses.containsKey(url)) {
      final mock = _responses[url]!;
      final isJsonBody = mock.body is Map || mock.body is List;
      final bodyStr = mock.body is String
          ? mock.body as String
          : jsonEncode(mock.body);
      // Set Content-Type so Dio auto-parses JSON responses
      final headers = <String, List<String>>{};
      if (mock.headers != null) {
        for (final e in mock.headers!.entries) {
          headers[e.key] = [e.value];
        }
      }
      if (isJsonBody) {
        headers['content-type'] = ['application/json'];
      }
      return ResponseBody.fromString(
        bodyStr,
        mock.statusCode,
        headers: headers,
      );
    }

    // No stub — fail loudly
    throw DioException(
      requestOptions: options,
      message: 'No stub configured for $url',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Factory: create a Dio instance with stubbed responses.
///
/// ```dart
/// final (dio, adapter) = createMockDio();
/// adapter.stub('https://api.example.com/data', MockResponse(
///   body: {'result': 'ok'},
/// ));
/// ```
(Dio, MockDioAdapter) createMockDio() {
  final adapter = MockDioAdapter();
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ))..httpClientAdapter = adapter;
  return (dio, adapter);
}

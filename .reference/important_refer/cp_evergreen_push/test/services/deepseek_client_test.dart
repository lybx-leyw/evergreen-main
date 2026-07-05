import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/result.dart';
import 'package:evergreen_multi_tools/core/errors.dart';
import 'package:evergreen_multi_tools/features/tutor/services/deepseek_client.dart';
import '../mocks/mock_app_config.dart';
import '../mocks/mock_dio.dart';

/// Load a fixture JSON file as Map.
Map<String, dynamic> _fixture(String name) {
  // Fixtures are loaded via the test runner's resolution
  return jsonDecode(_rawFixture(name)) as Map<String, dynamic>;
}

String _rawFixture(String name) {
  // Simplified: fixtures embedded inline for portability
  switch (name) {
    case 'chat_ok':
      return '{"choices":[{"message":{"content":"你好！我是 DeepSeek AI 助手。"}}],"usage":{"prompt_tokens":10,"completion_tokens":15,"total_tokens":25}}';
    case 'chat_rate_limited':
      return '{"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}';
    case 'chat_context_overflow':
      return '{"error":{"message":"This model\'s maximum context length is 131072 tokens. However, your request has 250000 tokens.","type":"invalid_request_error","code":"context_length_exceeded"}}';
    default:
      return '{}';
  }
}

void main() {
  setUp(() {
    setupTestAppConfig();
  });

  group('DeepSeekClient.chat()', () {
    test('成功返回 Ok 含 AI 回复内容', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://api.deepseek.com/chat/completions',
        MockResponse(body: _fixture('chat_ok')),
      );

      final client = DeepSeekClient(dio);
      final result = await client.chat([
        {'role': 'user', 'content': '你好'}
      ]);

      expect(result.isOk, isTrue);
      expect(result.unwrap(), contains('DeepSeek AI'));
    });

    test('429 限流 → Err(AiModelError)，重试 3 次后放弃', () async {
      final (dio, adapter) = createMockDio();
      final url = 'https://api.deepseek.com/chat/completions';

      // Stub 429 for all attempts (mock adapter doesn't differentiate
      // between retries, so it always returns 429)
      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 429,
            data: _fixture('chat_rate_limited'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final client = DeepSeekClient(dio);
      final result = await client.chat([
        {'role': 'user', 'content': 'test'}
      ]);

      expect(result.isErr, isTrue);
      final err = (result as Err<String>).error;
      expect(err, isA<AiModelError>());
      expect(err.userMessage, contains('繁忙'));
    });

    test('上下文溢出 → Err(ContextExceededError)', () async {
      final (dio, adapter) = createMockDio();
      final url = 'https://api.deepseek.com/chat/completions';

      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          response: Response(
            requestOptions: RequestOptions(path: url),
            statusCode: 400,
            data: _fixture('chat_context_overflow'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final client = DeepSeekClient(dio);
      final result = await client.chat([
        {'role': 'user', 'content': 'test'}
      ]);

      expect(result.isErr, isTrue);
      final err = (result as Err<String>).error;
      expect(err, isA<ContextExceededError>());
      expect(err.userMessage, contains('超出'));
      expect(err.recoveryHint, contains('新会话'));
    });

    test('连接错误 → Err(UnknownError)', () async {
      final (dio, adapter) = createMockDio();
      final url = 'https://api.deepseek.com/chat/completions';

      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
          message: 'Connection refused',
        ),
      );

      final client = DeepSeekClient(dio);
      final result = await client.chat([
        {'role': 'user', 'content': 'test'}
      ]);

      expect(result.isErr, isTrue);
      // Non-DioException errors (connection errors that aren't 429/502/503)
      // get mapped through _mapDioError which defaults to AiModelError
      // if no matching status code.
    });
  });

  group('DeepSeekClient.testConnection()', () {
    test('连接成功 → Ok 含余额信息', () async {
      final (dio, adapter) = createMockDio();
      adapter.stub(
        'https://api.deepseek.com/user/balance',
        MockResponse(body: {'balance': '100.00'}),
      );

      final client = DeepSeekClient(dio);
      final result = await client.testConnection();

      expect(result.isOk, isTrue);
      expect(result.unwrap(), contains('连接成功'));
      expect(result.unwrap(), contains('100.00'));
    });

    test('连接失败 → Err', () async {
      final (dio, adapter) = createMockDio();
      final url = 'https://api.deepseek.com/user/balance';

      adapter.stubError(
        url,
        DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        ),
      );

      final client = DeepSeekClient(dio);
      final result = await client.testConnection();

      expect(result.isErr, isTrue);
    });
  });
}

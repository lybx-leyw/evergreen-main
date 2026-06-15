import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/result.dart';
import '../../../core/errors.dart';
import '../../../core/log.dart';

/// DeepSeek API Client — ports electron/services/deepseek-client.js.
///
/// Handles chat completions, streaming, and account balance queries.
/// Returns [Result<T>] for all non-streaming methods, with typed [AiModelError]
/// and [ContextExceededError] for precise error recovery.
class DeepSeekClient {
  final Dio _dio;
  final String? _apiKey;
  final String _model;
  final String _thinking;
  Usage? _lastUsage;

  static const _baseUrl = 'https://api.deepseek.com';
  static const _modelContextTokens = {
    'deepseek-chat': 65536,
    'deepseek-reasoner': 65536,
    'deepseek-v4-flash': 131072,
    'deepseek-v4-pro': 131072,
  };

  DeepSeekClient(this._dio, {
    String? apiKey,
    String? model,
    String? thinking,
  })  : _apiKey = apiKey ?? AppConfig.deepseekApiKey,
        _model = model ?? AppConfig.deepseekModel ?? 'deepseek-v4-flash',
        _thinking = thinking ?? AppConfig.deepseekThinking ?? 'enabled';

  Usage? get lastUsage => _lastUsage;

  /// Maximum context window for the current model.
  int get maxContextTokens =>
      _modelContextTokens[_model] ?? 65536;

  /// Non-streaming chat completion.
  Future<Result<String>> chat(List<Map<String, dynamic>> messages,
      {int maxTokens = 4096}) async {
    final body = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'max_tokens': maxTokens,
      'stream': false,
    };

    if (_model.startsWith('deepseek-v4') || _model == 'deepseek-reasoner') {
      body['extra_body'] = {'thinking': _thinking};
    }

    final resResult = await _retryFetch(() => _dio.post(
          '$_baseUrl/chat/completions',
          data: body,
          options: Options(headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          }),
        ));

    if (resResult.isErr) return Err((resResult as Err<Response>).error);

    final res = (resResult as Ok<Response>).value;
    _lastUsage = Usage.fromApi(res.data);

    final content =
        res.data['choices']?[0]?['message']?['content']?.toString() ?? '';
    return Ok(content);
  }

  /// Streaming chat completion.
  ///
  /// Yields [StreamChunk] events. On initial connection failure, yields a
  /// single error chunk. On mid-stream errors, the stream closes via the
  /// error channel.
  Stream<StreamChunk> streamChat(List<Map<String, dynamic>> messages,
      {int maxTokens = 2048, double? temperature}) async* {
    final body = <String, dynamic>{
      'model': _model,
      'messages': messages,
      'max_tokens': maxTokens,
      'stream': true,
    };
    if (temperature != null) {
      body['temperature'] = temperature;
    }
    if (_model.startsWith('deepseek-v4') || _model == 'deepseek-reasoner') {
      body['extra_body'] = {'thinking': _thinking};
    }

    final resResult = await _retryFetch(() => _dio.post(
          '$_baseUrl/chat/completions',
          data: body,
          options: Options(
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            responseType: ResponseType.stream,
          ),
        ));

    if (resResult.isErr) {
      final err = (resResult as Err<Response>).error;
      yield StreamChunk(
          type: StreamChunkType.error,
          content: err.userMessage,
          error: err);
      return;
    }

    final response = (resResult as Ok<Response>).value;
    final byteStream = response.data.stream as Stream<List<int>>;
    StringBuffer pendingBuffer = StringBuffer();

    await for (final chunk in byteStream) {
      pendingBuffer.write(utf8.decode(chunk));
      final fullText = pendingBuffer.toString();
      final lastNewline = fullText.lastIndexOf('\n');
      if (lastNewline < 0) continue;

      final complete = fullText.substring(0, lastNewline);
      pendingBuffer = StringBuffer(fullText.substring(lastNewline + 1));

      for (final line in complete.split('\n')) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          yield StreamChunk(type: StreamChunkType.done, usage: _lastUsage);
          continue;
        }
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          if (delta['content'] != null) {
            yield StreamChunk(
                type: StreamChunkType.content,
                content: delta['content'] as String);
          }
          if (delta['reasoning_content'] != null) {
            yield StreamChunk(
                type: StreamChunkType.reasoning,
                content: delta['reasoning_content'] as String);
          }

          if (json['usage'] != null) {
            _lastUsage = Usage.fromApi(json);
          }
        } catch (_) {
          // Skip malformed chunks
        }
      }
    }
  }

  /// Test API connection.
  Future<Result<String>> testConnection() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/user/balance',
        options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      );
      final data = response.data;
      final balance = data['balance']?.toString() ?? '未知';
      Log().info('DeepSeek API connection test succeeded',
          data: {'balance': balance});
      return Ok('DeepSeek API 连接成功 (余额: $balance)');
    } on DioException catch (e, stack) {
      Log().warn('DeepSeek API connection test failed',
          error: e);
      return Err(_mapDioError(e));
    } catch (e, stack) {
      Log().error('DeepSeek API unexpected error', error: e);
      return Err(AppError.unknown(e));
    }
  }

  // ── Internal ───────────────────────────────────────────────────────

  /// Retry fetch with exponential backoff for transient errors (429, 502, 503).
  Future<Result<Response>> _retryFetch(
      Future<Response> Function() fn) async {
    for (var i = 0; i < 3; i++) {
      try {
        return Ok(await fn());
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 429 || status == 502 || status == 503) {
          Log().warn('DeepSeek transient error, retrying (${i + 1}/3)',
              data: {'status': status, 'model': _model});
          await Future.delayed(Duration(
              milliseconds: 1000 * pow(2, i).toInt() + Random().nextInt(1000)));
          continue;
        }
        // Non-retryable error — map to typed error
        return Err(_mapDioError(e));
      } catch (e, stack) {
        Log().error('DeepSeek unexpected fetch error',
            error: e, stack: stack);
        return Err(AppError.unknown(e));
      }
    }
    return Err(AppError.aiModelError(_model, 429)
      ..recoveryHint = 'AI 服务暂时不可用，已重试 3 次，请稍后再试');
  }

  /// Map a DioException to an appropriate AppError subtype.
  AppError _mapDioError(DioException e) {
    final status = e.response?.statusCode;

    // Context overflow detection: DeepSeek returns specific error messages
    final errorBody = e.response?.data;
    if (errorBody is Map) {
      final errorMsg = errorBody['error']?['message']?.toString() ?? '';
      if (errorMsg.contains('context length') ||
          errorMsg.contains('maximum context') ||
          errorMsg.contains('token limit') ||
          errorMsg.contains('too long')) {
        return AppError.contextExceeded(_model, 0, maxContextTokens);
      }
      if (errorMsg.contains('quota') ||
          errorMsg.contains('insufficient_quota') ||
          errorMsg.contains('balance')) {
        return AiModelError.quotaExhausted(_model);
      }
    }

    return AppError.aiModelError(_model, status);
  }
}

class Usage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int? promptCacheHitTokens;
  final int? promptCacheMissTokens;
  final double? cacheHitRatio;

  const Usage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    this.promptCacheHitTokens,
    this.promptCacheMissTokens,
    this.cacheHitRatio,
  });

  factory Usage.fromApi(Map<String, dynamic> json) {
    final usage = json['usage'] as Map<String, dynamic>? ?? {};
    return Usage(
      promptTokens: usage['prompt_tokens'] ?? 0,
      completionTokens: usage['completion_tokens'] ?? 0,
      totalTokens: usage['total_tokens'] ?? 0,
      promptCacheHitTokens: usage['prompt_cache_hit_tokens'],
      promptCacheMissTokens: usage['prompt_cache_miss_tokens'],
      cacheHitRatio: usage['cache_hit_ratio'] is num
          ? (usage['cache_hit_ratio'] as num).toDouble()
          : null,
    );
  }
}

enum StreamChunkType { content, reasoning, done, error }

class StreamChunk {
  final StreamChunkType type;
  final String? content;
  final Usage? usage;
  final AppError? error;

  const StreamChunk({
    required this.type,
    this.content,
    this.usage,
    this.error,
  });
}

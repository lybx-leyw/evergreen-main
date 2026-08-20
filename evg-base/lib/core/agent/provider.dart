/// LLM Provider 抽象 + DeepSeek 实现 — 对应 reasonix/internal/provider/。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'message.dart';
import 'event.dart';

// ═══════ AiUnavailableException ═══════

/// AI 服务不可用异常——当 LLM API 不可达、认证失败或超时时抛出。
///
/// 携带可操作的建议，供渲染层展示降级 UI。
class AiUnavailableException implements Exception {
  /// 错误原因（如 "connection_timeout", "invalid_api_key", "rate_limited"）。
  final String reason;

  /// 人类可读的错误信息。
  final String message;

  /// 建议的重试等待时间（秒），null 表示不确定。
  final int? retryAfterSeconds;

  /// 是否为可恢复错误（true=等待后可重试，false=需人工介入）。
  final bool recoverable;

  const AiUnavailableException({
    required this.reason,
    required this.message,
    this.retryAfterSeconds,
    this.recoverable = false,
  });

  /// 网络连接超时。
  factory AiUnavailableException.connectionTimeout({String? detail}) =>
      AiUnavailableException(
        reason: 'connection_timeout',
        message: detail ?? '无法连接到 AI 服务，请检查网络连接',
        retryAfterSeconds: 5,
        recoverable: true,
      );

  /// API Key 无效。
  factory AiUnavailableException.invalidApiKey() => AiUnavailableException(
        reason: 'invalid_api_key',
        message: 'API Key 无效，请在设置中重新配置',
        recoverable: false,
      );

  /// 频率限制。
  factory AiUnavailableException.rateLimited({int? retryAfterSeconds}) =>
      AiUnavailableException(
        reason: 'rate_limited',
        message: '请求过于频繁，请稍后重试',
        retryAfterSeconds: retryAfterSeconds ?? 10,
        recoverable: true,
      );

  /// 服务器内部错误。
  factory AiUnavailableException.serverError({int? statusCode}) =>
      AiUnavailableException(
        reason: 'server_error',
        message: 'AI 服务返回错误${statusCode != null ? " (HTTP $statusCode)" : ""}，请稍后重试',
        retryAfterSeconds: 15,
        recoverable: true,
      );

  /// 账户余额不足。
  factory AiUnavailableException.insufficientBalance() =>
      AiUnavailableException(
        reason: 'insufficient_balance',
        message: 'API 账户余额不足，请充值后再试',
        recoverable: false,
      );

  /// 模型不支持。
  factory AiUnavailableException.unsupportedModel(String model) =>
      AiUnavailableException(
        reason: 'unsupported_model',
        message: '模型 "$model" 不可用，已自动切换至默认模型',
        recoverable: true,
      );

  /// 从 HTTP 状态码创建。
  factory AiUnavailableException.fromStatusCode(int statusCode, {String? body}) {
    switch (statusCode) {
      case 401:
        return AiUnavailableException.invalidApiKey();
      case 402:
        return AiUnavailableException.insufficientBalance();
      case 429:
        return AiUnavailableException.rateLimited();
      case 500:
      case 502:
      case 503:
        return AiUnavailableException.serverError(statusCode: statusCode);
      default:
        return AiUnavailableException(
          reason: 'http_$statusCode',
          message: body ?? 'AI 服务返回 HTTP $statusCode',
          recoverable: statusCode >= 500,
        );
    }
  }

  @override
  String toString() => 'AiUnavailableException($reason): $message';
}

// ═══════ ProviderEventKind ═══════

/// Provider 事件种类。
enum ProviderEventKind { content, reasoning, toolCalls, usage, error, done }

// ═══════ Provider ═══════

/// LLM 提供者接口。对应 Go 的 provider.Provider。
abstract class Provider {
  /// 流式对话补全。
  ///
  /// 返回事件流：
  ///   - reasoning: 思考过程 delta
  ///   - text: 回答文本 delta
  ///   - tool_calls: 通过 [toolCallsDetected] 回调通知
  ///   - usage: token 用量
  ///
  /// [messages] 是对话历史。
  /// [tools] 是可用的工具定义列表。
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  });

  /// Provider 的名称/标识。
  String get name;
}

// ═══════ ProviderEvent ═══════

class ProviderEvent {
  final ProviderEventKind kind;
  final String? text;
  final List<ToolCall>? toolCalls;
  final TokenUsage? usage;
  final String? error;

  const ProviderEvent({
    required this.kind,
    this.text,
    this.toolCalls,
    this.usage,
    this.error,
  });

  factory ProviderEvent.content(String text) =>
      ProviderEvent(kind: ProviderEventKind.content, text: text);

  factory ProviderEvent.reasoning(String text) =>
      ProviderEvent(kind: ProviderEventKind.reasoning, text: text);

  factory ProviderEvent.toolCalls(List<ToolCall> calls) =>
      ProviderEvent(kind: ProviderEventKind.toolCalls, toolCalls: calls);

  factory ProviderEvent.usage(TokenUsage u) =>
      ProviderEvent(kind: ProviderEventKind.usage, usage: u);

  factory ProviderEvent.error(String e) =>
      ProviderEvent(kind: ProviderEventKind.error, error: e);

  factory ProviderEvent.done() =>
      const ProviderEvent(kind: ProviderEventKind.done);
}

// ═══════ DeepSeekProvider ═══════

/// DeepSeek API Provider。支持流式、function calling、自动重试。
///
/// [baseUrl] 可指向任意 OpenAI 兼容端点（如自定义代理 / 中转），
/// 默认 `https://api.deepseek.com`。模型 id 不做白名单限制——
/// 填写任意 OpenAI 兼容模型 id（如 `deepseek-chat`、`gpt-4o`）均可直通。
class DeepSeekProvider implements Provider {
  final Dio _dio;
  final String _apiKey;
  final String _baseUrl;
  String _model;
  String _thinking = 'enabled';
  String _reasoningEffort = '';
  TokenUsage? _lastUsage;

  static const String defaultBaseUrl = 'https://api.deepseek.com';

  /// 归一化 baseUrl：去首尾空白、去末尾斜杠，空值回退默认地址。
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.isEmpty ? defaultBaseUrl : u;
  }

  DeepSeekProvider({
    required Dio dio,
    required String apiKey,
    String model = 'deepseek-v4-flash',
    String thinking = 'enabled',
    String baseUrl = defaultBaseUrl,
  })  : _dio = dio,
        _apiKey = apiKey,
        _baseUrl = normalizeBaseUrl(baseUrl),
        _model = model,
        _thinking = thinking;

  @override
  String get name => _model;

  /// 获取最后一次调用的 token 用量。
  TokenUsage? get lastUsage => _lastUsage;

  /// 切换模型。
  void setModel(String model) => _model = model;

  /// 切换思考模式（enabled / disabled）。
  void setThinking(String thinking) {
    print('[Provider:D] 🔍 setThinking("$thinking") called — _thinking was "$_thinking"');
    _thinking = thinking;
  }

  /// 设置推理深度（'low' / 'medium' / 'high' / 'max' / '' 默认）。
  /// 由 [reasoningEffortProvider] 驱动，参见 agent_runtime.dart。
  void setReasoningEffort(String effort) => _reasoningEffort = effort;

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    final msgCount = messages.length;
    final toolCount = tools.length;
    print('[Provider:D] chat() called model=$_model messages=$msgCount tools=$toolCount'
        ' apiKey=${_apiKey.isNotEmpty ? "✅ ${_apiKey.substring(0, 8)}..." : "❌ null"}');

    final body = <String, dynamic>{
      'model': _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      'max_tokens': 16384,
    };

    if (_model.startsWith('deepseek-v4') || _model == 'deepseek-reasoner') {
      // API 文档：thinking 是顶层参数，type="enabled"/"disabled"
      if (_thinking == 'disabled') {
        body['thinking'] = <String, dynamic>{'type': 'disabled'};
        print('[Provider:D] thinking disabled — thinking.type=disabled');
      } else {
        final thinkingObj = <String, dynamic>{'type': 'enabled'};
        if (_reasoningEffort.isNotEmpty) {
          thinkingObj['reasoning_effort'] = _reasoningEffort;
        }
        body['thinking'] = thinkingObj;
      }
      print('[Provider:D] thinking=$_thinking reasoning_effort=$_reasoningEffort');
    }

    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
      print('[Provider:D] tools attached: ${tools.map((t) => t['function']?['name']).join(", ")}');
    }

    // 打印完整请求体用于调试
    final bodyJson = jsonEncode(body);
    print('[Provider:D] 🔍 REQUEST BODY: ${bodyJson.substring(0, (bodyJson.length).clamp(0, 500))}');

    try {
      print('[Provider:D] POST $_baseUrl/chat/completions streaming...');
      final response = await _retryFetch(() => _dio.post(
            '$_baseUrl/chat/completions',
            data: body,
            options: Options(
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
              },
              responseType: ResponseType.stream,
              receiveTimeout: const Duration(seconds: 120),
            ),
          ));
      print('[Provider:D] ✅ API response received, status=${response.statusCode}');

      final byteStream = response.data.stream as Stream<List<int>>;

      int lineNum = 0;
      int toolCallCount = 0;

      StringBuffer reasoningBuf = StringBuffer();
      StringBuffer contentBuf = StringBuffer();
      List<ToolCall>? pendingCalls;
      String _partialLine = '';

      StringBuffer pendingBuffer = StringBuffer();

      await for (final chunk in byteStream) {
        pendingBuffer.write(utf8.decode(chunk));
        // 按行分割，保留最后一个不完整的行
        final fullText = pendingBuffer.toString();
        final lastNewline = fullText.lastIndexOf('\n');
        if (lastNewline < 0) continue; // 还未收到完整的行

        final complete = fullText.substring(0, lastNewline);
        pendingBuffer = StringBuffer(fullText.substring(lastNewline + 1));

        for (final line in complete.split('\n')) {
        lineNum++;
        if (!line.startsWith('data: ')) {
          if (lineNum <= 3) print('[Provider:D] skip non-data line: ${line.substring(0, (line.length).clamp(0, 80))}');
          continue;
        }

        final data = line.substring(6).trim();
        if (lineNum <= 2 || data.contains('tool_calls') || data == '[DONE]') {
          print('[Provider:D] chunk#$lineNum data=${data.substring(0, (data.length).clamp(0, 120))}');
        }

        if (data == '[DONE]') {
          print('[Provider:D] ✅ [DONE] received — total lines=$lineNum toolCalls=$toolCallCount');
          if (pendingCalls != null && pendingCalls.isNotEmpty) {
            yield ProviderEvent.toolCalls(pendingCalls);
          }
          yield ProviderEvent.done();
          continue;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>? ?? {};
          final finishReason = choices[0]['finish_reason'] as String?;

          // reasoning_content
          if (delta['reasoning_content'] != null) {
            final r = delta['reasoning_content'] as String;
            if (r.isNotEmpty) {
              reasoningBuf.write(r);
              yield ProviderEvent.reasoning(r);
            }
          }

          // content
          if (delta['content'] != null) {
            final c = delta['content'] as String;
            if (c.isNotEmpty) {
              contentBuf.write(c);
              yield ProviderEvent.content(c);
            }
          }

          // tool_calls (delta 形式，可能分多次到达)
          if (delta['tool_calls'] != null) {
            final tcList = delta['tool_calls'] as List;
            pendingCalls ??= [];

            // DeepSeek 的 tool_calls delta 需要合并
            for (final tc in tcList) {
              final index = tc['index'] as int? ?? 0;
              final func = tc['function'] as Map<String, dynamic>? ?? {};
              final tcId = tc['id']?.toString();

              // 按 index 合并：新 index 创建新 call，已有 index 追加内容
              while (pendingCalls.length <= index) {
                pendingCalls.add(ToolCall(id: '', name: '', arguments: ''));
              }
              if (tcId != null && tcId.isNotEmpty) {
                pendingCalls[index] = ToolCall(
                  id: tcId,
                  name: pendingCalls[index].name,
                  arguments: pendingCalls[index].arguments,
                );
              }
              if (func['name'] != null && (func['name'] as String).isNotEmpty) {
                pendingCalls[index] = ToolCall(
                  id: pendingCalls[index].id,
                  name: func['name'] as String,
                  arguments: pendingCalls[index].arguments,
                );
              }
              if (func['arguments'] != null) {
                final argStr = func['arguments'] as String;
                pendingCalls[index] = ToolCall(
                  id: pendingCalls[index].id,
                  name: pendingCalls[index].name,
                  arguments: pendingCalls[index].arguments + argStr,
                );
              }
            }
          }

          // usage
          if (json['usage'] != null) {
            _lastUsage = TokenUsage.fromApi(json['usage'] as Map<String, dynamic>);
            yield ProviderEvent.usage(_lastUsage!);
          }

          // finish_reason = tool_calls → 工具调用收集完成
          if (finishReason == 'tool_calls' && pendingCalls != null && pendingCalls.isNotEmpty) {
            print('[Provider:D] finish_reason=tool_calls calls=${pendingCalls.length}');
            for (final c in pendingCalls) {
              print('[Provider:D]   call: ${c.name} args=${c.arguments.substring(0, (c.arguments.length).clamp(0, 100))}');
            }
            // 补全可能缺失的 ID
            for (var i = 0; i < pendingCalls.length; i++) {
              if (pendingCalls[i].id.isEmpty) {
                pendingCalls[i] = ToolCall(
                  id: 'call_${DateTime.now().millisecondsSinceEpoch}_$i',
                  name: pendingCalls[i].name,
                  arguments: pendingCalls[i].arguments,
                );
              }
            }
            toolCallCount = pendingCalls.length;
            yield ProviderEvent.toolCalls(pendingCalls);
            pendingCalls = null;
          }

          // finish_reason = stop → done
          if (finishReason == 'stop') {
            print('[Provider:D] finish_reason=stop');
            yield ProviderEvent.done();
          }
        } catch (e) {
          // 跳过解析失败的 chunk
          continue;
        }
      } // end for (line)
    } // end await for (chunk)
    } catch (e) {
      yield ProviderEvent.error('API call failed: $e');
    }
  }

  /// 测试 API 连接。
  Future<String> testConnection() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/user/balance',
        options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      );
      final data = response.data;
      return 'DeepSeek API 连接成功 (余额: ${data['balance'] ?? '未知'})';
    } catch (e) {
      return 'API 连接失败: $e';
    }
  }

  /// 带指数退避的重试。
  Future<Response> _retryFetch(Future<Response> Function() fn) async {
    for (var i = 0; i < 3; i++) {
      try {
        return await fn();
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 429 || status == 502 || status == 503) {
          await Future.delayed(
              Duration(milliseconds: 1000 * (1 << i) + DateTime.now().millisecond % 1000));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('API 请求失败，已重试 3 次');
  }
}

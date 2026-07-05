/// LLM Provider 抽象 + DeepSeek 实现。
///
/// 对应 reasonix/internal/provider/ 和 provider/openai/。
/// Provider 接口封装了 LLM API 调用，支持 streaming + function calling。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'message.dart';
import 'event.dart';

// ─── Provider 接口 ─────────────────────────────────────────

/// LLM 提供者——一个可流式对话的模型后端。
///
/// 对应 Go 的 provider.Provider。
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

/// Provider 发射的事件类型。
enum ProviderEventKind { content, reasoning, toolCalls, usage, error, done }

/// Provider 事件。
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

// ─── DeepSeek Provider ────────────────────────────────────

/// DeepSeek API 的 Provider 实现。
///
/// 支持：
///   - 流式 content/reasoning/tool_calls
///   - Function calling
///   - 自动重试（429/502/503）
///   - Token 用量统计
///   - 前缀缓存命中率
class DeepSeekProvider implements Provider {
  final Dio _dio;
  final String _apiKey;
  String _model;
  String _thinking = 'enabled';
  String _reasoningEffort = '';
  TokenUsage? _lastUsage;

  static const String _baseUrl = 'https://api.deepseek.com';

  DeepSeekProvider({
    required Dio dio,
    required String apiKey,
    String model = 'deepseek-v4-flash',
    String thinking = 'enabled',
  })  : _dio = dio,
        _apiKey = apiKey,
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

  /// 设置推理深度（'' / 'high' / 'max'）。
  void setReasoningEffort(String effort) => _reasoningEffort = effort;

  @override
  Stream<ProviderEvent> chat({
    required List<Message> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    final msgCount = messages.length;
    final toolCount = tools.length;
    print('[Provider:D] chat() called model=$_model messages=$msgCount tools=$toolCount'
        ' apiKey=${_apiKey != null && _apiKey!.isNotEmpty ? "✅ ${_apiKey!.substring(0, 8)}..." : "❌ null"}');

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
              while (pendingCalls!.length <= index) {
                pendingCalls!.add(ToolCall(id: '', name: '', arguments: ''));
              }
              if (tcId != null && tcId.isNotEmpty) {
                pendingCalls![index] = ToolCall(
                  id: tcId,
                  name: pendingCalls![index].name,
                  arguments: pendingCalls![index].arguments,
                );
              }
              if (func['name'] != null && (func['name'] as String).isNotEmpty) {
                pendingCalls![index] = ToolCall(
                  id: pendingCalls![index].id,
                  name: func['name'] as String,
                  arguments: pendingCalls![index].arguments,
                );
              }
              if (func['arguments'] != null) {
                final argStr = func['arguments'] as String;
                pendingCalls![index] = ToolCall(
                  id: pendingCalls![index].id,
                  name: pendingCalls![index].name,
                  arguments: pendingCalls![index].arguments + argStr,
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
            print('[Provider:D] finish_reason=tool_calls calls=${pendingCalls!.length}');
            for (final c in pendingCalls!) {
              print('[Provider:D]   call: ${c.name} args=${c.arguments.substring(0, (c.arguments.length).clamp(0, 100))}');
            }
            // 补全可能缺失的 ID
            for (var i = 0; i < pendingCalls!.length; i++) {
              if (pendingCalls![i].id.isEmpty) {
                pendingCalls![i] = ToolCall(
                  id: 'call_${DateTime.now().millisecondsSinceEpoch}_$i',
                  name: pendingCalls![i].name,
                  arguments: pendingCalls![i].arguments,
                );
              }
            }
            toolCallCount = pendingCalls!.length;
            yield ProviderEvent.toolCalls(pendingCalls!);
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

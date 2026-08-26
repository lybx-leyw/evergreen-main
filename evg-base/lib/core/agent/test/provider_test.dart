/// AiUnavailableException + MockEventStream + Provider 测试。
library;


import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../message.dart';
import '../provider.dart';
import '../event.dart';
import '../tools/mock_event_stream.dart';
import '../tools/ocr_attachment_handler.dart';

void main() {
  // ═══════ AiUnavailableException ═══════

  group('AiUnavailableException', () {
    test('connectionTimeout factory', () {
      final e = AiUnavailableException.connectionTimeout(detail: 'DNS 解析失败');
      expect(e.reason, 'connection_timeout');
      expect(e.message, contains('DNS'));
      expect(e.recoverable, isTrue);
      expect(e.retryAfterSeconds, 5);
    });

    test('invalidApiKey factory', () {
      final e = AiUnavailableException.invalidApiKey();
      expect(e.reason, 'invalid_api_key');
      expect(e.recoverable, isFalse);
    });

    test('rateLimited factory', () {
      final e = AiUnavailableException.rateLimited(retryAfterSeconds: 30);
      expect(e.reason, 'rate_limited');
      expect(e.retryAfterSeconds, 30);
      expect(e.recoverable, isTrue);
    });

    test('serverError factory', () {
      final e = AiUnavailableException.serverError(statusCode: 503);
      expect(e.reason, 'server_error');
      expect(e.message, contains('503'));
      expect(e.recoverable, isTrue);
    });

    test('insufficientBalance factory', () {
      final e = AiUnavailableException.insufficientBalance();
      expect(e.reason, 'insufficient_balance');
      expect(e.recoverable, isFalse);
    });

    test('unsupportedModel factory', () {
      final e = AiUnavailableException.unsupportedModel('gpt-7');
      expect(e.message, contains('gpt-7'));
      expect(e.recoverable, isTrue);
    });

    test('fromStatusCode: 401 → invalidApiKey', () {
      final e = AiUnavailableException.fromStatusCode(401);
      expect(e.reason, 'invalid_api_key');
    });

    test('fromStatusCode: 402 → insufficientBalance', () {
      final e = AiUnavailableException.fromStatusCode(402);
      expect(e.reason, 'insufficient_balance');
    });

    test('fromStatusCode: 429 → rateLimited', () {
      final e = AiUnavailableException.fromStatusCode(429);
      expect(e.reason, 'rate_limited');
    });

    test('fromStatusCode: 500/502/503 → serverError', () {
      for (final code in [500, 502, 503]) {
        final e = AiUnavailableException.fromStatusCode(code);
        expect(e.reason, 'server_error');
      }
    });

    test('fromStatusCode: 5xx → recoverable', () {
      final e = AiUnavailableException.fromStatusCode(500);
      expect(e.recoverable, isTrue);
    });

    test('fromStatusCode: 4xx → non-recoverable (except 429)', () {
      final e = AiUnavailableException.fromStatusCode(404);
      expect(e.recoverable, isFalse);
    });

    test('toString includes reason and message', () {
      final e = AiUnavailableException.connectionTimeout();
      final s = e.toString();
      expect(s, contains('connection_timeout'));
      expect(s, contains('无法连接'));
    });

    test('implements Exception', () {
      final e = AiUnavailableException.connectionTimeout();
      expect(e, isA<Exception>());
    });
  });

  // ═══════ MockEventStream ═══════

  group('MockEventStream', () {
    test('eventKindReference covers all 18 kinds', () {
      final ref = MockEventStream.eventKindReference;
      expect(ref.length, 18);
      final covered = ref.map((r) => r['kind']).toSet();
      for (final kind in EventKind.values) {
        expect(covered, contains(kind.name),
            reason: 'MockEventStream reference missing: ${kind.name}');
      }
    });

    test('generate yields all required event kinds', () async {
      final seenKinds = <EventKind>{};
      await for (final event in MockEventStream.generate(delay: Duration.zero)) {
        seenKinds.add(event.kind);
      }

      // Must cover: turnStarted, reasoning, text, phase, toolDispatch,
      //   toolResult, toolProgress, message, usage, notice, approvalRequest,
      //   askRequest, retrying, compactionStarted, compactionDone, mcpSurfaceReady, turnDone
      expect(seenKinds, contains(EventKind.turnStarted));
      expect(seenKinds, contains(EventKind.reasoning));
      expect(seenKinds, contains(EventKind.text));
      expect(seenKinds, contains(EventKind.phase));
      expect(seenKinds, contains(EventKind.toolDispatch));
      expect(seenKinds, contains(EventKind.toolResult));
      expect(seenKinds, contains(EventKind.toolProgress));
      expect(seenKinds, contains(EventKind.message));
      expect(seenKinds, contains(EventKind.usage));
      expect(seenKinds, contains(EventKind.notice));
      expect(seenKinds, contains(EventKind.approvalRequest));
      expect(seenKinds, contains(EventKind.askRequest));
      expect(seenKinds, contains(EventKind.retrying));
      expect(seenKinds, contains(EventKind.compactionStarted));
      expect(seenKinds, contains(EventKind.compactionDone));
      expect(seenKinds, contains(EventKind.mcpSurfaceReady));
      expect(seenKinds, contains(EventKind.turnDone));
    });

    test('generate yields at least 25 events', () async {
      var count = 0;
      await for (final _ in MockEventStream.generate(delay: Duration.zero)) {
        count++;
      }
      expect(count, greaterThanOrEqualTo(25));
    });

    test('toolDispatch events have complete payload', () async {
      ToolEventPayload? dispatch;
      await for (final event in MockEventStream.generate(delay: Duration.zero)) {
        if (event.kind == EventKind.toolDispatch && event.tool != null) {
          dispatch = event.tool;
          break;
        }
      }
      expect(dispatch, isNotNull);
      expect(dispatch!.id, isNotEmpty);
      expect(dispatch.name, isNotEmpty);
      expect(dispatch.arguments, isNotEmpty);
    });

    test('toolResult with error has isError=true', () async {
      ToolEventPayload? errorResult;
      await for (final event in MockEventStream.generate(delay: Duration.zero)) {
        if (event.kind == EventKind.toolResult && event.tool?.isError == true) {
          errorResult = event.tool;
          break;
        }
      }
      expect(errorResult, isNotNull);
      expect(errorResult!.error, contains('超时'));
    });

    test('turnDone with error signals failure', () async {
      AgentEvent? errorDone;
      await for (final event in MockEventStream.generate(delay: Duration.zero)) {
        if (event.kind == EventKind.turnDone && event.error != null) {
          errorDone = event;
          break;
        }
      }
      expect(errorDone, isNotNull);
      expect(errorDone!.error, contains('超时'));
    });
  });

  // ═══════ OcrAttachmentHandler ═══════

  group('OcrAttachmentHandler', () {
    test('process empty list returns empty', () async {
      final handler = OcrAttachmentHandler(
        recognize: (_) async => 'text',
        sink: null,
      );
      final results = await handler.process([]);
      expect(results, isEmpty);
    });

    test('process single file returns OcrResult', () async {
      final handler = OcrAttachmentHandler(
        recognize: (path) async => 'OCR content for $path',
        sink: null,
      );
      final results = await handler.process(['/tmp/test.png']);
      expect(results.length, 1);
      expect(results.first.isSuccess, isTrue);
      expect(results.first.text, contains('OCR content'));
      expect(results.first.isImage, isTrue);
    });

    test('process handles OCR failure gracefully', () async {
      final handler = OcrAttachmentHandler(
        recognize: (_) async => throw Exception('OCR engine crash'),
        sink: null,
      );
      final results = await handler.process(['/tmp/bad.png']);
      expect(results.length, 1);
      expect(results.first.isSuccess, isFalse);
      expect(results.first.error, contains('Exception'));
    });

    test('toContextString formats results', () {
      final handler = OcrAttachmentHandler(recognize: (_) async => '');
      final results = [
        OcrResult(filePath: '/tmp/a.png', text: 'hello world', mimeType: 'image/png'),
        OcrResult(filePath: '/tmp/b.pdf', error: 'timeout', mimeType: 'application/pdf'),
      ];
      final ctx = handler.toContextString(results);
      expect(ctx, contains('附件 OCR 内容'));
      expect(ctx, contains('a.png'));
      expect(ctx, contains('hello world'));
      expect(ctx, contains('b.pdf'));
      expect(ctx, contains('识别失败'));
      expect(ctx, contains('timeout'));
    });

    test('toContextString empty returns empty string', () {
      final handler = OcrAttachmentHandler(recognize: (_) async => '');
      expect(handler.toContextString([]), '');
    });

    test('mime type detection by extension', () async {
      final handler = OcrAttachmentHandler(
        recognize: (path) async => 'content',
        sink: null,
      );
      final imageTypes = ['a.png', 'a.jpg', 'a.jpeg', 'a.webp', 'a.pdf'];
      for (final file in imageTypes) {
        final results = await handler.process(['/tmp/$file']);
        expect(results.first.isImage || results.first.isPdf, isTrue,
            reason: '$file should be detected as image or pdf');
      }
      final results = await handler.process(['/tmp/a.txt']);
      expect(results.first.isImage || results.first.isPdf, isFalse,
          reason: 'txt should not be detected as image or pdf');
    });
  });

  // ═══════ DeepSeekProvider chat() 协议路由（Task 五 A5） ═══════
  //
  // 通过覆写 dio stub 的 post() 捕获请求体，验证 thinking / reasoning_effort
  // 按「模型支持矩阵」路由：
  //   - deepseek 系列 → 顶层 thinking:{type}，不嵌套 reasoning_effort；
  //   - OpenAI o 系列（o1/o3/o4 或 gpt-* 且思考开启）→ 顶层 reasoning_effort；
  //   - 其他模型 → 不发送任何 thinking/effort。

  group('DeepSeekProvider chat() 协议路由', () {
    Future<Map<String, dynamic>> captureBody({
      required String model,
      String thinking = 'enabled',
      String effort = '',
      List<Map<String, dynamic>> tools = const [],
    }) async {
      final dio = _CapturingDio();
      final provider = DeepSeekProvider(
        dio: dio,
        apiKey: 'test-key',
        model: model,
        thinking: thinking,
      );
      provider.setReasoningEffort(effort);
      await provider
          .chat(messages: [Message.user('hi')], tools: tools)
          .toList();
      expect(dio.lastBody, isNotNull,
          reason: 'chat() 应已发起 POST 并捕获请求体（模型=$model）');
      return dio.lastBody!;
    }

    test('deepseek 模型: 顶层 thinking:{type:enabled}，不嵌套 reasoning_effort', () async {
      final body = await captureBody(model: 'deepseek-v4-flash', effort: 'high');
      expect(body['thinking'], {'type': 'enabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('deepseek 系列全前缀生效（deepseek-chat / deepseek-reasoner / deepseek-v4-pro）', () async {
      for (final model in ['deepseek-chat', 'deepseek-reasoner', 'deepseek-v4-pro']) {
        final body = await captureBody(model: model);
        expect(body['thinking'], {'type': 'enabled'}, reason: model);
        expect(body.containsKey('reasoning_effort'), isFalse, reason: model);
      }
    });

    test('deepseek + thinking=disabled → thinking:{type:disabled}', () async {
      final body = await captureBody(model: 'deepseek-v4-flash', thinking: 'disabled');
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('deepseek + off → thinking:{type:disabled}', () async {
      final body = await captureBody(model: 'deepseek-v4-flash', effort: 'off');
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('deepseek 模型不发送 reasoning_effort（即使 max）', () async {
      final body = await captureBody(model: 'deepseek-v4-flash', effort: 'max');
      expect(body['thinking'], {'type': 'enabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
      // 且 thinking 对象内也无嵌套
      expect((body['thinking'] as Map).containsKey('reasoning_effort'), isFalse);
    });

    test('o1 模型 + low → 顶层 reasoning_effort:low，无 thinking 对象', () async {
      final body = await captureBody(model: 'o1-preview', effort: 'low');
      expect(body['reasoning_effort'], 'low');
      expect(body.containsKey('thinking'), isFalse);
    });

    test('o3/o4 模型名命中 o 系列路由', () async {
      for (final model in ['o3-mini', 'o4-mini']) {
        final body = await captureBody(model: model, effort: 'medium');
        expect(body['reasoning_effort'], 'medium', reason: model);
        expect(body.containsKey('thinking'), isFalse, reason: model);
      }
    });

    test('max → 映射为 reasoning_effort:high', () async {
      final body = await captureBody(model: 'o1-preview', effort: 'max');
      expect(body['reasoning_effort'], 'high');
      expect(body.containsKey('thinking'), isFalse);
    });

    test('o1 + off → 不发送 reasoning_effort', () async {
      final body = await captureBody(model: 'o1-preview', effort: 'off');
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('o1 + 空 effort（缺省）→ 不发送 reasoning_effort', () async {
      final body = await captureBody(model: 'o1-preview');
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('o1 + 非法 effort → 不发送 reasoning_effort（未知值静默忽略）', () async {
      final body = await captureBody(model: 'o1-preview', effort: 'ultra');
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('gpt-* + thinking 开启 → 顶层 reasoning_effort', () async {
      final body = await captureBody(model: 'gpt-4o', thinking: 'enabled', effort: 'high');
      expect(body['reasoning_effort'], 'high');
      expect(body.containsKey('thinking'), isFalse);
    });

    test('gpt-* + thinking 关闭 → 不发送任何 thinking/effort', () async {
      final body = await captureBody(model: 'gpt-4o', thinking: 'disabled', effort: 'high');
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('其他 OpenAI 兼容模型 → 不发送任何 thinking/effort', () async {
      // 注：gpt-* 模型在 thinking 开启时属 o 系列路由（见上），此处只测非 gpt/deepseek 模型。
      for (final model in ['moonshot-v1-8k', 'qwen-max', 'claude-3-5-sonnet']) {
        final body = await captureBody(model: model, effort: 'high');
        expect(body.containsKey('thinking'), isFalse, reason: model);
        expect(body.containsKey('reasoning_effort'), isFalse, reason: model);
      }
    });

    test('tools 附加不受路由影响（o 系列 + tools）', () async {
      final body = await captureBody(
        model: 'o1-preview',
        effort: 'high',
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'web_search',
              'description': 'search',
              'parameters': <String, dynamic>{},
            },
          },
        ],
      );
      expect(body['reasoning_effort'], 'high');
      expect(body['tools'], isA<List>());
      expect(body['tool_choice'], 'auto');
      expect((body['tools'] as List).length, 1);
    });
  });
}

/// 捕获请求体的 Dio 替身（覆写 dio stub 的 post，返回空 SSE 流）。
class _CapturingDio extends Dio {
  _CapturingDio();

  Map<String, dynamic>? lastBody;

  @override
  Future<Response> post(String path, {dynamic data, Options? options}) async {
    lastBody = data as Map<String, dynamic>?;
    // ResponseType.stream 下 chat() 读取 response.data.stream
    return Response(
      statusCode: 200,
      data: _EmptyStreamBody(Stream<List<int>>.fromIterable(const [])),
    );
  }
}

/// 模拟 Dio ResponseType.stream 的响应体（含 .stream getter）。
class _EmptyStreamBody {
  final Stream<List<int>> stream;
  _EmptyStreamBody(this.stream);
}

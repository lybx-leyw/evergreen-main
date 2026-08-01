/// AiUnavailableException + MockEventStream + Provider 测试。
library;


import 'package:test/test.dart';

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
    test('eventKindReference covers all 17 kinds', () {
      final ref = MockEventStream.eventKindReference;
      expect(ref.length, 17);
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
}

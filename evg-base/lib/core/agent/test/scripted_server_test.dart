/// ScriptedAgentHttpServer 集成测试 — 覆盖场景 [3][4] + 全部端点。
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../event.dart';
import '../tools/scripted_agent_http_server.dart';

// ═══════ helpers ═══════

Future<HttpClientRequest> _post(HttpClient client, int port, String path, Map<String, dynamic> body) async {
  final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
  req.headers.set('Content-Type', 'application/json; charset=utf-8');
  final bytes = utf8.encode(jsonEncode(body));
  req.contentLength = bytes.length;
  req.add(bytes);
  return req;
}

Future<Map<String, dynamic>> _getJson(HttpClient client, int port, String path) async {
  final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  final resp = await req.close();
  final body = await resp.transform(utf8.decoder).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> _readSse(HttpClientResponse resp) async {
  final events = <Map<String, dynamic>>[];
  final text = await resp.transform(utf8.decoder).join();
  for (final line in text.split('\n')) {
    if (line.startsWith('data: ')) {
      final data = line.substring(6).trim();
      if (data.isNotEmpty) {
        events.add(jsonDecode(data) as Map<String, dynamic>);
      }
    }
  }
  return events;
}

// ═══════ tests ═══════

void main() {
  group('ScriptedAgentHttpServer', () {
    late ScriptedAgentHttpServer server;
    late int port;
    late HttpClient client;

    setUp(() async {
      server = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario3());
      port = await server.start();
      client = HttpClient();
    });

    tearDown(() {
      server.stop();
      client.close();
    });

    test('start writes port file', () async {
      final tmpFile = '${Directory.systemTemp.path}${Platform.pathSeparator}test_agent_port_${DateTime.now().millisecondsSinceEpoch}';
      final s = ScriptedAgentHttpServer(
        scenario: ScriptedAgentHttpServer.scenario3(),
        portFile: tmpFile,
      );
      final p = await s.start();
      expect(File(tmpFile).existsSync(), isTrue);
      expect(File(tmpFile).readAsStringSync().trim(), '$p');
      s.stop();
      File(tmpFile).deleteSync();
    });

    test('GET /health returns scripted mode', () async {
      final data = await _getJson(client, port, '/health');
      expect(data['status'], 'ok');
      expect(data['mode'], 'scripted');
      expect(data['scenario_events'], greaterThan(0));
    });

    test('POST /agent/chat/stream returns SSE with scenario events', () async {
      final req = await _post(client, port, '/agent/chat/stream', {'input': '明天什么课'});
      final resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.contentType?.mimeType, 'text/event-stream');

      final events = await _readSse(resp);
      expect(events.isNotEmpty, isTrue);

      // 验证关键事件类型
      final types = events.map((e) => e['type'] as String).toList();
      expect(types, contains('turn_started'));
      expect(types, contains('tool_dispatch'));
      expect(types, contains('tool_result'));
      expect(types, contains('text'));
      expect(types, contains('turn_done'));
    });

    test('POST /agent/chat/stream scenario[3] has check_schedule tool', () async {
      final req = await _post(client, port, '/agent/chat/stream', {'input': '任意'});
      final resp = await req.close();
      final events = await _readSse(resp);

      final toolDispatch = events.firstWhere((e) => e['type'] == 'tool_dispatch');
      expect(toolDispatch['name'], 'check_schedule');

      final toolResult = events.firstWhere((e) => e['type'] == 'tool_result');
      expect(toolResult['output'], contains('高等数学'));
      expect(toolResult['output'], contains('B201'));
    });

    test('POST /agent/chat returns JSON event array', () async {
      final req = await _post(client, port, '/agent/chat', {'input': 'test'});
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      expect(data['mode'], 'scripted');
      final events = data['events'] as List;
      expect(events.isNotEmpty, isTrue);
    });

    test('GET /agent/tools returns empty list', () async {
      final data = await _getJson(client, port, '/agent/tools');
      expect(data['tools'], isEmpty);
      expect(data['mode'], 'scripted');
    });

    test('GET /agent/config returns scripted mode', () async {
      final data = await _getJson(client, port, '/agent/config');
      expect(data['provider'], 'scripted');
      expect(data['mode'], 'scripted');
    });

    test('unknown endpoint returns scripted note', () async {
      final data = await _getJson(client, port, '/agent/memory');
      expect(data['mode'], 'scripted');
      expect(data['available'], false);
      expect(data['note'], isNotEmpty);
    });
  });

  group('Scenario [4] cross-module', () {
    late ScriptedAgentHttpServer server;
    late int port;
    late HttpClient client;

    setUp(() async {
      server = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario4());
      port = await server.start();
      client = HttpClient();
    });

    tearDown(() {
      server.stop();
      client.close();
    });

    test('contains two tool_dispatch events', () async {
      final req = await _post(client, port, '/agent/chat/stream', {'input': 'test'});
      final resp = await req.close();
      final events = await _readSse(resp);

      final dispatches = events.where((e) => e['type'] == 'tool_dispatch').toList();
      expect(dispatches.length, 2);
      final names = dispatches.map((e) => e['name']).toSet();
      expect(names, containsAll(['check_schedule', 'get_pomodoro']));
    });

    test('contains two tool_result events with outputs', () async {
      final req = await _post(client, port, '/agent/chat/stream', {'input': 'test'});
      final resp = await req.close();
      final events = await _readSse(resp);

      final results = events.where((e) => e['type'] == 'tool_result').toList();
      expect(results.length, 2);

      final outputs = results.map((e) => e['output'] as String).toList();
      final hasSchedule = outputs.any((o) => o.contains('高等数学'));
      final hasPomodoro = outputs.any((o) => o.contains('番茄钟'));
      expect(hasSchedule, isTrue);
      expect(hasPomodoro, isTrue);
    });

    test('text event mentions both schedule and pomodoro', () async {
      final req = await _post(client, port, '/agent/chat/stream', {'input': 'test'});
      final resp = await req.close();
      final events = await _readSse(resp);

      final texts = events
          .where((e) => e['type'] == 'text')
          .map((e) => e['text'] as String)
          .join();
      expect(texts, contains('高等数学'));
      expect(texts, contains('番茄钟'));
    });
  });

  group('ScriptedAgentHttpServer preset validation', () {
    test('scenario3 has at least 6 events', () {
      expect(ScriptedAgentHttpServer.scenario3().length, greaterThanOrEqualTo(6));
    });

    test('scenario3 starts with turnStarted', () {
      expect(ScriptedAgentHttpServer.scenario3().first.kind, EventKind.turnStarted);
    });

    test('scenario3 ends with turnDone', () {
      expect(ScriptedAgentHttpServer.scenario3().last.kind, EventKind.turnDone);
    });

    test('scenario4 has two distinct tool names', () {
      final s4 = ScriptedAgentHttpServer.scenario4();
      final toolNames = s4
          .where((e) => e.kind == EventKind.toolDispatch)
          .map((e) => e.tool!.name)
          .toSet();
      expect(toolNames.length, 2);
    });

    test('scenario4 tool call IDs match between dispatch and result', () {
      final s4 = ScriptedAgentHttpServer.scenario4();
      final dispatchIds = s4
          .where((e) => e.kind == EventKind.toolDispatch)
          .map((e) => e.tool!.id)
          .toSet();
      final resultIds = s4
          .where((e) => e.kind == EventKind.toolResult)
          .map((e) => e.tool!.id)
          .toSet();
      expect(dispatchIds, resultIds);
    });
  });
}

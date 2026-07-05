/// Scripted Agent HTTP Server — 供 Core 层集成测试使用，无需真实 AI Provider。
///
/// 接受预编排的 [AgentEvent] 脚本，`/agent/chat/stream` 直接输出 SSE 流。
/// 不依赖 Controller / Provider / API Key，可纯 `dart run` 独立启动。
///
/// ## 用法
/// ```dart
/// final server = ScriptedAgentHttpServer(scenario: ScriptedAgentHttpServer.scenario3());
/// final port = await server.start();
/// // POST http://127.0.0.1:$port/agent/chat/stream {"input":"任意文本"}
/// // → SSE: turnStarted → toolDispatch → toolResult → text → turnDone
/// server.stop();
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../event.dart';
import '../tool.dart';
import 'event_serializers.dart';

// ═══════ ScriptedAgentHttpServer ═══════

/// 预编排 HTTP 服务器——用固定事件脚本替代真实 Agent 主循环。
class ScriptedAgentHttpServer {
  final List<AgentEvent> _scenario;
  final Registry _registry;
  final String? _portFile;

  HttpServer? _server;

  ScriptedAgentHttpServer({
    required List<AgentEvent> scenario,
    Registry? registry,
    String? portFile,
  })  : _scenario = List.unmodifiable(scenario),
        _registry = registry ?? Registry(),
        _portFile = portFile;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// 启动服务器，返回监听端口。
  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final p = _server!.port;

    if (_portFile != null) {
      File(_portFile!).writeAsStringSync('$p');
      stderr.writeln('[ScriptedAgent] 端口 $p → $_portFile');
    }

    stderr.writeln('[ScriptedAgent] http://127.0.0.1:$p (mode: scripted)');
    _server!.listen(_handle);
    return p;
  }

  /// 停止服务器。
  void stop() {
    _server?.close();
    _server = null;
  }

  // ── 路由 ──

  Future<void> _handle(HttpRequest req) async {
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    final path = req.uri.path;

    try {
      if (path == '/health')                  return await _health(req);
      if (path == '/agent/chat/stream')       return await _chatStream(req);
      if (path == '/agent/chat')              return await _chat(req);
      if (path == '/agent/sessions')          return _json(req.response, 200, {'sessions': [], 'mode': 'scripted'});
      if (path == '/agent/tools')             return await _listTools(req);
      if (path == '/agent/config')            return _json(req.response, 200, {'provider': 'scripted', 'toolsCount': _registry.enabled().length, 'mode': 'scripted'});
      if (path == '/agent/styles')            return _json(req.response, 200, {'styles': [], 'mode': 'scripted'});
      if (path == '/agent/skills')            return _json(req.response, 200, {'skills': [], 'mode': 'scripted'});

      // 其他端点：返回 scripted 模式提示
      _json(req.response, 200, {'mode': 'scripted', 'available': false, 'note': '此端点仅在完整 AgentHttpServer 中可用'});
    } catch (e, st) {
      stderr.writeln('[ScriptedAgent] ❌ $path: $e\n$st');
      try {
        _json(req.response, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  // ── 端点 ──

  Future<void> _health(HttpRequest req) async {
    _json(req.response, 200, {
      'status': 'ok',
      'mode': 'scripted',
      'tools': _registry.enabled().length,
      'scenario_events': _scenario.length,
    });
  }

  Future<void> _chatStream(HttpRequest req) async {
    // 忽略 input——始终返回预编排场景
    req.response.statusCode = 200;
    req.response.headers.set('Content-Type', 'text/event-stream');
    req.response.headers.set('Cache-Control', 'no-cache');
    req.response.headers.set('Connection', 'keep-alive');

    try {
      for (final event in _scenario) {
        final frame = eventToSseFrame(event);
        req.response.add(utf8.encode('data: $frame\n\n'));
      }
    } catch (e) {
      stderr.writeln('[ScriptedAgent] SSE write error: $e');
    } finally {
      await req.response.close();
    }
  }

  Future<void> _chat(HttpRequest req) async {
    final events = _scenario
        .where((e) => e.kind != EventKind.turnStarted)
        .map(eventToJsonMap)
        .toList();
    _json(req.response, 200, {'events': events, 'mode': 'scripted'});
  }

  Future<void> _listTools(HttpRequest req) async {
    _json(req.response, 200, {
      'tools': _registry.enabled().map((t) => {
        'name': t.name,
        'description': t.description,
        'readOnly': t.readOnly,
      }).toList(),
      'mode': 'scripted',
    });
  }

  // ── 预设场景 ──

  /// 场景 [3]：单工具调用——查课表。
  ///
  /// Core 集成测试 §六 场景 3。
  static List<AgentEvent> scenario3() => [
    AgentEvent.turnStarted(),
    AgentEvent.toolDispatch(ToolEventPayload(
      id: 'call_sched',
      name: 'check_schedule',
      arguments: '{}',
      readOnly: true,
    )),
    AgentEvent.toolResult(ToolEventPayload(
      id: 'call_sched',
      name: 'check_schedule',
      arguments: '{}',
      output: '高等数学 B201 教室\n线性代数 C305 教室\n大学英语 A102 教室',
    )),
    AgentEvent.text('明天上午'),
    AgentEvent.text('高等数学，'),
    AgentEvent.text('B201 教室。'),
    AgentEvent.message(text: '明天上午高等数学，B201 教室。'),
    AgentEvent.usage(TokenUsage(promptTokens: 120, completionTokens: 15, totalTokens: 135)),
    AgentEvent.turnDone(),
  ];

  /// 场景 [4]：跨模块双工具——课表 + 番茄钟。
  ///
  /// Core 集成测试 §六 场景 4。
  static List<AgentEvent> scenario4() => [
    AgentEvent.turnStarted(),
    AgentEvent.toolDispatch(ToolEventPayload(
      id: 'call_sched',
      name: 'check_schedule',
      arguments: '{}',
      readOnly: true,
    )),
    AgentEvent.toolDispatch(ToolEventPayload(
      id: 'call_pomo',
      name: 'get_pomodoro',
      arguments: '{}',
      readOnly: true,
    )),
    AgentEvent.toolResult(ToolEventPayload(
      id: 'call_sched',
      name: 'check_schedule',
      arguments: '{}',
      output: '高等数学 B201 教室\n线性代数 C305 教室',
    )),
    AgentEvent.toolResult(ToolEventPayload(
      id: 'call_pomo',
      name: 'get_pomodoro',
      arguments: '{}',
      output: '共 6 个番茄钟：已完成 3 个，剩余 3 个\n当前专注时长：75 分钟',
    )),
    AgentEvent.text('根据课表和番茄钟记录，'),
    AgentEvent.text('明天上午高等数学在 B201，'),
    AgentEvent.text('番茄钟已记录 3/6 完成，建议继续完成剩余 3 个。'),
    AgentEvent.message(text: '根据课表和番茄钟记录，明天上午高等数学在 B201，番茄钟已记录 3/6 完成，建议继续完成剩余 3 个。'),
    AgentEvent.usage(TokenUsage(promptTokens: 250, completionTokens: 35, totalTokens: 285)),
    AgentEvent.turnDone(),
  ];
}

// ═══════ 工具函数 ═══════

void _json(HttpResponse resp, int code, Map<String, dynamic> data) {
  resp.statusCode = code;
  resp.headers.set('Content-Type', 'application/json; charset=utf-8');
  resp.write(jsonEncode(data));
  resp.close();
}

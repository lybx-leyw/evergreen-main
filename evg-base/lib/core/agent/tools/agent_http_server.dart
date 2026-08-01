/// Agent HTTP Server — 将 Controller 能力暴露为内部 HTTP API。
///
/// 模块后端 .exe 通过本端点桥接到 core/agent，无需重实现 LLM 逻辑。
/// 启动时写入端口到 `.agent_port` 文件，供外部 .exe 发现。
///
/// ## 24 端点一览
/// | # | 方法 | 路径 | 说明 |
/// |---|------|------|------|
/// | 1 | GET | `/health` | 健康检查 |
/// | 2 | POST | `/agent/chat/stream` | 流式对话 (SSE) |
/// | 3 | POST | `/agent/chat` | 非流式对话 |
/// | 4 | GET | `/agent/sessions` | 列出会话 |
/// | 5 | POST | `/agent/sessions` | 创建会话 |
/// | 6 | GET | `/agent/sessions/:id` | 获取单个会话 |
/// | 7 | PUT | `/agent/sessions/:id` | 更新/重命名会话 |
/// | 8 | POST | `/agent/sessions/:id/messages` | 追加消息 |
/// | 9 | GET | `/agent/sessions/:id/messages` | 获取消息历史 |
/// | 10 | POST | `/agent/sessions/switch` | 切换会话 |
/// | 11 | DELETE | `/agent/sessions/:id` | 删除会话 |
/// | 12 | GET | `/agent/tools` | 列出工具 |
/// | 13 | POST | `/agent/tools/toggle` | 启用/禁用工具 |
/// | 14 | POST | `/agent/cancel` | 取消当前运行 |
/// | 15 | POST | `/agent/approve` | 批准工具调用 |
/// | 16 | POST | `/agent/reject` | 拒绝工具调用 |
/// | 17 | GET | `/agent/styles` | 列出输出风格 |
/// | 18 | POST | `/agent/styles` | 设置输出风格 |
/// | 19 | GET | `/agent/config` | 获取配置 |
/// | 20 | GET | `/agent/memory` | 列出记忆 |
/// | 21 | POST | `/agent/memory` | 保存记忆 |
/// | 22 | DELETE | `/agent/memory/:name` | 删除记忆 |
/// | 23 | GET | `/agent/skills` | 列出技能 |
/// | 24 | POST | `/agent/skills/toggle` | 激活/停用技能 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/agent/agent/agent.dart';
import 'package:evergreen_base/core/agent/agent/compose.dart';
import 'package:evergreen_base/core/agent/agent/session.dart';
import 'package:evergreen_base/core/agent/controller/controller.dart';
import 'package:evergreen_base/core/agent/event.dart';
import 'package:evergreen_base/core/agent/memory/memory.dart' as mem;
import 'package:evergreen_base/core/agent/memory/store_interface.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/message.dart';
import 'package:evergreen_base/core/agent/output_style/style.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'event_serializers.dart';

// ═══════ AgentHttpServer ═══════

/// 将 Controller + Session + Registry 暴露为 HTTP API。
///
/// 启动后在 127.0.0.1 随机端口监听，端口号写入 [portFile]。
class AgentHttpServer {
  final Controller _controller;
  final StreamEventSink _eventSink;
  final Session _session;
  final Registry _registry;
  final String? _portFile;

  HttpServer? _server;
  final List<Session> _savedSessions = [];
  String? _activeSessionId;

  /// 可选的 FileMemoryStore——供 /agent/memory 端点使用。
  FileMemoryStore? _memoryStore;

  /// 可选的 SkillIndex——供 /agent/skills 端点使用。
  SkillIndex? _skillIndex;

  AgentHttpServer({
    required Controller controller,
    required StreamEventSink eventSink,
    required Session session,
    required Registry registry,
    String? portFile,
    FileMemoryStore? memoryStore,
    SkillIndex? skillIndex,
  })  : _controller = controller,
        _eventSink = eventSink,
        _session = session,
        _registry = registry,
        _portFile = portFile,
        _memoryStore = memoryStore,
        _skillIndex = skillIndex;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// 启动服务器，返回监听端口。
  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final p = _server!.port;

    if (_portFile != null) {
      File(_portFile!).writeAsStringSync('$p');
      stderr.writeln('[AgentHttp] 端口 $p → $_portFile');
    }

    stderr.writeln('[AgentHttp] http://127.0.0.1:$p');
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
    req.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    final path = req.uri.path;

    try {
      // ── 1-3: health / chat ──
      if (path == '/health')                  return await _health(req);
      if (path == '/agent/chat/stream')       return await _chatStream(req);
      if (path == '/agent/chat')              return await _chat(req);

      // ── 4-11: sessions ──
      if (path == '/agent/sessions')          return req.method == 'GET' ? await _listSessions(req) : await _createSession(req);
      if (path == '/agent/sessions/switch')   return await _switchSession(req);
      if (path.startsWith('/agent/sessions/')) {
        final segments = path.split('/');
        // /agent/sessions/:id/messages
        if (segments.length == 5 && segments[4] == 'messages') {
          return req.method == 'GET' ? await _getSessionMessages(req, segments[3]) : await _appendMessage(req, segments[3]);
        }
        // /agent/sessions/:id
        if (segments.length == 4) {
          return req.method == 'GET' ? await _getSession(req, segments[3])
               : req.method == 'PUT' ? await _updateSession(req, segments[3])
               : await _deleteSession(req);
        }
      }

      // ── 12-13: tools ──
      if (path == '/agent/tools')             return await _listTools(req);
      if (path == '/agent/tools/toggle')      return await _toggleTool(req);

      // ── 14-16: control ──
      if (path == '/agent/cancel')            return await _cancel(req);
      if (path == '/agent/approve')           return await _approve(req);
      if (path == '/agent/reject')            return await _reject(req);

      // ── 17-18: styles ──
      if (path == '/agent/styles')            return req.method == 'GET' ? await _listStyles(req) : await _setStyle(req);

      // ── 19: config ──
      if (path == '/agent/config')            return await _getConfig(req);

      // ── 20-22: memory ──
      if (path == '/agent/memory')            return req.method == 'GET' ? await _listMemory(req) : await _saveMemory(req);
      if (path.startsWith('/agent/memory/'))  return await _deleteMemory(req, path.split('/').last);

      // ── 23-24: skills ──
      if (path == '/agent/skills')            return await _listSkills(req);
      if (path == '/agent/skills/toggle')     return await _toggleSkill(req);

      _json(req.response, 404, {'error': 'not found'});
    } catch (e, st) {
      stderr.writeln('[AgentHttp] ❌ $path: $e\n$st');
      try {
        _json(req.response, 500, {'error': '$e'});
      } catch (_) {
        // response already sent or closed
      }
    }
  }

  // ── 端点 ──

  Future<void> _health(HttpRequest req) async {
    _json(req.response, 200, {
      'status': 'ok',
      'tools': _registry.enabled().length,
      'sessions': _savedSessions.length,
      'provider': _controller.provider.name,
    });
  }

  Future<void> _chatStream(HttpRequest req) async {
    final body = await _readBody(req);
    final input = body['input'] as String?;
    if (input == null || input.trim().isEmpty) {
      _json(req.response, 400, {'error': 'input 不能为空'});
      return;
    }

    // 可选：运行时切换风格
    if (body['style'] is String) {
      final sm = StyleManager();
      sm.setByName(body['style'] as String);
      if (sm.current != null) {
        _controller.setSystemPrompt(sm.applyTo(defaultSystemPrompt));
      }
    }

    // SSE 响应头
    req.response.statusCode = 200;
    req.response.headers.set('Content-Type', 'text/event-stream');
    req.response.headers.set('Cache-Control', 'no-cache');
    req.response.headers.set('Connection', 'keep-alive');

    final completer = Completer<void>();
    StreamSubscription<AgentEvent>? sub;

    sub = _eventSink.stream.listen(
      (event) {
        try {
          final frame = eventToSseFrame(event);
          req.response.write('data: $frame\n\n');
          if (event.kind == EventKind.turnDone) {
            if (!completer.isCompleted) completer.complete();
          }
        } catch (_) {
          // response closed by client
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: false,
    );

    _controller.send(input.trim());

    try {
      await completer.future.timeout(const Duration(minutes: 10));
    } on TimeoutException {
      final err = jsonEncode({'type': 'error', 'text': '请求超时'});
      req.response.write('data: $err\n\n');
    } catch (_) {
      // 客户端断开
    } finally {
      await sub.cancel();
      await req.response.close();
    }
  }

  Future<void> _chat(HttpRequest req) async {
    final body = await _readBody(req);
    final input = body['input'] as String?;
    if (input == null || input.trim().isEmpty) {
      _json(req.response, 400, {'error': 'input 不能为空'});
      return;
    }

    final events = <Map<String, dynamic>>[];
    StreamSubscription<AgentEvent>? sub;
    final completer = Completer<void>();

    sub = _eventSink.stream.listen(
      (event) {
        if (event.kind == EventKind.turnDone) {
          if (!completer.isCompleted) completer.complete();
        } else {
          events.add(eventToJsonMap(event));
        }
      },
    );

    _controller.send(input.trim());

    try {
      await completer.future.timeout(const Duration(minutes: 5));
    } catch (_) {}

    await sub.cancel();
    _json(req.response, 200, {'events': events});
  }

  Future<void> _listSessions(HttpRequest req) async {
    _json(req.response, 200, {
      'sessions': _savedSessions.map((s) => _sessionToMap(s)).toList(),
    });
  }

  Future<void> _createSession(HttpRequest req) async {
    final body = await _readBody(req);
    final title = body['title'] as String? ?? '新对话';

    if (_activeSessionId != null) _saveCurrent();

    final session = Session(title: title);
    _activeSessionId = session.id;
    _savedSessions.add(session);
    _controller.setSession(session);
    _eventSink.emit(AgentEvent.notice('已创建新会话: $title'));

    _json(req.response, 201, _sessionToMap(session));
  }

  Future<void> _switchSession(HttpRequest req) async {
    final body = await _readBody(req);
    final id = body['id'] as String?;
    if (id == null) { _json(req.response, 400, {'error': '缺少 id'}); return; }

    _saveCurrent();
    final session = _savedSessions.where((s) => s.id == id).firstOrNull;
    if (session == null) { _json(req.response, 404, {'error': '会话不存在'}); return; }

    _activeSessionId = id;
    _controller.setSession(session);
    _json(req.response, 200, _sessionToMap(session));
  }

  Future<void> _deleteSession(HttpRequest req) async {
    final id = req.uri.path.split('/').last;
    _savedSessions.removeWhere((s) => s.id == id);
    if (_activeSessionId == id) {
      _activeSessionId = null;
      _controller.newSession();
    }
    _json(req.response, 200, {'deleted': id});
  }

  Future<void> _listTools(HttpRequest req) async {
    _json(req.response, 200, {
      'tools': _registry.enabled().map((t) => {
        'name': t.name,
        'description': t.description,
        'readOnly': t.readOnly,
      }).toList(),
    });
  }

  Future<void> _toggleTool(HttpRequest req) async {
    final body = await _readBody(req);
    final name = body['name'] as String?;
    final enable = body['enable'] as bool? ?? true;
    if (name == null) { _json(req.response, 400, {'error': '缺少 name'}); return; }
    if (enable) { _registry.enable(name); } else { _registry.disable(name); }
    _json(req.response, 200, {'name': name, 'enabled': enable});
  }

  Future<void> _cancel(HttpRequest req) async {
    _controller.cancel();
    _json(req.response, 200, {'cancelled': true});
  }

  Future<void> _approve(HttpRequest req) async {
    _controller.approve();
    _json(req.response, 200, {'approved': true});
  }

  Future<void> _reject(HttpRequest req) async {
    _controller.reject();
    _json(req.response, 200, {'rejected': true});
  }

  Future<void> _listStyles(HttpRequest req) async {
    _json(req.response, 200, {
      'styles': const [
        {'name': 'explanatory', 'label': '解释型'},
        {'name': 'learning', 'label': '学习型'},
        {'name': 'concise', 'label': '简洁型'},
        {'name': 'socratic', 'label': '苏格拉底式'},
      ],
    });
  }

  Future<void> _setStyle(HttpRequest req) async {
    final body = await _readBody(req);
    final name = body['style'] as String?;
    if (name == null) { _json(req.response, 400, {'error': '缺少 style'}); return; }

    final sm = StyleManager();
    final ok = sm.setByName(name);
    if (ok && sm.current != null) {
      _controller.setSystemPrompt(sm.applyTo(defaultSystemPrompt));
    }
    _json(req.response, 200, {'style': name, 'applied': ok});
  }

  Future<void> _getConfig(HttpRequest req) async {
    _json(req.response, 200, {
      'provider': _controller.provider.name,
      'toolsCount': _registry.enabled().length,
    });
  }

  // ── 6: GET /agent/sessions/:id — 获取单个会话详情 ──

  Future<void> _getSession(HttpRequest req, String id) async {
    final session = _savedSessions.where((s) => s.id == id).firstOrNull;
    if (session == null) {
      _json(req.response, 404, {'error': '会话不存在'});
      return;
    }
    _json(req.response, 200, {
      'id': session.id,
      'title': session.title,
      'messageCount': session.messages.length,
      'totalTokens': session.totalTokens,
      'createdAt': session.createdAt.toIso8601String(),
      'updatedAt': session.updatedAt.toIso8601String(),
    });
  }

  // ── 7: PUT /agent/sessions/:id — 更新/重命名会话 ──

  Future<void> _updateSession(HttpRequest req, String id) async {
    final body = await _readBody(req);
    final session = _savedSessions.where((s) => s.id == id).firstOrNull;
    if (session == null) {
      _json(req.response, 404, {'error': '会话不存在'});
      return;
    }
    if (body['title'] is String) session.title = body['title'] as String;
    _json(req.response, 200, _sessionToMap(session));
  }

  // ── 8: POST /agent/sessions/:id/messages — 追加消息 ──

  Future<void> _appendMessage(HttpRequest req, String id) async {
    final body = await _readBody(req);
    final role = body['role'] as String?;
    final content = body['content'] as String?;
    if (role == null || content == null) {
      _json(req.response, 400, {'error': '缺少 role 或 content'});
      return;
    }

    final session = _savedSessions.where((s) => s.id == id).firstOrNull;
    if (session == null) {
      _json(req.response, 404, {'error': '会话不存在'});
      return;
    }

    final msgRole = Role.values.firstWhere(
      (r) => r.value == role,
      orElse: () => Role.user,
    );
    session.add(Message(role: msgRole, content: content));
    _json(req.response, 200, _sessionToMap(session));
  }

  // ── 9: GET /agent/sessions/:id/messages — 获取消息历史 ──

  Future<void> _getSessionMessages(HttpRequest req, String id) async {
    final session = _savedSessions.where((s) => s.id == id).firstOrNull;
    if (session == null) {
      _json(req.response, 404, {'error': '会话不存在'});
      return;
    }
    final messages = session.messages.map((m) => {
      'role': m.role.value,
      'content': m.content,
      'toolCalls': m.hasToolCalls ? m.toolCalls.map((t) => t.name).toList() : null,
    }).toList();
    _json(req.response, 200, {'messages': messages, 'count': messages.length});
  }

  // ── 20: GET /agent/memory — 列出记忆 ──

  Future<void> _listMemory(HttpRequest req) async {
    final sw = Stopwatch()..start();
    if (_memoryStore == null) {
      stderr.writeln('[AgentHttp] GET /agent/memory → 200 (${sw.elapsedMilliseconds}ms) [no store]');
      _json(req.response, 200, {'memories': [], 'note': 'memoryStore 未配置'});
      return;
    }
    final all = await _memoryStore!.all();
    _json(req.response, 200, {
      'memories': all.map((m) => {
        'name': m.name,
        'title': m.title,
        'description': m.description,
        'type': m.type.value,
        'priority': m.priority,
      }).toList(),
    });
    stderr.writeln('[AgentHttp] GET /agent/memory → 200 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 21: POST /agent/memory — 保存记忆 ──

  Future<void> _saveMemory(HttpRequest req) async {
    final sw = Stopwatch()..start();
    if (_memoryStore == null) {
      stderr.writeln('[AgentHttp] POST /agent/memory → 400 (${sw.elapsedMilliseconds}ms) [no store]');
      _json(req.response, 400, {'error': 'memoryStore 未配置'});
      return;
    }
    final body = await _readBody(req);
    final name = body['name'] as String?;
    if (name == null || name.isEmpty) {
      stderr.writeln('[AgentHttp] POST /agent/memory → 400 (${sw.elapsedMilliseconds}ms) [missing name]');
      _json(req.response, 400, {'error': '缺少 name'});
      return;
    }
    final memory = mem.Memory(
      name: name,
      description: body['description'] as String? ?? '',
      body: body['body'] as String? ?? '',
      type: mem.MemoryType.fromString(body['type'] as String? ?? 'project'),
      priority: body['priority'] as String? ?? 'medium',
    );
    await _memoryStore!.save(memory);
    _json(req.response, 201, {'saved': name});
    stderr.writeln('[AgentHttp] POST /agent/memory → 201 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 22: DELETE /agent/memory/:name — 删除记忆 ──

  Future<void> _deleteMemory(HttpRequest req, String name) async {
    final sw = Stopwatch()..start();
    if (_memoryStore == null) {
      stderr.writeln('[AgentHttp] DELETE /agent/memory/$name → 400 (${sw.elapsedMilliseconds}ms) [no store]');
      _json(req.response, 400, {'error': 'memoryStore 未配置'});
      return;
    }
    await _memoryStore!.delete(name);
    _json(req.response, 200, {'deleted': name});
    stderr.writeln('[AgentHttp] DELETE /agent/memory/$name → 200 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 23: GET /agent/skills — 列出技能 ──

  Future<void> _listSkills(HttpRequest req) async {
    final sw = Stopwatch()..start();
    if (_skillIndex == null) {
      stderr.writeln('[AgentHttp] GET /agent/skills → 200 (${sw.elapsedMilliseconds}ms) [no index]');
      _json(req.response, 200, {'skills': [], 'note': 'skillIndex 未配置'});
      return;
    }
    final skills = _skillIndex!.all().map((s) => {
      'name': s.name,
      'description': s.description,
      'scope': s.scope.name,
      'runAs': s.runAs.name,
      'active': _controller.activeSkillIds.contains(s.name),
    }).toList();
    _json(req.response, 200, {'skills': skills, 'activeIds': _controller.activeSkillIds});
    stderr.writeln('[AgentHttp] GET /agent/skills → 200 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 24: POST /agent/skills/toggle — 激活/停用技能 ──

  Future<void> _toggleSkill(HttpRequest req) async {
    final sw = Stopwatch()..start();
    if (_skillIndex == null) {
      stderr.writeln('[AgentHttp] POST /agent/skills/toggle → 400 (${sw.elapsedMilliseconds}ms) [no index]');
      _json(req.response, 400, {'error': 'skillIndex 未配置'});
      return;
    }
    final body = await _readBody(req);
    final name = body['name'] as String?;
    final activate = body['activate'] as bool? ?? true;
    if (name == null || name.isEmpty) {
      stderr.writeln('[AgentHttp] POST /agent/skills/toggle → 400 (${sw.elapsedMilliseconds}ms) [missing name]');
      _json(req.response, 400, {'error': '缺少 name'});
      return;
    }
    final ok = activate ? _controller.activateSkill(name) : _controller.deactivateSkill(name);
    _json(req.response, 200, {'name': name, 'activated': activate, 'success': ok});
    stderr.writeln('[AgentHttp] POST /agent/skills/toggle → 200 (${sw.elapsedMilliseconds}ms)');
  }

  // ── 辅助 ──

  void _saveCurrent() {
    if (_activeSessionId == null) return;
    if (_session.title.isEmpty || _session.title == '新对话') {
      final u = _session.messages.where((m) => m.role == Role.user).firstOrNull;
      if (u != null && u.content.isNotEmpty) {
        final t = u.content.replaceAll('\n', ' ').trim();
        _session.title = t.length > 30 ? '${t.substring(0, 30)}...' : t;
      }
    }
    final copy = Session.fromJson(_session.toJson());
    copy.id = _activeSessionId!;
    final idx = _savedSessions.indexWhere((s) => s.id == _activeSessionId);
    if (idx >= 0) _savedSessions[idx] = copy;
  }

  // _eventToSse / _eventToMap → 已提取至 tools/event_serializers.dart（与 ScriptedAgentHttpServer 共享）

  Map<String, dynamic> _sessionToMap(Session s) => {
    'id': s.id, 'title': s.title,
    'messageCount': s.messages.length,
    'createdAt': s.createdAt.toIso8601String(),
  };
}

// ═══════ 工具函数 ═══════

Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
  final raw = await utf8.decodeStream(req);
  if (raw.isEmpty) return {};
  try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return {}; }
}

void _json(HttpResponse resp, int code, Map<String, dynamic> data) {
  resp.statusCode = code;
  resp.headers.set('Content-Type', 'application/json; charset=utf-8');
  resp.write(jsonEncode(data));
  resp.close();
}

/// Theme HTTP Server — 将主题能力暴露为内部 HTTP API。
///
/// 插件 .exe 通过本端点列出/查询/切换主题，无需直接访问 ThemeStore。
///
/// ## 7 端点一览
/// | # | 方法 | 路径 | 说明 |
/// |---|------|------|------|
/// | 1 | GET  | `/theme/health`                             | 健康检查 |
/// | 2 | GET  | `/theme/themes`                             | 列出所有已注册主题 |
/// | 3 | GET  | `/theme/themes/:id`                         | 获取单个主题详情 |
/// | 4 | GET  | `/theme/active`                             | 获取当前活跃主题 |
/// | 5 | POST | `/theme/active`                             | 切换活跃主题 |
/// | 6 | GET  | `/theme/token?layer=&component=&token=`     | 查询五层 token 颜色值 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'theme_store.dart';

// ═══════ ThemeHttpServer ═══════

/// 主题层 HTTP 服务器。供插件 .exe 通过 HTTP 查询/切换主题。
class ThemeHttpServer {
  final ThemeStore _store;
  final int _requestedPort;

  HttpServer? _server;
  bool _running = false;

  ThemeHttpServer(this._store, {int port = 0}) : _requestedPort = port;

  /// 是否正在监听。
  bool get isRunning => _running;

  /// 实际端口号（未启动时返回 0）。
  int get port => _server?.port ?? 0;

  /// 启动监听。返回实际绑定的端口号。
  Future<int> start() async {
    if (_running) return _server!.port;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _requestedPort,
    );
    _running = true;

    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// 关闭服务器。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _server?.close(force: true);
    _server = null;
  }

  // ═══════ 路由 ═══════

  static final _paramPattern = RegExp(r'^:(\w+)$');

  Future<void> _handleRequest(HttpRequest request) async {
    final sw = Stopwatch()..start();
    try {
      if (request.method == 'OPTIONS') {
        _respond(request, 204, {}, sw);
        return;
      }
      await _dispatch(request, sw);
    } catch (e) {
      _respond(request, 500, {'error': '内部错误: $e'}, sw);
    }
  }

  Future<void> _dispatch(HttpRequest request, Stopwatch sw) async {
    final method = request.method;
    final path = request.uri.path;
    final segments = path.split('/')..removeAt(0);

    final exactKey = '$method $path';
    final exact = _routes[exactKey];
    if (exact != null) {
      await exact(request, {}, sw);
      return;
    }

    for (final entry in _paramRoutes.entries) {
      final parts = entry.key.split(' ');
      if (parts[0] != method) continue;
      final patternSegments = parts[1].split('/')..removeAt(0);
      if (patternSegments.length != segments.length) continue;

      final params = <String, String>{};
      var match = true;
      for (var i = 0; i < patternSegments.length; i++) {
        final pm = _paramPattern.firstMatch(patternSegments[i]);
        if (pm != null) {
          params[pm.group(1)!] = segments[i];
        } else if (patternSegments[i] != segments[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        await entry.value(request, params, sw);
        return;
      }
    }

    _respond(request, 404, {
      'error': '未找到: $method $path',
    }, sw);
  }

  // ── 路由表 ──

  late final Map<String,
      Future<void> Function(HttpRequest, Map<String, String>, Stopwatch)>
      _routes = {
    // 1: health
    'GET /theme/health': (req, _, sw) async {
      _respond(req, 200, {
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'themeCount': _store.all.length,
      }, sw);
    },

    // 2: list all themes
    'GET /theme/themes': (req, _, sw) async {
      _respond(req, 200, {
        'themes': _store.all.map((t) => {
          'id': t.id,
          'name': t.name,
          'colors': t.colors,
        }).toList(),
      }, sw);
    },

    // 4: get active theme
    'GET /theme/active': (req, _, sw) async {
      final active = _store.activeTheme;
      if (active == null) {
        _respond(req, 404, {'error': '未设置活跃主题'}, sw);
        return;
      }
      _respond(req, 200, active.toJson(), sw);
    },

    // 5: set active theme
    'POST /theme/active': (req, _, sw) async {
      final body = await _readBody(req);
      final id = body['id'] as String?;
      if (id == null || id.isEmpty) {
        _respond(req, 400, {'error': '缺少 id'}, sw);
        return;
      }
      final success = _store.setActiveById(id);
      if (!success) {
        _respond(req, 404, {'error': '主题不存在: $id'}, sw);
        return;
      }
      _respond(req, 200, {
        'active': id,
        'name': _store.activeTheme?.name,
      }, sw);
    },

    // 6: query semantic color (扁平色板)
    'GET /theme/token': (req, _, sw) async {
      final key = req.uri.queryParameters['key'];

      if (key == null || key.isEmpty) {
        _respond(req, 400, {'error': '缺少 key 参数（语义色字段名）'}, sw);
        return;
      }

      final theme = _store.activeTheme ?? _store.activeOrFirst;
      if (theme == null) {
        _respond(req, 404, {'error': '无已注册主题'}, sw);
        return;
      }

      final colorHex = theme.color(key);
      if (colorHex == null) {
        _respond(req, 404, {
          'error': '颜色未找到',
          'key': key,
          'themeId': theme.id,
        }, sw);
        return;
      }

      _respond(req, 200, {
        'color': colorHex,
        'key': key,
        'themeId': theme.id,
      }, sw);
    },
  };

  late final Map<String,
      Future<void> Function(HttpRequest, Map<String, String>, Stopwatch)>
      _paramRoutes = {
    // 3: get theme by id
    'GET /theme/themes/:id': (req, p, sw) async {
      final id = p['id']!;
      final theme = _store.findById(id);
      if (theme == null) {
        _respond(req, 404, {'error': '主题不存在: $id'}, sw);
        return;
      }
      _respond(req, 200, theme.toJson(), sw);
    },
  };

  // ═══════ 辅助 ═══════

  void _respond(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
    Stopwatch sw,
  ) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );
    request.response.write(jsonEncode(body));
    request.response.close();
    stderr.writeln(
      '[ThemeHttp] ${request.method} ${request.uri.path} '
      '→ $status (${sw.elapsedMilliseconds}ms)',
    );
  }
}

/// 读取请求体 JSON。
Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
  final raw = await utf8.decodeStream(req);
  if (raw.isEmpty) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

/// 模块 HTTP 服务器——暴露模块查询的 HTTP 端点。
///
/// 将 [ModuleRegistry] 的能力以 REST API 形式对外暴露，供外部客户端
/// （如前端市场页、CLI 工具）查询模块信息。
///
/// # 端点
///
/// ```
/// GET  /module/health              → 200 { "status": "ok" }
/// GET  /module/modules             → 列出所有注册模块（摘要）
/// GET  /module/modules/:id         → 获取单模块详情
/// GET  /module/search?q=&dim=&cat= → 搜索/筛选
/// GET  /module/nav                 → 获取导航结构
/// GET  /module/routes              → 获取全部路由
/// ```
///
/// # 使用
///
/// ```dart
/// final server = ModuleHttpServer(registry, port: 9100);
/// await server.start();
/// // ... 使用 ...
/// await server.stop();
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'package:evergreen_base/core/log.dart';
import 'capability.dart';
import 'module_descriptor.dart';
import 'module_registry.dart';

/// 模块 HTTP 服务器——将 [ModuleRegistry] 暴露为 REST API。
///
/// 与其他 5 个 HttpServer 保持一致：[start] 返回 [Future<int>]（实际监听端口），
/// 支持 `port: 0` 自动分配端口，启动后写入 `.module_port` 文件供外部发现。
class ModuleHttpServer {
  final ModuleRegistry _registry;
  int _port;
  HttpServer? _server;
  File? _portFile;

  ModuleHttpServer(this._registry, {int port = 9100}) : _port = port;

  /// 服务器是否正在运行。
  bool get isRunning => _server != null;

  /// 监听端口（启动前返回传入值，启动后返回实际绑定端口）。
  int get port => _port;

  /// 启动 HTTP 服务器（非阻塞——绑定后立即返回）。
  ///
  /// 返回实际监听端口。`port: 0` 时由操作系统分配可用端口。
  /// 启动成功后写入 `.module_port` 文件，供外部进程发现端口。
  Future<int> start() async {
    if (_server != null) return _port;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _port = _server!.port; // 读取实际绑定端口（port:0 时关键）
    _server!.listen(_handle);
    // 写入 port 文件供外部发现
    _writePortFile();
    Log().info('ModuleHttpServer: 已启动', data: {'port': _port});
    return _port;
  }

  /// 停止 HTTP 服务器并清理 port 文件。
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cleanPortFile();
    Log().info('ModuleHttpServer: 已停止');
  }

  /// 写入 `.module_port` 文件。
  void _writePortFile() {
    try {
      _portFile = File('.module_port');
      _portFile!.writeAsStringSync('$_port');
    } catch (e) {
      Log().warn('ModuleHttpServer: 写入 .module_port 失败', error: e);
    }
  }

  /// 清理 `.module_port` 文件。
  void _cleanPortFile() {
    try {
      _portFile?.deleteSync();
    } catch (_) {}
    _portFile = null;
  }

  // ═══════ 路由分发 ═══════

  void _handle(HttpRequest req) {
    final sw = Stopwatch()..start();
    try {
      final path = req.uri.path;
      final method = req.method;

      if (method != 'GET') {
        _json(req, 405, {'error': '仅支持 GET'});
        return;
      }

      if (path == '/module/health') {
        _json(req, 200, {'status': 'ok'});
        stderr.writeln('[ModuleHttp] GET /module/health → 200 (${sw.elapsedMilliseconds}ms)');
      } else if (path == '/module/modules') {
        _listModules(req);
      } else if (path.startsWith('/module/modules/')) {
        final id = path.split('/').last;
        final found = _registry.findById(id) != null;
        _moduleDetail(req, id);
        final status = found ? 200 : 404;
        stderr.writeln('[ModuleHttp] GET /module/modules/$id → $status (${sw.elapsedMilliseconds}ms)');
      } else if (path == '/module/search') {
        _search(req);
      } else if (path == '/module/nav') {
        _nav(req);
      } else if (path == '/module/routes') {
        _routes(req);
        stderr.writeln('[ModuleHttp] GET /module/routes → 200 (${sw.elapsedMilliseconds}ms)');
      } else {
        _json(req, 404, {'error': '未找到端点: $path'});
      }
    } catch (e, stack) {
      Log().error('ModuleHttpServer: 请求处理异常', error: e, stack: stack);
      try {
        _json(req, 500, {'error': '内部错误'});
      } catch (_) {}
    }
  }

  // ═══════ 端点实现 ═══════

  /// GET /module/modules — 列出所有注册模块（摘要）。
  void _listModules(HttpRequest req) {
    final modules = _registry.modules.map((m) => {
      'id': m.id,
      'name': m.name,
      'description': m.description,
      'icon': m.icon?.codePoint,
      'route': m.route,
      'ui': m.ui,
      'category': m.sidebar?.section ?? '',
    }).toList();
    _json(req, 200, {'modules': modules, 'count': modules.length});
  }

  /// GET /module/modules/:id — 获取单模块详情（完整 [ModuleDescriptor]）。
  void _moduleDetail(HttpRequest req, String id) {
    final m = _registry.findById(id);
    if (m == null) {
      _json(req, 404, {'error': '模块 "$id" 不存在'});
      return;
    }
    _json(req, 200, m.toJson());
  }

  /// GET /module/search?q=&dim=&cat= — 搜索/筛选。
  void _search(HttpRequest req) {
    final q = req.uri.queryParameters['q'] ?? '';
    final dimStr = req.uri.queryParameters['dim'];
    final cat = req.uri.queryParameters['cat'];

    List<CapabilityDimension>? dims;
    if (dimStr != null && dimStr.isNotEmpty) {
      final parsed = parseCapabilityDimension(dimStr);
      dims = parsed != null ? [parsed] : null;
    }

    final results = _registry.search(q, dims: dims, cat: cat);
    _json(req, 200, {
      'results': results.map((p) => p.toJson()).toList(),
      'count': results.length,
      'query': q,
    });
  }

  /// GET /module/nav — 获取导航结构。
  void _nav(HttpRequest req) {
    final groups = _registry.navGroups.map((g) {
      final (section, entries) = g;
      return {
        'section': section.label,
        'sectionOrder': section.order,
        'entries': entries.map((e) => {
          'label': e.label,
          'routePath': e.routePath,
          'icon': e.icon.codePoint,
        }).toList(),
      };
    }).toList();
    _json(req, 200, {'navGroups': groups});
  }

  /// GET /module/routes — 获取全部路由路径。
  void _routes(HttpRequest req) {
    final routes = _registry.buildRoutePaths();
    _json(req, 200, {'routes': routes, 'count': routes.length});
  }

  // ═══════ 工具 ═══════

  void _json(HttpRequest req, int status, Object data) {
    final body = utf8.encode(jsonEncode(data));
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..contentLength = body.length
      ..add(body);
    req.response.close();
  }
}

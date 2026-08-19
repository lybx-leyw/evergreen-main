/// ScraperBridgeServer——常驻 HTTP 服务，接收 DSH RPC，驱动真实 scraper WebView。
///
/// B 方案核心：DSH 常驻进程通过 HTTP RPC 驱动平台真实的 scraper WebView。
/// 本服务挂在 Evergreen 进程生命周期（常驻，不随插件切换销毁），通过
/// [ScraperBridgeRegistry] 拿到「当前活跃的 scraper 能力」执行。
///
/// 端点：
/// - `GET  /scraper/health`           → 健康 + 是否活跃
/// - `POST /scraper/navigate`         → 导航 {url}
/// - `POST /scraper/evaluate`         → 执行 JS {script} → 结果
/// - `GET  /scraper/current`          → 当前 URL
/// - `GET  /scraper/requests`         → 捕获的请求日志
/// - `POST /scraper/register`         → 注册数据源 {pluginDir}
///
/// 端口写入 `.scraper_bridge_port`（projectRoot），供 DSH 经 bridge 文件发现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import 'scraper_bridge_registry.dart';

/// ScraperBridgeServer——DSH RPC 的接收端。
class ScraperBridgeServer {
  final ScraperBridgeRegistry _registry;
  final DataOrchestrator? _orchestrator;

  /// 自动切换回调：RPC 到达但 scraper WebView 未挂载时，由 UI 层注入
  /// 「切到 scraper 插件」的逻辑（导航 + devHubIndexProvider）。返回后服务
  /// 会 [ScraperBridgeRegistry.waitReady] 等待 WebView 就绪。
  Future<void> Function()? activateScraper;

  HttpServer? _server;
  bool _running = false;
  int _port = 0;

  ScraperBridgeServer(this._registry, {DataOrchestrator? orchestrator})
      : _orchestrator = orchestrator;

  bool get isRunning => _running;
  int get port => _port;

  /// 启动监听（loopback，端口自动分配）。返回实际端口。
  Future<int> start() async {
    if (_running) return _port;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _running = true;
    _server!.listen(_handle);
    _writePortFile();
    Log().info('ScraperBridgeServer: 已启动 (port: $_port)');
    return _port;
  }

  /// 停止服务。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _server?.close(force: true);
    _server = null;
    Log().info('ScraperBridgeServer: 已关闭');
  }

  void _writePortFile() {
    try {
      final root = resolveProjectRoot() ?? Directory.current.path;
      File(p.join(root, '.scraper_bridge_port')).writeAsStringSync('$_port');
    } catch (e) {
      Log().warn('ScraperBridgeServer: 写端口文件失败', error: e);
    }
  }

  // ── 路由 ──

  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    resp.headers.set('Access-Control-Allow-Origin', '*');
    resp.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    resp.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method == 'OPTIONS') {
      resp.statusCode = 204;
      await resp.close();
      return;
    }

    final path = req.uri.path;
    try {
      switch (path) {
        case '/scraper/health':
          return _json(resp, 200, {
            'status': 'ok',
            'active': _registry.isActive,
          });
        case '/scraper/navigate':
          return await _navigate(req, resp);
        case '/scraper/evaluate':
          return await _evaluate(req, resp);
        case '/scraper/current':
          return await _current(resp);
        case '/scraper/requests':
          return await _requests(req, resp);
        case '/scraper/register':
          return await _register(req, resp);
        case '/scraper/tool':
          return await _tool(req, resp);
        default:
          return _json(resp, 404, {'error': '未找到端点: $path'});
      }
    } catch (e, st) {
      Log().error('ScraperBridgeServer: 处理 $path 异常', error: e, stack: st);
      try {
        _json(resp, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  // ── 端点 ──

  /// 确保 scraper 能力就绪：未激活且有 activateScraper 回调时，触发切换 + 等待。
  /// 返回是否就绪。
  Future<bool> _ensureActive() async {
    if (_registry.isActive) return true;
    final cb = activateScraper;
    if (cb == null) return false;
    try {
      await cb();
    } catch (e) {
      Log().warn('ScraperBridgeServer: activateScraper 回调失败', error: e);
      return false;
    }
    return _registry.waitReady();
  }

  Future<void> _navigate(HttpRequest req, HttpResponse resp) async {
    if (!await _ensureActive()) {
      return _json(resp, 409, {
        'error': 'scraper 未激活，请先打开 scraper 插件',
        'code': 'SCRAPER_INACTIVE',
      });
    }
    final bridge = _registry.activeBridge;
    final body = await _readJson(req);
    final url = (body?['url'] as String? ?? '').trim();
    if (url.isEmpty) return _json(resp, 400, {'error': '缺少 url 参数'});
    await bridge!.navigateTo!(url);
    return _json(resp, 200, {'ok': true, 'url': url});
  }

  Future<void> _evaluate(HttpRequest req, HttpResponse resp) async {
    if (!await _ensureActive()) {
      return _json(resp, 409, {
        'error': 'scraper 未激活，请先打开 scraper 插件',
        'code': 'SCRAPER_INACTIVE',
      });
    }
    final bridge = _registry.activeBridge;
    final body = await _readJson(req);
    final script = (body?['script'] as String? ?? '').trim();
    if (script.isEmpty) return _json(resp, 400, {'error': '缺少 script 参数'});
    final result = await bridge!.evaluateJavaScript!(script);
    return _json(resp, 200, {'result': result});
  }

  Future<void> _current(HttpResponse resp) async {
    if (!await _ensureActive()) {
      return _json(resp, 409, {
        'error': 'scraper 未激活',
        'code': 'SCRAPER_INACTIVE',
      });
    }
    final bridge = _registry.activeBridge;
    final url = await bridge!.currentUrl!();
    return _json(resp, 200, {'url': url});
  }

  Future<void> _requests(HttpRequest req, HttpResponse resp) async {
    if (!await _ensureActive()) {
      return _json(resp, 409, {
        'error': 'scraper 未激活',
        'code': 'SCRAPER_INACTIVE',
      });
    }
    final workflow = _registry.activeWorkflow;
    final logs = workflow!.logs.map((l) => l.toJson()).toList();
    return _json(resp, 200, {'logs': logs, 'count': logs.length});
  }

  Future<void> _register(HttpRequest req, HttpResponse resp) async {
    final orch = _orchestrator;
    if (orch == null) {
      return _json(resp, 503, {'error': 'DataOrchestrator 未注入'});
    }
    final body = await _readJson(req);
    final pluginDir = (body?['pluginDir'] as String? ?? '').trim();
    if (pluginDir.isEmpty) return _json(resp, 400, {'error': '缺少 pluginDir'});
    final projectRoot = resolveProjectRoot() ?? Directory.current.path;
    final registered = registerDataSourcesFromManifest(
      orch: orch,
      pluginDir: pluginDir,
      projectRoot: projectRoot,
    );
    if (registered.isEmpty) {
      return _json(resp, 404, {'error': '未注册任何数据源'});
    }
    return _json(resp, 200, {'registered': registered});
  }

  /// 通用工具转发：body `{name, args}` → 活跃官方工具 Registry.call()。
  ///
  /// 这是「转发给活跃 ScraperAIPanel」的核心——DSH 的工具 RPC 到这里，
  /// 转发到活跃 ScraperAIPanel 的 AgentAssembly.registry 执行官方工具
  /// （run_python_scraper / export_and_register_scraper / save_credential 等），
  /// 100% 复用官方逻辑（含 lint / Guardian / 真实数据验收）。
  Future<void> _tool(HttpRequest req, HttpResponse resp) async {
    if (!await _ensureActive()) {
      return _json(resp, 409, {
        'error': 'scraper 未激活，请先打开 scraper 插件',
        'code': 'SCRAPER_INACTIVE',
      });
    }
    final registry = _registry.toolRegistry;
    if (registry == null) {
      return _json(resp, 503, {
        'error': '官方工具 Registry 未就绪（ScraperAIPanel 尚未初始化 Agent）',
      });
    }
    final body = await _readJson(req);
    final name = (body?['name'] as String? ?? '').trim();
    if (name.isEmpty) return _json(resp, 400, {'error': '缺少 name 参数'});
    final args = body?['args'];
    final argsJson = args == null
        ? '{}'
        : (args is String ? args : jsonEncode(args));
    final result = await registry.call(name, argsJson);
    return _json(resp, 200, {'result': result});
  }

  // ── 工具 ──

  Future<Map<String, dynamic>?> _readJson(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  void _json(HttpResponse resp, int status, Map<String, dynamic> data) {
    resp.statusCode = status;
    resp.headers.contentType = ContentType.json;
    resp.write(jsonEncode(data));
    resp.close();
  }
}

/// Core HTTP Server — 将安装管理、OCR、更新检测能力暴露为内部 HTTP API。
///
/// 插件 .exe 通过本端点安装/卸载插件、执行 OCR、检查更新，无需直接访问文件系统。
/// 启动后端口写入 `.core_port` 文件，供外部 .exe 发现。
///
/// ## 8 端点一览
/// | # | 方法 | 路径 | 说明 |
/// |---|------|------|------|
/// | 1 | GET  | `/core/health`           | 健康检查 |
/// | 2 | POST | `/core/install`          | 安装插件 |
/// | 3 | POST | `/core/uninstall/:id`    | 卸载插件 |
/// | 4 | GET  | `/core/plugins`          | 列出已安装插件 |
/// | 5 | GET  | `/core/update/check/:id` | 检查单个插件更新 |
/// | 6 | GET  | `/core/update/check`     | 检查宿主更新 |
/// | 7 | POST | `/core/ocr`              | OCR 识别 |
/// | 8 | GET  | `/core/ocr/status`       | OCR 服务状态 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../log.dart';
import 'plugin_installer.dart';
import 'ocr_pipeline.dart';
import 'update_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CoreHttpServer
// ═══════════════════════════════════════════════════════════════════════════

/// Core 层 HTTP 服务器。供插件 .exe 通过 HTTP 调用安装、OCR、更新等平台能力。
class CoreHttpServer {
  final PluginInstaller _installer;
  final OcrPipeline _ocrPipeline;
  final UpdateService _updateService;
  final int _requestedPort;

  HttpServer? _server;
  bool _running = false;

  CoreHttpServer(
    this._installer,
    this._ocrPipeline,
    this._updateService, {
    int port = 0,
  }) : _requestedPort = port;

  /// 是否正在监听。
  bool get isRunning => _running;

  /// 实际端口号（未启动时返回 0）。
  int get port => _server?.port ?? 0;

  /// 启动监听。返回实际绑定的端口号。
  ///
  /// 端口发现文件由 main.dart 统一写入 _projectRoot，此处不再写入。
  Future<int> start() async {
    if (_running) return _server!.port;

    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _requestedPort,
    );
    _running = true;

    Log().info('CoreHttpServer: 启动 (port: ${_server!.port})');

    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// 关闭服务器。
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _server?.close(force: true);
    _server = null;
    Log().info('CoreHttpServer: 已关闭');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 路由
  // ═══════════════════════════════════════════════════════════════════════

  static final _paramPattern = RegExp(r'^:(\w+)$');

  Future<void> _handleRequest(HttpRequest request) async {
    final sw = Stopwatch()..start();
    final method = request.method;
    final path = request.uri.path;
    try {
      await _dispatch(request);
      Log().info('[CoreHttp] $method $path → ${request.response.statusCode} (${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      Log().error('[CoreHttp] $method $path ❌ $e (${sw.elapsedMilliseconds}ms)',
          error: e);
      _respond(request.response, 500, {'error': '内部错误: $e'});
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;
    final segments = path.split('/')..removeAt(0); // drop leading empty

    // 精确匹配
    final exactKey = '$method $path';
    final exact = _routes[exactKey];
    if (exact != null) {
      await exact(request, {});
      return;
    }

    // 参数匹配
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
        await entry.value(request, params);
        return;
      }
    }

    // 404
    _respond(request.response, 404, {
      'error': '未找到: $method $path',
    });
  }

  // ── 精确路由表 ──

  late final Map<
      String,
      Future<void> Function(HttpRequest, Map<String, String>)> _routes = {
    // 1: health
    'GET /core/health': (req, _) async {
      final plugins = _installer.listPlugins();
      _respond(req.response, 200, {
        'status': 'ok',
        'pluginsCount': plugins.length,
        'ocrAvailable': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
    },

    // 2: install
    'POST /core/install': (req, _) async {
      final body = await _readBody(req);
      final path = body['path'] as String?;
      final url = body['url'] as String?;
      final source = path ?? url;

      if (source == null || source.isEmpty) {
        _respond(req.response, 400, {'error': '缺少 path 或 url'});
        return;
      }

      final result = await _installer.install(source);
      result.fold(
        (installResult) => _respond(req.response,
            installResult.success ? 200 : 400, installResult.toJson()),
        (error) => _respond(
            req.response, 500, {'error': error.userMessage}),
      );
    },

    // 4: list plugins
    'GET /core/plugins': (req, _) async {
      final plugins = _installer.listPlugins();
      _respond(req.response, 200, {
        'plugins': plugins.map((p) => p.toJson()).toList(),
      });
    },

    // 6: check host update
    'GET /core/update/check': (req, _) async {
      final (hasUpdate, version, url) = await _updateService.checkForUpdate();
      _respond(req.response, 200, {
        'hasUpdate': hasUpdate,
        if (version != null) 'latestVersion': version,
        if (url != null) 'downloadUrl': url,
      });
    },

    // 7: OCR
    'POST /core/ocr': (req, _) async {
      final body = await _readBody(req);
      final path = body['path'] as String?;

      if (path == null || path.isEmpty) {
        _respond(req.response, 400, {'error': '缺少 path'});
        return;
      }

      final text = await _ocrPipeline.recognizeFile(path);
      _respond(req.response, 200, {'text': text});
    },

    // 8: OCR status
    'GET /core/ocr/status': (req, _) async {
      // DeepSeek 可用性由 API Key 是否配置决定
      final deepseekAvailable = true; // OcrPipeline 内部已有降级
      _respond(req.response, 200, {
        'deepseekAvailable': deepseekAvailable,
        'tesseractAvailable': true,
      });
    },
  };

  // ── 参数路由表 ──

  late final Map<
      String,
      Future<void> Function(HttpRequest, Map<String, String>)> _paramRoutes = {
    // 3: uninstall
    'POST /core/uninstall/:id': (req, p) async {
      final id = p['id']!;
      final result = await _installer.uninstall(id);
      result.fold(
        (_) => _respond(req.response, 200, {'uninstalled': id}),
        (error) =>
            _respond(req.response, 404, {'error': error.userMessage}),
      );
    },

    // 5: check plugin update
    'GET /core/update/check/:id': (req, p) async {
      final id = p['id']!;
      final result = await _installer.checkUpdate(id);
      _respond(req.response, 200, result.toJson());
    },
  };

  // ═══════════════════════════════════════════════════════════════════════
  // 辅助
  // ═══════════════════════════════════════════════════════════════════════

  void _respond(HttpResponse response, int status, Map<String, dynamic> body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.write(jsonEncode(body));
    response.close();
  }
}

/// 读取请求体 JSON。
Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
  final raw = await utf8.decodeStream(req);
  if (raw.isEmpty) return {};
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (e) {
    Log().warn('[CoreHttp] 请求体 JSON 解析失败，按空请求处理: $e', error: e);
    return {};
  }
}

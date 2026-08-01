/// 右侧预览面板 —— 设备画框 + 等比缩放 WebView。
///
/// 支持 Desktop / Mobile 两种预览模式切换，
/// 画框保持原始宽高比，WebView 内容通过 CSS zoom 等比填充。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/theme/render_tokens.dart';

/// 预览模式。
enum PreviewMode { desktop, mobile }

/// 设备画布尺寸定义。
class _DeviceCanvas {
  final double width;
  final double height;
  final String label;
  const _DeviceCanvas(this.width, this.height, this.label);
}

const _desktopCanvas = _DeviceCanvas(1440, 900, 'Desktop 1440×900');
const _mobileCanvas = _DeviceCanvas(375, 812, 'Mobile 375×812');

class PreviewPanel extends ConsumerStatefulWidget {
  final String htmlContent;
  final String? pluginId;
  final String? pluginsDir;

  const PreviewPanel({
    super.key,
    required this.htmlContent,
    this.pluginId,
    this.pluginsDir,
  });

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel> {
  final WebviewController _controller = WebviewController();
  /// Android：webview_flutter（webview_windows 仅支持 Windows）。
  /// ⚠️ 必须 late：WebViewController() 构造在 Windows 上无平台实现即断言，
  /// 字段级初始化会在桌面创建本组件时崩溃；惰性初始化保证仅安卓分支访问。
  late final WebViewController _androidController = WebViewController();
  HttpServer? _httpServer;
  int _httpPort = 0;
  bool _initialized = false;
  String? _initError;
  String _lastContent = '';
  bool _useHttpServer = false;

  PreviewMode _mode = PreviewMode.desktop;
  _DeviceCanvas get _canvas => _mode == PreviewMode.desktop ? _desktopCanvas : _mobileCanvas;

  @override
  void initState() {
    super.initState();
    _init();
    // 全局主题切换时实时推送新色板到预览（CSS 变量 + body 底色）。
    ref.listenManual(themeStoreProvider, (prev, next) {
      if (_initialized) _pushTheme();
    });
  }

  Future<void> _init() async {
    try {
      if (widget.pluginId != null && widget.pluginsDir != null) {
        await _startHttpServer();
      }
      if (Platform.isAndroid) {
        await _initAndroidWebView();
      } else {
        await _controller.initialize();
        if (!mounted) return;
        _listenMessages();
      }
      _lastContent = widget.htmlContent;
      await _loadContent();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[PreviewPanel] 初始化失败: $e');
      // 初始化失败：保持 _initialized=false 并在 build 中显示错误占位。
      // 若置为 true，didUpdateWidget→_refresh→_loadContent 会在未初始化时
      // 调用 WebView 方法触发断言崩溃（Android + webview_windows 曾必现）。
      _initError = e.toString();
      if (mounted) setState(() {});
    }
  }

  /// Android：webview_flutter 实现（bridge 经 evgBridge JS 通道）。
  Future<void> _initAndroidWebView() async {
    await _androidController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _androidController.addJavaScriptChannel(
      'evgBridge',
      onMessageReceived: (msg) => _handleBridgeMessage(msg.message),
    );
    // bridge 注入时机：导出模式由本地 HTTP 服务端在返回 HTML 时内联注入
    // （见 _startHttpServer，先于页面 body 脚本执行）；onPageStarted/onPageFinished
    // 仅作幂等兜底。
    await _androidController.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) {
        // 兜底注入（幂等）。
        _androidController.runJavaScript(_bridgeScript()).catchError((_) {});
      },
      onPageFinished: (_) {
        // 兜底注入（onPageStarted 可能早于通道就绪）。
        _androidController.runJavaScript(_bridgeScript()).catchError((_) {});
      },
    ));
  }

  Future<void> _startHttpServer() async {
    final pluginDir = '${widget.pluginsDir!}/${widget.pluginId!}';
    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _httpPort = _httpServer!.port;
    _httpServer!.listen((req) {
      final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
      final file = File('$pluginDir/module$path');
      file.exists().then((exists) {
        if (exists) {
          final ext = path.split('.').last;
          final mime = switch (ext) {
            'html' => 'text/html; charset=utf-8',
            'css'  => 'text/css', 'js' => 'application/javascript',
            'json' => 'application/json', 'png' => 'image/png',
            'jpg'  => 'image/jpeg', 'svg' => 'image/svg+xml',
            _      => 'text/plain',
          };
          req.response.headers.set('Content-Type', mime);
          req.response.headers.set('Access-Control-Allow-Origin', '*');
          file.readAsBytes().then((bytes) {
            if (mime.startsWith('text/html')) {
              // 服务端在文档最顶部内联注入 bridge：先于 <head> 内所有脚本执行，
              // 避免插件页面早期（甚至第一行）调用 platform.*/__evgResolve 时
              // bridge 未就绪（onPageStarted 的 runJavaScript 与 </head> 前注入
              // 都可能晚于页面内联脚本）。
              try {
                var html = utf8.decode(bytes);
                final bridge = '<script>$_bridgeScriptJs</script>';
                html = '$bridge\n$html';
                bytes = utf8.encode(html);
              } catch (_) {}
            }
            req.response.add(bytes); req.response.close();
          });
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found: $path');
          req.response.close();
        }
      });
    });
    _useHttpServer = true;
  }

  Future<void> _loadContent() async {
    if (Platform.isAndroid) {
      await _loadAndroidContent();
      return;
    }
    if (_useHttpServer && _httpPort > 0) {
      await _controller.loadUrl('http://localhost:$_httpPort/index.html');
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      final html = _buildFullHtml(widget.htmlContent);
      await _controller.loadStringContent(html);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _injectBridge();
    await _pushTheme();
    await _applyZoom();
  }

  /// Android：webview_flutter 加载（localhost 服务器或内联 HTML）。
  Future<void> _loadAndroidContent() async {
    if (_useHttpServer && _httpPort > 0) {
      await _androidController
          .loadRequest(Uri.parse('http://127.0.0.1:$_httpPort/index.html'));
      await Future.delayed(const Duration(milliseconds: 500));
    } else {
      final html = _buildFullHtml(widget.htmlContent);
      await _androidController.loadHtmlString(html);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _injectBridge();
    await _pushTheme();
    await _applyZoom();
  }

  /// 执行 JS（按平台分发）。
  Future<void> _executeJs(String script) {
    if (Platform.isAndroid) {
      return _androidController.runJavaScript(script).catchError((_) {});
    }
    return _controller.executeScript(script);
  }

  /// 推送当前全局主题色板到预览页：
  /// 设置 --evg-* CSS 变量（插件可用 var(--evg-accent) 等）+ body 底色。
  Future<void> _pushTheme() async {
    final colors = _themeColors();
    await _executeJs(
      'window.__evgApplyTheme(${jsonEncode(colors)});'
      'document.body.style.backgroundColor = "${colors['background']}";'
      'document.body.style.color = "${colors['text']}";',
    );
  }

  /// 当前全局主题色板（与 html_modle 的 platform.theme.getColors 同源）。
  Map<String, String> _themeColors() {
    final t = ref.read(themeStoreProvider).activeTheme;
    final c = RenderTokensColors.fromTheme(t);
    return {
      'background': c.bgPrimaryHex,
      'surface': c.bgSecondaryHex,
      'border': c.borderDefaultHex,
      'text': c.textPrimaryHex,
      'textSecondary': c.textSecondaryHex,
      'accent': c.accentBlueHex,
      'accentBg': c.accentBlueBgHex,
      'accentBorder': c.accentBlueBorderHex,
      'error': c.stateErrorHex,
      'others': c.othersHex,
    };
  }

  /// 设置 viewport 宽度 + CSS zoom 实现画框内等比缩放。
  Future<void> _applyZoom() async {
    await _executeJs(
      'document.querySelector(\'meta[name="viewport"]\')?.setAttribute("content", "width=${_canvas.width}");'
      'document.documentElement.style.zoom = "1";'
      'document.documentElement.style.transformOrigin = "top left";',
    );
  }

  String _buildFullHtml(String content) {
    final bridge = '<script>$_bridgeScriptJs</script>';

    if (content.contains('<meta name="viewport"')) {
      content = content.replaceAll(
        RegExp(r'<meta\s+name="viewport"[^>]*>'),
        '<meta name="viewport" content="width=${_canvas.width}">',
      );
    }
    if (content.contains('<body') && !content.contains('background')) {
      content = content.replaceFirst('<body', '<body style="background:var(--evg-background, #fff)"');
    }
    if (content.contains('<head>')) {
      content = content.replaceFirst(
        '<head>',
        '<head>\n<meta name="viewport" content="width=${_canvas.width}">\n$bridge',
      );
    } else if (content.contains('<html')) {
      content = content.replaceFirst(
        '<html',
        '<html>\n<head><meta name="viewport" content="width=${_canvas.width}">$bridge</head>',
      );
    } else {
      content = '<!DOCTYPE html>\n<html>\n<head><meta name="viewport" content="width=${_canvas.width}">$bridge</head>\n<body style="background:var(--evg-background, #fff)">$content</body>\n</html>';
    }
    return content;
  }

  void _switchMode(PreviewMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _loadContent();
  }

  Future<void> _refresh() async {
    if (!_initialized) return;
    _lastContent = widget.htmlContent;
    await _loadContent();
  }

  @override
  void didUpdateWidget(covariant PreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.htmlContent != _lastContent) _refresh();
  }

  // ═══════ JS Bridge ═══════

  Future<void> _injectBridge() async {
    await _executeJs(_bridgeScript());
  }

  static const String _bridgeScriptJs = '''
(function() {
  if (window.__evgBridgeInjected) return;
  window.__evgBridgeInjected = true;
  var _nextId = 1, _pending = {}, _listeners = {};
  function _call(method, args) {
    return new Promise(function(resolve, reject) {
      var id = _nextId++;
      _pending[id] = { resolve: resolve, reject: reject };
      _postToDart(JSON.stringify({
        id: id, method: method, args: args || []
      }));
    });
  }
  // 双通道发送：Windows chrome.webview / Android evgBridge JS 通道。
  function _postToDart(payload) {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(payload);
    } else if (window.evgBridge && window.evgBridge.postMessage) {
      window.evgBridge.postMessage(payload);
    }
  }
  function _resolve(id, result) {
    var cb = _pending[id];
    if (cb) { cb.resolve(result); delete _pending[id]; }
  }
  function _reject(id, message) {
    var cb = _pending[id];
    if (cb) { cb.reject(new Error(message)); delete _pending[id]; }
  }
  window.platform = {
    data: {
      get: function(name) { return _call('data.get', [name]); },
      list: function() { return _call('data.list', []); },
    },
    ai: { chat: function(prompt) { return _call('ai.chat', [prompt]); } },
    settings: {
      get: function(key) { return _call('settings.get', [key]); },
      set: function(key, value) { return _call('settings.set', [key, value]); },
    },
    theme: {
      getColors: function() { return _call('theme.getColors', []); },
    },
    emit: function(event, payload) { return _call('emit', [event, payload]); },
    on: function(event, fn) {
      if (!_listeners[event]) _listeners[event] = [];
      _listeners[event].push(fn);
    },
  };
  // 主题色板 → CSS 变量（--evg-*）+ 触发 'theme:changed'。
  window.__evgApplyTheme = function(colors) {
    if (!colors) return;
    var root = document.documentElement.style;
    var map = {
      '--evg-background': colors.background,
      '--evg-surface': colors.surface,
      '--evg-border': colors.border,
      '--evg-text': colors.text,
      '--evg-text-secondary': colors.textSecondary,
      '--evg-accent': colors.accent,
      '--evg-accent-bg': colors.accentBg,
      '--evg-accent-border': colors.accentBorder,
      '--evg-error': colors.error,
      '--evg-others': colors.others,
    };
    for (var k in map) root.setProperty(k, map[k]);
    window.__evgFireEvent('theme:changed', colors);
  };
  window.__evgResolve = _resolve;
  window.__evgReject = _reject;
  window.__evgFireEvent = function(name, payload) {
    var handlers = _listeners[name];
    if (handlers) handlers.forEach(function(h) { h(payload); });
  };
  console.log('[Evergreen Bridge] ready');
})();
''';

  String _bridgeScript() => _bridgeScriptJs;

  StreamSubscription? _msgSub;

  void _listenMessages() {
    _msgSub?.cancel();
    _msgSub = _controller.webMessage.listen((msg) {
      if (msg is String) _handleBridgeMessage(msg);
    });
  }

  /// 处理来自 JS 侧的消息（Windows: chrome.webview / Android: evgBridge 通道）。
  void _handleBridgeMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final id = data['id'] as int;
      final method = data['method'] as String;
      final args = (data['args'] as List?)?.cast<dynamic>() ?? [];
      _handlePlatformApi(method, args).then((result) {
        _executeJs('window.__evgResolve($id, ${jsonEncode(result)})');
      }).catchError((e) {
        _executeJs('window.__evgReject($id, ${jsonEncode(e.toString())})');
      });
    } catch (_) {}
  }

  Future<dynamic> _handlePlatformApi(String method, List<dynamic> args) async {
    final orch = ref.read(dataOrchestratorProvider);
    switch (method) {
      case 'data.get':
        final dt = orch.typeByName(args[0] as String);
        if (dt == null) return null;
        return await orch.fastRead(dt) ?? await orch.get(dt);
      case 'data.list':
        return orch.allStatuses
            .map((s) => {'name': s.name, 'displayName': s.displayName, 'freshness': s.freshnessLabel})
            .toList();
      case 'settings.get':
        return ref.read(sharedPreferencesProvider).getString(args[0] as String);
      case 'settings.set':
        await ref.read(sharedPreferencesProvider).setString(args[0] as String, (args[1] ?? '').toString());
        return 'ok';
      case 'theme.getColors':
        return _themeColors();
      case 'emit': return 'ok';
      default: throw Exception('未知 API: $method');
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel(); _httpServer?.close();
    if (!Platform.isAndroid) _controller.dispose();
    super.dispose();
  }

  /// 主题色条——当前全局主题的色板预览（插件将继承 --evg-* 变量）。
  Widget _buildThemeStrip(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _themeColors();
    const labels = {
      'background': '背景', 'surface': '面板', 'border': '边框',
      'text': '文字', 'textSecondary': '次要', 'accent': '强调',
      'accentBg': '强调底', 'accentBorder': '强调框',
      'error': '错误', 'others': '杂色',
    };
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text('主题',
              style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in colors.entries)
                  Tooltip(
                    message: '${labels[e.key] ?? e.key} · ${e.value}',
                    child: Container(
                      width: 24,
                      height: 18,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: _hexColor(e.value),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: Text('插件 CSS 可用 var(--evg-*)',
                style: TextStyle(
                    fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
        ],
      ),
    );
  }

  Color _hexColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', 'FF'), radix: 16);
    return v != null ? Color(v) : Colors.transparent;
  }

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    // 跟随主题：预览框架/画布底色（此前硬编码 0xFF1a1a2e/0xFFe8ecf1 等）
    final frameBg = scheme.surfaceContainerHighest;
    final canvasBg = Theme.of(context).scaffoldBackgroundColor;

    return Column(
      children: [
        _buildToolbar(isDark),
        _buildThemeStrip(context),
        Expanded(
          child: Container(
            color: canvasBg,
            child: _initialized
                ? LayoutBuilder(
                    builder: (ctx, constraints) {
                      final availW = constraints.maxWidth - 32;
                      final availH = constraints.maxHeight - 32;

                      // 计算画框在可用空间内的最大等比尺寸
                      final canvasRatio = _canvas.width / _canvas.height;
                      double frameW, frameH;
                      if (availW / availH > canvasRatio) {
                        frameH = availH;
                        frameW = frameH * canvasRatio;
                      } else {
                        frameW = availW;
                        frameH = frameW / canvasRatio;
                      }

                      final borderW = _mode == PreviewMode.mobile ? 12.0 : 8.0;
                      final radius = _mode == PreviewMode.mobile ? 24.0 : 12.0;

                      return Center(
                        child: Container(
                          width: frameW + borderW * 2,
                          height: frameH + borderW * 2,
                          decoration: BoxDecoration(
                            color: frameBg,
                            borderRadius: BorderRadius.circular(radius + borderW),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 24, offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // 画框边框
                              Center(
                                child: Container(
                                  width: frameW,
                                  height: frameH,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(radius),
                                    border: Border.all(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                      width: 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Platform.isAndroid
                                      ? WebViewWidget(controller: _androidController)
                                      : Webview(_controller),
                                ),
                              ),
                              // Mobile 模式：顶部刘海
                              if (_mode == PreviewMode.mobile)
                                Positioned(
                                  top: borderW + 8,
                                  left: 0, right: 0,
                                  child: Center(
                                    child: Container(
                                      width: 80,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: frameBg,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : _initError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '预览初始化失败: $_initError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.visibility, size: 14),
          const SizedBox(width: 4),
          const Text('实时预览', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 12),
          // Desktop / Mobile 切换
          _modeButton(PreviewMode.desktop, Icons.desktop_windows, '桌面'),
          const SizedBox(width: 4),
          _modeButton(PreviewMode.mobile, Icons.phone_android, '手机'),
          if (_useHttpServer) ...[
            const SizedBox(width: 8),
            Text('localhost:$_httpPort',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const Spacer(),
          Flexible(
            child: Text(_canvas.label,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            onPressed: _refresh, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(PreviewMode mode, IconData icon, String label) {
    final active = _mode == mode;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

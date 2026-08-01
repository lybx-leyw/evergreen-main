/// HtmlModleView —— 用 WebView 加载插件 HTML，通过 JS Bridge 暴露平台 API。
///
/// JS Bridge API (插件侧)：
///   platform.data.get(name)      → 从数据中枢获取数据
///   platform.data.subscribe(name, fn) → 订阅数据变化
///   platform.ai.chat(prompt)     → AI 对话
///   platform.settings.get(key)   → 读取设置
///   platform.settings.set(k, v)  → 写入设置
///   platform.theme.getColors()   → 获取当前主题色板（Promise<Object>）
///   platform.emit(event, data)   → 发出事件
///   platform.on(event, fn)       → 监听事件（含 'theme:changed'）
///
/// 平台：Windows 用 webview_windows（chrome.webview 通道），
/// Android 用 webview_flutter（evgBridge JS 通道），bridge 双通道兼容。
///
/// ## 主题色（HTML 插件可用）
///
/// 当前主题的语义色自动注入为 CSS 变量（页面加载即生效，切换主题实时更新）：
/// ```css
/// :root {
///   --evg-background: 页面背景;      --evg-surface: 卡片/面板底色;
///   --evg-border: 边框/分隔线;        --evg-text: 主文字;
///   --evg-text-secondary: 次级文字;   --evg-accent: 强调/品牌色;
///   --evg-accent-bg: 强调色半透明底;  --evg-accent-border: 强调色半透明边框;
///   --evg-error: 错误态;              --evg-others: 其余杂色;
/// }
/// ```
/// 也可编程获取：`const c = await platform.theme.getColors()`；
/// 主题切换时监听：`platform.on('theme:changed', (colors) => ...)`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/theme/render_tokens.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/html_creator_view.dart';

/// HTML 模板主视图。
class HtmlModleView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;

  const HtmlModleView({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  ConsumerState<HtmlModleView> createState() => _HtmlModleViewState();
}

class _HtmlModleViewState extends ConsumerState<HtmlModleView> {
  final WebviewController _controller = WebviewController();
  /// Android：webview_flutter（webview_windows 仅支持 Windows）。
  /// ⚠️ 必须 late：WebViewController() 构造在 Windows 上无平台实现即断言，
  /// 字段级初始化会在桌面创建本组件时崩溃；惰性初始化保证仅安卓分支访问。
  late final WebViewController _androidController = WebViewController();
  HttpServer? _httpServer;
  int _httpPort = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _startServer();
    // 主题切换时把新色板推送到页面：更新 CSS 变量 + 触发 'theme:changed' 事件。
    ref.listenManual(themeStoreProvider, (prev, next) {
      if (_initialized) {
        _executeJs('window.__evgApplyTheme(${jsonEncode(_themeColors())})');
      }
    });
  }

  @override
  void dispose() {
    _httpServer?.close();
    if (!Platform.isAndroid) {
      _controller.dispose();
    }
    super.dispose();
  }

  // ═══════ HTTP 服务器 ═══════

  Future<void> _startServer() async {
    final pluginDir = _pluginDir();
    if (pluginDir == null) return;

    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _httpPort = _httpServer!.port;

    _httpServer!.listen((req) {
      final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
      final file = File('$pluginDir/module$path');
      file.exists().then((exists) {
        if (exists) {
          final ext = path.split('.').last;
          final mime = _mimeType(ext);
          req.response.headers.set('Content-Type', mime);
          req.response.headers.set('Access-Control-Allow-Origin', '*');
          file.readAsBytes().then((bytes) {
            if (mime.startsWith('text/html')) {
              // 服务端在文档最顶部内联注入 bridge：先于 <head> 内所有脚本执行，
              // 避免插件页面早期（甚至第一行）调用 platform.* 时 bridge 未就绪
              //（onPageStarted 的 runJavaScript 晚于页面内联脚本，存在竞态）。
              try {
                var html = utf8.decode(bytes);
                html = '<script>${_bridgeScript()}</script>\n$html';
                bytes = utf8.encode(html);
              } catch (_) {}
            }
            req.response.add(bytes);
            req.response.close();
          });
        } else {
          req.response.statusCode = 404;
          req.response.write('Not found: $path');
          req.response.close();
        }
      });
    });

    _initWebView();
  }

  String _mimeType(String ext) => switch (ext) {
    'html' => 'text/html; charset=utf-8',
    'css'  => 'text/css',
    'js'   => 'application/javascript',
    'json' => 'application/json',
    'png'  => 'image/png',
    'jpg'  => 'image/jpeg',
    'svg'  => 'image/svg+xml',
    _      => 'text/plain',
  };

  String? _pluginDir() {
    if (widget.workingDirectory != null) return widget.workingDirectory;
    try {
      final pluginsRoot = ref.read(pluginsDirProvider);
      return '$pluginsRoot/${widget.descriptor.id}';
    } catch (_) {
      return null;
    }
  }

  // ═══════ WebView ═══════

  Future<void> _initWebView() async {
    if (_httpPort == 0) return;

    if (Platform.isAndroid) {
      await _initAndroidWebView();
      return;
    }

    try {
      await _controller.initialize();
      // 在文档创建时注入 bridge —— 先于页面脚本执行，
      // 避免插件 init() 立即调用 platform.* 时 bridge 未就绪。
      await _controller.addScriptToExecuteOnDocumentCreated(_bridgeScript());
      _controller.webMessage.listen(_onBridgeMessage);
      _controller.loadUrl('http://localhost:$_httpPort/index.html');
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[HtmlModleView] WebView 初始化失败: $e');
    }
  }

  // ═══════ JS Bridge ═══════

  /// Android：webview_flutter 实现。
  ///
  /// 与 Windows 的 document-created 注入对齐：onPageStarted 时注入 bridge，
  /// 消息经 evgBridge JS 通道回传（与 chrome.webview.postMessage 双通道兼容）。
  Future<void> _initAndroidWebView() async {
    await _androidController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _androidController.addJavaScriptChannel(
      'evgBridge',
      onMessageReceived: (msg) => _onBridgeMessage(msg.message),
    );
    await _androidController.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) {
        // 页面脚本执行前注入 bridge（幂等）。
        _androidController.runJavaScript(_bridgeScript()).catchError((_) {});
      },
      onPageFinished: (_) {
        if (mounted) setState(() => _initialized = true);
      },
    ));
    await _androidController.loadRequest(
      Uri.parse('http://127.0.0.1:$_httpPort/index.html'),
    );
    // 立即挂载视图（页面加载中由 WebView 自行呈现），
    // 避免 onPageFinished 异常时永远停在加载圈。
    if (mounted) setState(() => _initialized = true);
    // 兜底：确保 bridge 已注入（onPageStarted 可能早于通道就绪）。
    _androidController.runJavaScript(_bridgeScript()).catchError((_) {});
  }

  /// 执行 JS（按平台分发）。
  Future<void> _executeJs(String script) {
    if (Platform.isAndroid) {
      return _androidController.runJavaScript(script).catchError((_) {});
    }
    return _controller.executeScript(script);
  }

  String _bridgeScript() {
    return r'''
(function() {
  if (window.__evgBridgeInjected) return;
  window.__evgBridgeInjected = true;
  var _nextId = 1;
  var _pending = {};
  var _listeners = {};

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

  function _fireEvent(name, payload) {
    var handlers = _listeners[name];
    if (handlers) handlers.forEach(function(h) { h(payload); });
  }

  window.platform = {
    data: {
      get: function(name) { return _call('data.get', [name]); },
      subscribe: function(name, fn) {
        if (!_listeners['data:changed']) _listeners['data:changed'] = [];
        _listeners['data:changed'].push(fn);
        return _call('data.subscribe', [name]);
      },
    },
    ai: {
      chat: function(prompt) { return _call('ai.chat', [prompt]); },
    },
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

  // 把主题色板应用到 CSS 变量（--evg-*），并触发 'theme:changed' 事件。
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
    _fireEvent('theme:changed', colors);
  };

  // 文档创建时即拉取主题色板并应用，插件 CSS 可立即使用 --evg-* 变量。
  _call('theme.getColors', []).then(function(c) {
    window.__evgApplyTheme(c);
  });

  // 暴露回调和事件触发器到全局作用域
  window.__evgResolve = _resolve;
  window.__evgReject = _reject;
  window.__evgFireEvent = _fireEvent;

  console.log('Evergreen bridge ready');
})();
''';
  }

  void _onBridgeMessage(dynamic message) {
    try {
      final Map<String, dynamic> data;
      if (message is String) {
        data = jsonDecode(message) as Map<String, dynamic>;
      } else if (message is Map) {
        data = Map<String, dynamic>.from(message);
      } else {
        return;
      }
      final id = data['id'] as int;
      final method = data['method'] as String;
      final args = (data['args'] as List?)?.cast<dynamic>() ?? [];

      _executePlatformApi(method, args).then(
        (result) => _executeJs(
          'window.__evgResolve($id, ${jsonEncode(result)})',
        ),
        onError: (e) => _executeJs(
          'window.__evgReject($id, ${jsonEncode(e.toString())})',
        ),
      );
    } catch (e) {
      // ignore malformed messages
    }
  }

  Future<dynamic> _executePlatformApi(String method, List<dynamic> args) async {
    final orch = ref.read(dataOrchestratorProvider);

    switch (method) {
      case 'data.get':
        final name = args[0] as String;
        final dt = orch.typeByName(name);
        if (dt == null) return null;
        return await orch.fastRead(dt) ?? await orch.get(dt);

      case 'data.subscribe':
        // TODO: 真正的订阅机制
        return 'ok';

      case 'ai.chat':
        return 'AI chat 待接入';

      case 'settings.get':
        return ref.read(sharedPreferencesProvider).getString(args[0] as String);

      case 'settings.set':
        await ref.read(sharedPreferencesProvider).setString(
          args[0] as String, (args[1] ?? '').toString());
        return 'ok';

      case 'theme.getColors':
        return _themeColors();

      case 'emit':
        // TODO: 接入 PageEventBus
        return 'ok';

      default:
        throw Exception('未知 API: $method');
    }
  }

  /// 当前主题色板（HTML 插件消费）。
  ///
  /// 以 [RenderTokensColors]（随主题更新的共享色板）为来源：
  /// 8 个语义色 + accent 的半透明底/边框派生色。
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

  // ═══════ UI ═══════

  @override
  Widget build(BuildContext context) {
    // 内置创作工具走 Dart 原生渲染
    if (widget.descriptor.id == 'html-creator') {
      return HtmlCreatorView(
        descriptor: widget.descriptor,
        pluginsDir: widget.workingDirectory,
      );
    }

    // 安卓：webview_flutter 渲染（bridge 经 evgBridge JS 通道）。
    if (Platform.isAndroid) {
      return Scaffold(
        body: SafeArea(
          child: _initialized
              ? WebViewWidget(controller: _androidController)
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Webview(_controller),
      ),
    );
  }
}

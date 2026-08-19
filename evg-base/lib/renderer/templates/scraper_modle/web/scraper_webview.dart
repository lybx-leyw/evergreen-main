/// 爬虫生成器内嵌 WebView（Windows WebView2 实现）。
///
/// 使用 webview_windows 基于 Edge WebView2 提供内嵌浏览器。
///
/// **网络请求捕获——双层架构**：
///   主方案：CDP (Chrome DevTools Protocol) Network 域
///     - 通过 --remote-debugging-port 开启，全量捕获引擎级请求
///     - 覆盖：导航/fetch/XHR/子资源/WebSocket/重定向/失败请求
///   降级方案：JS 注入（PerformanceObserver + fetch + XHR + URL 监听）
///     - CDP 连接失败时自动启用
///
/// 将捕获的请求通过回调发送到 Dart 侧，最终展示在请求日志面板中。
library scraper_webview;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../workflow/scraper_workflow.dart';
import 'cdp_network_client.dart';

/// JS 注入脚本——三层 HTTP 请求捕获。
///
/// 第 1 层：PerformanceObserver — 浏览器引擎级资源（img/css/js/font/navigation/beacon 等）
/// 第 2 层：window.fetch 拦截 — 捕获 fetch 请求的 method/headers/body 细节
/// 第 3 层：XMLHttpRequest 拦截 — 捕获 XHR 请求的 method/headers/body 细节
///
/// 通过 chrome.webview.postMessage 发送到 Dart 侧。
const String _httpInterceptorJs = '''
(function() {
  if (window.__evg_scraper_hooked) return;
  window.__evg_scraper_hooked = true;

  function sendToDart(data) {
    try {
      var payload = JSON.stringify(data);
      // Windows: chrome.webview.postMessage；Android: evgScraper JS 通道
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(payload);
      } else if (window.evgScraper && window.evgScraper.postMessage) {
        window.evgScraper.postMessage(payload);
      }
    } catch (e) {
      console.error('[EVG Scraper] sendToDart failed:', e);
    }
  }

  function safeStringify(val) {
    try { return JSON.stringify(val); } catch(e) { return ''; }
  }

  // ═══════ 第 1 层：PerformanceObserver — 浏览器引擎级资源捕获 ═══════
  if (window.PerformanceObserver) {
    try {
      var perfObserver = new PerformanceObserver(function(list) {
        var entries = list.getEntries();
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i];
          if (entry.initiatorType === 'fetch' || entry.initiatorType === 'xmlhttprequest') continue;
          sendToDart({
            timestamp: new Date(Date.now()).toISOString(),
            method: 'GET',
            url: entry.name || '',
            type: entry.initiatorType || 'resource',
            headers: {},
          });
        }
      });
      perfObserver.observe({ type: 'resource', buffered: true });
      try { perfObserver.observe({ type: 'navigation', buffered: true }); } catch(e) {}
      console.log('[EVG Scraper] PerformanceObserver OK');
    } catch (e) {
      console.error('[EVG Scraper] PerformanceObserver failed:', e);
    }
  }

  // ═══════ 第 2 层：拦截 window.fetch ═══════
  try {
    if (typeof window.fetch === 'function') {
      var origFetch = window.fetch;
      window.fetch = function() {
        var args = arguments;
        var url = args[0];
        var options = args[1];
        var payload = {
          timestamp: new Date().toISOString(),
          method: (options && options.method) ? options.method.toUpperCase() : 'GET',
          url: typeof url === 'string' ? url : (url && url.url ? url.url : (url && url.href ? url.href : '')),
          headers: {},
        };
        if (options && options.headers) {
          try {
            if (options.headers instanceof Headers) {
              options.headers.forEach(function(v, k) { payload.headers[k] = v; });
            } else if (typeof options.headers === 'object') {
              var keys = Object.keys(options.headers);
              for (var j = 0; j < keys.length; j++) {
                payload.headers[keys[j]] = options.headers[keys[j]];
              }
            }
          } catch(he) {}
        }
        if (options && options.body) {
          try {
            var b = typeof options.body === 'string' ? options.body : safeStringify(options.body);
            if (b) payload.body = b.substring(0, 4096);
          } catch(be) {}
        }
        sendToDart(payload);
        return origFetch.apply(this, args);
      };
      console.log('[EVG Scraper] fetch hooked');
    }
  } catch (e) {
    console.error('[EVG Scraper] fetch hook failed:', e);
  }

  // ═══════ 第 3 层：拦截 XMLHttpRequest ═══════
  try {
    if (typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.prototype) {
      var OrigXHROpen = XMLHttpRequest.prototype.open;
      var OrigXHRSend = XMLHttpRequest.prototype.send;
      var OrigXHRSetHeader = XMLHttpRequest.prototype.setRequestHeader;

      XMLHttpRequest.prototype.open = function(method, url) {
        this._evgMethod = (method || 'GET').toString().toUpperCase();
        this._evgUrl = typeof url === 'string' ? url : (url && url.toString ? url.toString() : '');
        this._evgHeaders = {};
        return OrigXHROpen.apply(this, arguments);
      };

      XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (!this._evgHeaders) this._evgHeaders = {};
        this._evgHeaders[name] = value;
        return OrigXHRSetHeader.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function(body) {
        var payload = {
          timestamp: new Date().toISOString(),
          method: this._evgMethod || 'GET',
          url: this._evgUrl || '',
          headers: Object.assign({}, this._evgHeaders || {}),
        };
        if (body) {
          try {
            var b = typeof body === 'string' ? body : safeStringify(body);
            if (b) payload.body = b.substring(0, 4096);
          } catch(be) {}
        }
        sendToDart(payload);
        return OrigXHRSend.apply(this, arguments);
      };
      console.log('[EVG Scraper] XHR hooked');
    }
  } catch (e) {
    console.error('[EVG Scraper] XHR hook failed:', e);
  }

  console.log('[EVG Scraper] Interceptors ready (PerfObserver + fetch + XHR)');
})();
''';

// ═══════ ScraperWebView ═══════

/// Phase 4：浏览器 JS/导航执行通道（探索模式工具消费）。
///
/// 由 [ScraperWebView] 在初始化时按平台填充：
/// - `evaluateJavaScript` — Windows `WebviewController.executeScript`（**不回传
///   求值结果**，经 `chrome.webview.postMessage` 结果通道桥接，带 10s 超时）/
///   Android `WebViewController.runJavaScriptReturningResult`（原生回传）
/// - `navigateTo` — 纯 GET 导航（同域/上限/节流守卫由 ExploreWorkflow 负责）
/// - `currentUrl` — 当前地址栏 URL（用于开始探索时锁定域名）
///
/// 与 Widget 解耦：探索工具只依赖本对象，可在测试中注入假实现。
class ScraperWebViewBridge {
  Future<String?> Function(String script)? evaluateJavaScript;
  Future<void> Function(String url)? navigateTo;
  Future<String?> Function()? currentUrl;

  /// JS 通道是否已就绪（WebView 初始化完成后由 [ScraperWebView] 设为 true）。
  bool ready = false;
}

/// 爬虫生成器专用的内嵌 WebView 组件（Windows WebView2）。
///
/// 特性：
/// - 默认加载 [initialUrl]，支持地址栏输入跳转
/// - 三层 HTTP 请求拦截（PerfObserver + fetch + XHR）
/// - 导航 URL 变化自动作为日志条目捕获
/// - 拦截到的请求通过 [onRequestCaptured] 回调发送到工作流
/// - 地址栏提供 URL 输入 + 刷新 + 前进/后退
class ScraperWebView extends StatefulWidget {
  /// 默认打开的 URL。
  final String initialUrl;

  /// 请求捕获回调。
  final void Function(HttpRequestLog log)? onRequestCaptured;

  /// WebView 初始化完成且首帧绘制后回调。
  ///
  /// 父级用它门控「命名弹窗」——避免 Webview 在弹窗覆盖期间才挂载，
  /// 导致 WebView2 纹理丢帧 → 弹窗关闭后黑屏。
  final VoidCallback? onInitialized;

  /// 每次 +1 时强制重挂载 Webview（新 key → 重新上报 surface size）
  /// 并调用 [WebviewController.resume]，恢复弹窗等遮挡层关闭后可能
  /// 丢失的 WebView2 纹理帧。
  final int refreshTick;

  /// 是否锁定（A18：日志快照冻结后锁定，禁止继续操作）。
  final bool locked;

  /// 重抓按钮回调（A18：用户确认后回首页重启抓取）。
  final VoidCallback? onRestartCapture;

  /// Phase 4：JS/导航执行通道（探索模式）。初始化时填充，可空（定向模式不用）。
  final ScraperWebViewBridge? bridge;

  const ScraperWebView({
    super.key,
    this.initialUrl = 'https://www.baidu.com',
    this.onRequestCaptured,
    this.onInitialized,
    this.refreshTick = 0,
    this.locked = false,
    this.onRestartCapture,
    this.bridge,
  });

  @override
  State<ScraperWebView> createState() => _ScraperWebViewState();
}

class _ScraperWebViewState extends State<ScraperWebView> {
  final _controller = WebviewController();
  /// Android：webview_flutter（webview_windows 仅支持 Windows）。
  /// ⚠️ 必须 late：WebViewController() 构造在 Windows 上无平台实现即断言，
  /// 字段级初始化会在桌面创建本组件时崩溃；惰性初始化保证仅安卓分支访问。
  late final _androidController = WebViewController();
  final _urlCtrl = TextEditingController();
  bool _initialized = false;
  String? _initError;
  bool _isLoading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _prevUrl = '';

  // ── CDP 全量网络捕获 ──
  CdpNetworkClient? _cdpClient;
  StreamSubscription? _cdpSub;
  bool _cdpActive = false;

  // ── JS 注入降级 ──
  StreamSubscription? _loadingSub;
  StreamSubscription? _urlSub;
  StreamSubscription? _historySub;
  StreamSubscription? _webMessageSub;
  StreamSubscription? _loadErrorSub;


  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.initialUrl;
    // Phase 4：填充 JS/导航执行通道（探索模式工具消费）。
    // ready 保持 false 直到 WebView 初始化完成，避免探索工具在页面未就绪时
    // 调用 evaluateJs 导致"页面未就绪"超时。
    final bridge = widget.bridge;
    if (bridge != null) {
      bridge
        ..ready = false
        ..evaluateJavaScript = _evaluateJs
        ..navigateTo = _navigateToUrl
        ..currentUrl = _getCurrentUrl;
    }
    _initWebView();
  }

  // ── Phase 4：JS/导航执行通道实现 ──

  /// 执行 JS 并返回结果字符串。
  ///
  /// - Android：`runJavaScriptReturningResult`（原生回传 JSON 编码的结果）
  /// - Windows：`WebviewController.executeScript` **原生回传求值结果**
  ///   （webview_windows 0.4.0 的 C++ `ExecuteScript` 回调 `Success(json_result)`，
  ///   Dart 侧 `jsonDecode` 后返回），无需 postMessage 桥接。
  ///
  ///   修复背景（bug：浏览器 JS 通道失效）：旧实现误以为 executeScript 不
  ///   回传结果，绕道 `chrome.webview.postMessage` + `webMessage` 流 + 10s
  ///   超时，任一环节失效即返回 null → `explore_page_links` 报「JS 通道不可用」。
  ///   现直接消费原生返回值；脚本抛异常/返回非字符串时回退为 JSON 字符串，
  ///   空结果返回 null（调用方降级提示）。
  Future<String?> _evaluateJs(String script) async {
    if (Platform.isAndroid) {
      final result = await _androidController.runJavaScriptReturningResult(script);
      return result == null ? null : result.toString();
    }
    try {
      final raw = await _controller.executeScript(script);
      // executeScript 返回 jsonDecode 后的结果：字符串原样、对象/数组已解码、
      // null/undefined → null。
      if (raw == null) return null;
      if (raw is String) return raw;
      return jsonEncode(raw);
    } catch (e) {
      _log('⚠ _evaluateJs 执行失败: $e');
      return null;
    }
  }

  /// 纯 GET 导航（守卫在 ExploreWorkflow 层，此处只执行）。
  Future<void> _navigateToUrl(String url) {
    if (Platform.isAndroid) {
      return _androidController.loadRequest(Uri.parse(url));
    }
    return _controller.loadUrl(url);
  }

  /// 当前 URL（地址栏最新值；初始未导航时回退初始 URL）。
  Future<String?> _getCurrentUrl() async =>
      _prevUrl.isNotEmpty ? _prevUrl : widget.initialUrl;

  Future<void> _initWebView() {
    if (Platform.isAndroid) return _initAndroidWebView();
    return _initWindowsWebView();
  }

  /// Android：webview_flutter 实现（无 CDP，依赖 JS 注入拦截请求）。
  Future<void> _initAndroidWebView() async {
    await _androidController.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _androidController.addJavaScriptChannel(
      'evgScraper',
      onMessageReceived: (msg) => _handleWebMessage(msg.message),
    );
    await _androidController.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final url = request.url;
        // 正常网页导航放行
        if (url.startsWith('http://') || url.startsWith('https://')) {
          return NavigationDecision.navigate;
        }
        // 自定义 scheme（baiduboxapp:// 等）：WebView 无法加载 →
        // ERR_UNKNOWN_URL_SCHEME + 导航失败。阻止并尝试改写为真实网页。
        _log('🚫 拦截自定义 scheme 导航: ${url.length > 160 ? '${url.substring(0, 160)}...' : url}');
        // baiduboxapp://v1/browser/open?url=<encoded https> → 解码后继续爬取
        final m = RegExp(r'baiduboxapp://[^?]*\?.*[?&]url=([^&]+)').firstMatch(url);
        if (m != null) {
          try {
            final real = Uri.decodeComponent(m.group(1)!);
            if (real.startsWith('http://') || real.startsWith('https://')) {
              _log('🔀 改写为网页导航: $real');
              _androidController.loadRequest(Uri.parse(real));
            }
          } catch (_) {}
        }
        return NavigationDecision.prevent;
      },
      onUrlChange: (change) {
        if (!mounted) return;
        final u = change.url ?? '';
        if (u.isEmpty) return;
        _urlCtrl.text = u;
        if (u != _prevUrl) {
          _prevUrl = u;
          _log('📍 URL 变更: $u');
          widget.onRequestCaptured?.call(HttpRequestLog(
            timestamp: DateTime.now(),
            method: 'NAVIGATION',
            url: u,
          ));
        }
      },
      onPageStarted: (_) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        _injectInterceptor();
      },
      onPageFinished: (_) async {
        if (!mounted) return;
        _injectInterceptor();
        final canBack = await _androidController.canGoBack();
        final canFwd = await _androidController.canGoForward();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _canGoBack = canBack;
          _canGoForward = canFwd;
        });
      },
      onWebResourceError: (e) {
        _log('⚠ 资源加载错误: ${e.description}');
      },
    ));
    await _androidController.loadRequest(Uri.parse(widget.initialUrl));
    if (!mounted) return;
    setState(() => _initialized = true);
    widget.bridge?.ready = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onInitialized?.call();
    });
  }

  /// 注入三层 HTTP 请求拦截器（Android 主方案；幂等）。
  Future<void> _injectInterceptor() async {
    try {
      await _androidController.runJavaScript(_httpInterceptorJs);
    } catch (e) {
      _log('⚠ 拦截器注入失败: $e');
    }
  }

  @override
  void didUpdateWidget(ScraperWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _resyncSurface();
    }
  }

  /// 弹窗/遮挡层关闭后，WebView2 纹理可能丢帧黑屏。
  ///
  /// 重建 Webview widget（新 key → 重新上报 surface size）并调用
  /// [WebviewController.resume] 强制 compositor 重渲染，恢复纹理。
  void _resyncSurface() {
    if (!mounted || !_initialized) return;
    // Android：webview_flutter 为平台视图渲染，无纹理丢帧问题。
    if (Platform.isAndroid) return;
    _log('🔄 WebView 表面重同步 (refreshTick=${widget.refreshTick})');
    setState(() {});
    _controller.resume().catchError((_) {});
  }

  Future<void> _initWindowsWebView() async {
    try {
      // 注意：CDP 远程调试端口（--remote-debugging-port=9222）已由
      // AppBootstrap._stepWebView2 通过
      // `WebviewController.initializeEnvironment(additionalArguments: ...)` 在
      // 启动序列早期（任何 WebviewController 构造前）正确初始化。
      // 此处不能再设置环境（environment 全局唯一、仅可初始化一次），也无需
      // 再用 FFI 设 WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS（webview_windows
      // 插件不读该环境变量，属无效冗余）。
      _log('🏁 初始化 WebView2（CDP 环境由 AppBootstrap 预先设置）');

      await _controller.initialize();
      if (!mounted) return;

      // ── 预注册 JS 拦截器（降级方案） ──
      // addScriptToExecuteOnDocumentCreated 在全局对象创建后、HTML 解析前执行。
      await _controller.addScriptToExecuteOnDocumentCreated(_httpInterceptorJs);
      _log('✓ JS 降级拦截器已预注册');

      // ── 阻止新窗口弹出 —— window.open / target=_blank 在原窗口打开 ──
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      _log('✓ 弹窗策略: sameWindow（新窗口拦截）');

      // ── 监听加载状态（进度条） ──
      _loadingSub = _controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          switch (state) {
            case LoadingState.loading:
              _isLoading = true;
              break;
            case LoadingState.navigationCompleted:
              _isLoading = false;
              break;
            case LoadingState.none:
              break;
          }
        });
      });

      // ── 监听 URL 变化（更新地址栏 + 捕获导航请求） ──
      _urlSub = _controller.url.listen((url) {
        if (!mounted) return;
        _urlCtrl.text = url;

        // 捕获导航请求（页面跳转不会被 fetch/XHR 拦截器捕获）
        if (url.isNotEmpty && url != _prevUrl) {
          _prevUrl = url;
          _log('📍 URL 变更: $url');
          widget.onRequestCaptured?.call(HttpRequestLog(
            timestamp: DateTime.now(),
            method: 'NAVIGATION',
            url: url,
          ));
        }
      });

      // ── 监听历史状态（前进/后退按钮） ──
      _historySub = _controller.historyChanged.listen((h) {
        if (!mounted) return;
        setState(() {
          _canGoBack = h.canGoBack;
          _canGoForward = h.canGoForward;
        });
      });

      // ── 监听 WebMessage（来自 JS 的 chrome.webview.postMessage） ──
      _webMessageSub = _controller.webMessage.listen((message) {
        _handleWebMessage(message);
      });

      // ── 监听加载错误 ──
      _loadErrorSub = _controller.onLoadError.listen((error) {
        _log('⚠ 资源加载错误: $error');
      });

      setState(() => _initialized = true);
      widget.bridge?.ready = true;

      // 加载初始页面（拦截器已预注册，会自动在文档创建时注入）
      _controller.loadUrl(widget.initialUrl);
      _log('🌐 初始 URL: ${widget.initialUrl}');

      // ── 首帧绘制后通知父级（命名弹窗门控）──
      // 注意：CDP 探测最长可阻塞 5s+，必须放到挂载之后并行执行，
      // 否则 Webview 会在命名弹窗覆盖期间才挂载 → 纹理丢帧 → 黑屏。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onInitialized?.call();
      });

      // ── CDP 全量网络捕获（主方案）——与页面加载并行，失败自动降级 JS 注入 ──
      await _connectCdp();
    } catch (e) {
      _log('❌ WebView 初始化失败: $e');
      if (mounted) {
        setState(() => _initError = e.toString());
        // 初始化失败同样放行命名弹窗，不阻塞用户流程。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onInitialized?.call();
        });
      }
    }
  }

  /// 尝试连接 CDP 远程调试端点，开启全量网络捕获。
  ///
  /// 成功时 [onRequestCaptured] 通过 CDP Network 事件接收所有请求；
  /// 失败时自动降级到 JS 注入方案，不影响使用。
  Future<void> _connectCdp() async {
    if (!mounted) return;

    _cdpClient = CdpNetworkClient(debugPort: 9222);

    // 监听 CDP 状态日志
    _cdpClient!.statusLog.listen((msg) {
      _log('CDP: $msg');
    });

    final ok = await _cdpClient!.connect();

    if (ok) {
      _cdpActive = true;
      _log('🎯 CDP Network 域已启用 — 全量网络捕获活跃');
      _log('🧭 bridge.ready=${widget.bridge?.ready}（探索工具 JS/导航通道就绪状态）');

      // 将 CDP 事件转发到 onRequestCaptured
      _cdpSub = _cdpClient!.networkEvents.listen((event) {
        if (!mounted) return;

        // 只转发有实际 URL 的请求日志：
        //   requestWillBeSent — 真实请求 ✅
        //   responseReceived — 响应（含 status code）✅
        //   webSocketCreated / webSocketFrame — WebSocket ✅
        //   frameNavigated — 页面导航 ✅
        // 跳过：
        //   loadingFinished — 只有 requestId（无 URL），噪声
        //   loadingFailed — 同上
        final url = event.log.url;
        if (url.isEmpty) return;

        // 必须是真实 URL（http/https/ws/wss 开头）或 WebSocket 标记
        final isRealUrl = url.startsWith('http://') ||
            url.startsWith('https://') ||
            url.startsWith('ws://') ||
            url.startsWith('wss://') ||
            event.eventType == 'webSocketCreated' ||
            event.eventType == 'webSocketFrame';
        if (!isRealUrl) return;

        widget.onRequestCaptured?.call(event.log);
      });
    } else {
      _log('⚠ CDP 连接失败（端口 9222 不可达），降级到 JS 注入方案。'
          '若导航正常但捕获日志为空，请确认 AppBootstrap._stepWebView2 已'
          '初始化 CDP 环境，且 9222 端口未被占用。');
      _cdpClient?.dispose();
      _cdpClient = null;
    }
  }

  /// 处理来自 WebView JS 的消息。
  void _handleWebMessage(dynamic message) {
    try {
      Map<String, dynamic> json;
      if (message is String) {
        json = jsonDecode(message) as Map<String, dynamic>;
      } else if (message is Map) {
        json = Map<String, dynamic>.from(message);
      } else {
        return;
      }

      final log = HttpRequestLog.fromJson(json);
      _log('📋 拦截: ${log.method} ${log.url}');
      widget.onRequestCaptured?.call(log);
    } catch (e) {
      _log('⚠ 解析拦截请求失败: $e');
    }
  }

  @override
  void dispose() {
    if (!Platform.isAndroid) {
      _cdpSub?.cancel();
      _cdpClient?.dispose();
      _loadingSub?.cancel();
      _urlSub?.cancel();
      _historySub?.cancel();
      _webMessageSub?.cancel();
      _loadErrorSub?.cancel();
      _controller.dispose();
    }
    _urlCtrl.dispose();
    super.dispose();
  }

  void _navigate() {
    final text = _urlCtrl.text.trim();
    if (text.isEmpty) return;
    // 自动补全 http(s)://
    final url = text.startsWith('http://') || text.startsWith('https://')
        ? text
        : 'https://$text';
    if (Platform.isAndroid) {
      _androidController.loadRequest(Uri.parse(url));
    } else {
      _controller.loadUrl(url);
    }
  }

  void _goBack() {
    if (Platform.isAndroid) {
      _androidController.goBack();
    } else {
      _controller.goBack();
    }
  }

  void _goForward() {
    if (Platform.isAndroid) {
      _androidController.goForward();
    } else {
      _controller.goForward();
    }
  }

  void _refresh() {
    if (Platform.isAndroid) {
      _androidController.reload();
    } else {
      _controller.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Android：webview_flutter 渲染（地址栏与 Windows 共用）。
    if (Platform.isAndroid) return _buildAndroid(context);
    // ── 初始化错误（Windows）──
    if (_initError != null) {
      return _buildErrorState(context);
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        // ── 地址栏 ──
        _buildAddressBar(theme),
        // ── WebView ──
        Expanded(
          child: Stack(
            children: [
              // 初始化完成 → Webview（refreshTick 变化时换 key 强制重挂载，恢复纹理）
              if (_initialized)
                KeyedSubtree(
                  key: ValueKey('scraper-webview-${widget.refreshTick}'),
                  child: Webview(_controller),
                )
              else
                _buildLoadingPlaceholder(context),
              // 加载进度条
              if (_isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              // 锁定遮罩（A18）
              if (widget.locked) _buildLockOverlay(theme),
            ],
          ),
        ),
      ],
    );
  }

  /// 快照冻结后的锁定遮罩（A18）：阻止继续操作，提供重抓入口。
  Widget _buildLockOverlay(ThemeData theme) {
    return Positioned.fill(
      child: Container(
        color: theme.colorScheme.scrim.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded,
                    size: 32, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                const Text('日志快照已冻结，浏览器已锁定',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('AI 正在基于快照分析。如需重新抓取，请点击下方按钮。',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: widget.onRestartCapture,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('重新抓取'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Android：webview_flutter 渲染主体（地址栏与 Windows 共用）。
  Widget _buildAndroid(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildAddressBar(theme),
        Expanded(
          child: Stack(
            children: [
              if (_initialized)
                WebViewWidget(controller: _androidController)
              else
                _buildLoadingPlaceholder(context),
              if (_isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (widget.locked) _buildLockOverlay(theme),
            ],
          ),
        ),
      ],
    );
  }

  /// 初始化期间展示加载占位（避免空 Stack 显示为一片黑）。
  Widget _buildLoadingPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 12),
          Text(
            '正在初始化 WebView2…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'WebView 渲染不可用',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              '需要 Edge WebView2 运行时',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              _initError!,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 后退
          _barButton(
            Icons.arrow_back_ios_rounded,
            _canGoBack ? _goBack : null,
            '后退',
          ),
          const SizedBox(width: 2),
          // 前进
          _barButton(
            Icons.arrow_forward_ios_rounded,
            _canGoForward ? _goForward : null,
            '前进',
          ),
          const SizedBox(width: 2),
          // 刷新
          _barButton(Icons.refresh_rounded, _refresh, '刷新'),
          const SizedBox(width: 8),
          // URL 输入
          Expanded(
            child: TextField(
              controller: _urlCtrl,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                filled: true,
                fillColor: theme.colorScheme.surface,
                hintText: '输入网址...',
                hintStyle: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              onSubmitted: (_) => _navigate(),
            ),
          ),
          const SizedBox(width: 6),
          // 跳转
          SizedBox(
            height: 32,
            child: IconButton.filledTonal(
              onPressed: _navigate,
              icon: const Icon(Icons.arrow_forward, size: 14),
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barButton(IconData icon, VoidCallback? onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 16,
            color: onTap != null ? null : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// ── 调试日志 ──
void _log(String msg) {
  assert(() {
    debugPrint('[ScraperWebView] $msg');
    return true;
  }());
}


/// HtmlModleView —— 用 WebView 加载插件 HTML，通过 JS Bridge 暴露平台 API。
///
/// JS Bridge API (插件侧)：
///   platform.data.get(name)      → 从数据中枢获取数据
///   platform.data.refresh(name)  → 强制刷新数据源（POST /data/types/:name/refresh）
///   platform.data.testConnectivity() → 测试全部数据源连通性（POST /data/connectivity/test）
///   platform.data.subscribe(name, fn) → 订阅数据变化（Dart 侧 5s 轮询，变化触发 data:changed）
///   platform.ai.chat(prompt, [style]) → AI 对话（接 AgentHttpServer POST /agent/chat）
///   platform.api.call(service, path, {method, body}) → 通用 core 服务 HTTP 转发
///     - service: agent/config/data/module/theme/core（6 组 core 服务）
///     - 端口来自 `.xxx_port` 端口文件（CoreApiDiscovery）
///   platform.settings.get(key)   → 读取设置
///   platform.settings.set(k, v)  → 写入设置
///   platform.theme.getColors()   → 获取当前主题色板（Promise<Object>）
///   platform.emit(event, data)   → 发出事件（PageEventBus 广播）
///   platform.on(event, fn)       → 监听事件（PageEventBus 订阅 + 'theme:changed'）
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
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/app/service/theme/render_tokens.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/html_creator_view.dart';
import 'bridge_script.dart';
import 'core_api_discovery.dart';

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

  /// 页级事件总线：插件 `emit`/`on` 的桥接通道（Dart 侧广播 ↔ JS 侧回调）。
  late final PageEventBus _eventBus = PageEventBus(
    pageId: widget.descriptor.id,
  );
  StreamSubscription<SlotEvent>? _eventBusSub;

  /// 数据订阅轮询：dataName → 5s 拉取，值变化推送 data:changed（共享实现）。
  late final DataSubscriptionPoller _poller;

  /// 常驻进程会话（key = exe 名或 id）：`platform.process.start/stop/write/read`。
  final Map<String, _LongProcessSession> _longProcesses = {};

  /// html-creator 已走 Dart 原生 [HtmlCreatorView]，不需要启动本地 HTTP
  /// 服务或 WebView；这里提前短路，避免进入开发者模式时白白初始化 WebView2。
  bool get _isNativeCreator => widget.descriptor.id == 'html-creator';

  @override
  void initState() {
    super.initState();
    if (!_isNativeCreator) {
      _startServer();
    }
    _poller = DataSubscriptionPoller(
      fetch: (name) async {
        final orch = ref.read(dataOrchestratorProvider);
        final dt = orch.typeByName(name);
        if (dt == null) return null; // 未注册：跳过本轮
        return await orch.fastRead(dt) ?? await orch.get(dt);
      },
      executeJs: _executeJs,
    );
    // 主题切换时把新色板推送到页面：更新 CSS 变量 + 触发 'theme:changed' 事件。
    ref.listenManual(themeStoreProvider, (prev, next) {
      if (_initialized) {
        _executeJs('window.__evgApplyTheme(${jsonEncode(_themeColors())})');
      }
    });
    // PageEventBus → JS：Dart 侧（其他栏/模块）发出的事件推送给页面 `platform.on`。
    _eventBusSub = _eventBus.all.listen((evt) {
      if (!_initialized) return;
      final payload = jsonEncode({
        'event': evt.event,
        'source': evt.sourceSlot,
        'data': evt.data,
        'timestamp': evt.timestamp.toIso8601String(),
      });
      debugPrint('[HtmlModleView] PageEventBus → JS: ${evt.event}');
      _executeJs('window.__evgFireEvent(${jsonEncode(evt.event)}, $payload)');
    });
  }

  @override
  void dispose() {
    _httpServer?.close();
    _poller.dispose();
    _eventBusSub?.cancel();
    _eventBus.dispose();
    // 终止所有常驻进程（避免插件卸载后残留进程）。
    for (final session in _longProcesses.values) {
      session.stop();
    }
    _longProcesses.clear();
    // 原生创作工具没有初始化 WebView2，不能调用 _controller.dispose()
    //（其内部会等待尚未创建的 _creatingCompleter，导致 LateInitializationError）。
    if (!_isNativeCreator && !Platform.isAndroid) {
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
    'css' => 'text/css',
    'js' => 'application/javascript',
    'json' => 'application/json',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'svg' => 'image/svg+xml',
    _ => 'text/plain',
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
    await _androidController.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          // 页面脚本执行前注入 bridge（幂等）。
          _androidController.runJavaScript(_bridgeScript()).catchError((_) {});
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _initialized = true);
        },
      ),
    );
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

  String _bridgeScript() => buildBridgeScript();

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
        (result) =>
            _executeJs('window.__evgResolve($id, ${jsonEncode(result)})'),
        onError: (e) =>
            _executeJs('window.__evgReject($id, ${jsonEncode(e.toString())})'),
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
        // 真正的订阅：Dart 侧 5s 轮询，值变化推 data:changed 事件。
        _poller.subscribe(args[0] as String);
        return 'ok';

      case 'data.refresh':
        // POST /data/types/:name/refresh —— 强制重抓并写回中枢缓存。
        return await _httpForward(
          CoreService.data,
          'POST',
          '/data/types/${args[0] as String}/refresh',
        );

      case 'data.testConnectivity':
        // POST /data/connectivity/test —— 测试全部数据源连通性。
        return await _httpForward(
          CoreService.data,
          'POST',
          '/data/connectivity/test',
        );

      case 'ai.chat':
        // POST /agent/chat —— 非流式对话，返回事件数组 + 拼接文本。
        final prompt = (args[0] ?? '').toString();
        final style = args.length > 1 && args[1] != null
            ? args[1].toString()
            : null;
        final result = await _httpForward(
          CoreService.agent,
          'POST',
          '/agent/chat',
          {
            'input': prompt,
            if (style != null && style.isNotEmpty) 'style': style,
          },
        );
        final map = (result as Map<String, dynamic>?) ?? const {};
        final events =
            (map['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final text = events
            .map((e) => e['text'])
            .whereType<String>()
            .where((t) => t.isNotEmpty)
            .join('\n');
        return {'text': text, 'events': events};

      case 'api.call':
        // 通用 core 服务 HTTP 转发：api.call('agent', '/agent/tools', {method:'GET', body:{...}})
        final serviceId = args[0] as String;
        final path = args[1] as String;
        final opts = args.length > 2 && args[2] is Map
            ? Map<String, dynamic>.from(args[2] as Map)
            : <String, dynamic>{};
        final service = CoreService.values.firstWhere(
          (s) => s.id == serviceId,
          orElse: () => throw Exception('未知服务: $serviceId'),
        );
        final method = ((opts['method'] as String?) ?? 'GET').toUpperCase();
        final body = opts['body'];
        return await _httpForward(
          service,
          method,
          path,
          body is Map ? Map<String, dynamic>.from(body as Map) : null,
        );

      case 'settings.get':
        return ref.read(sharedPreferencesProvider).getString(args[0] as String);

      case 'settings.set':
        // 走 ConfigHttpServer 的 POST /config/settings/:key，而非直接写
        // SharedPreferences：该路由会调用 syncConfigToGreenix()，把值同步到
        // `.greenix/config.json`，否则 Python 常驻进程的 `_get_config` 三级降级
        // 读不到新值（「恢复监控」等设置变更对 worker 无效）。
        final key = args[0] as String;
        final value = (args[1] ?? '').toString();
        return await _httpForward(
          CoreService.config,
          'POST',
          '/config/settings/$key',
          {'value': value},
        );

      case 'theme.getColors':
        return _themeColors();

      case 'emit':
        // 事件桥接：插件 emit → PageEventBus 广播 → 同页其他栏/模块可订阅。
        final event = args[0] as String;
        final payload = args.length > 1 && args[1] is Map
            ? Map<String, dynamic>.from(args[1] as Map)
            : <String, dynamic>{};
        _eventBus.emit(event, sourceSlot: 'html-plugin', data: payload);
        return 'ok';

      case 'process.run':
        // 运行本插件 manifest `process` 声明的 exe（白名单内才允许，方案 A）。
        // args[0] = exe 名（或 id）；args[1] = {args, input}。
        final exe = args[0] as String;
        final opts = args.length > 1 && args[1] is Map
            ? Map<String, dynamic>.from(args[1] as Map)
            : <String, dynamic>{};
        return await _runPluginProcess(exe, opts);

      case 'process.start':
        // 启动常驻进程（scope:"long"），输出经 process:output 事件推送。
        // args[0] = exe 名（或 id）；args[1] = {args}。
        return await _startLongProcess(
          args[0] as String,
          args.length > 1 && args[1] is Map
              ? Map<String, dynamic>.from(args[1] as Map)
              : <String, dynamic>{},
        );

      case 'process.write':
        // 向常驻进程 stdin 写数据。
        return await _writeLongProcess(
            args[0] as String, (args.length > 1 ? args[1] : '')?.toString() ?? '');

      case 'process.stop':
        // 终止常驻进程。
        return await _stopLongProcess(args[0] as String);

      case 'process.read':
        // 读常驻进程当前累积的 stdout。
        return {'stdout': _readLongProcess(args[0] as String)};

      default:
        throw Exception('未知 API: $method');
    }
  }

  /// 运行本插件 manifest `process` 声明的 exe（方案 A：白名单内才允许）。
  ///
  /// [exe] 为 manifest `process[].exe` 或 `process[].id`；[opts.args] 为命令行参数
  /// （如 `['-u', username, '-p', password]`）。
  ///
  /// 白名单：只允许 [ModuleDescriptor.process] 里声明的进程，杜绝 HTML 插件跑
  /// 任意系统命令（fail-closed）。未声明 → 抛异常。返回 `{stdout, stderr, exitCode}`。
  Future<Map<String, dynamic>> _runPluginProcess(
      String exe, Map<String, dynamic> opts) async {
    final declared = _findDeclaredProcess(exe);
    if (declared == null) {
      throw Exception(
          '进程 "$exe" 未在 manifest 的 process 中声明，拒绝执行（fail-closed）');
    }

    final args = (opts['args'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];

    // exe 相对插件目录解析（与 ProcessManager 一致），并做跨平台扩展名兜底：
    // Windows 上 release 二进制常带 `.exe`，manifest 写 `zjuical` 时自动补 `.exe`。
    final pluginDir = _pluginDir();
    if (pluginDir == null) {
      throw Exception('无法定位插件目录');
    }
    final exePath = _resolveExePath(pluginDir, declared.exe);
    if (exePath == null) {
      throw Exception('exe 不存在: ${p.join(pluginDir, declared.exe)}');
    }

    final runner = await sharedPluginRunner;
    final r = await runner.runOnce(
      exePath,
      args,
      workingDirectory: pluginDir,
      runtime: declared.runtime,
    );
    return {'stdout': r.stdout, 'stderr': r.stderr, 'exitCode': r.exitCode};
  }

  /// 解析 exe 的磁盘路径（跨平台扩展名兜底）。
  ///
  /// [declared] 为 manifest `process[].exe`（可能不含扩展名）。按序尝试：
  /// 1. `pluginDir/declared`（原样）
  /// 2. Windows 下 `pluginDir/declared.exe`
  /// 3. 其余平台 `pluginDir/declared`（无扩展名，Unix 惯例）
  ///
  /// 全部不存在返回 null。
  String? _resolveExePath(String pluginDir, String declared) {
    // 候选路径：优先 module/ 子目录（module 进程脚本约定在 module/ 下，
    // 如 worker.py 与 index.html 同目录），其次插件根目录（如 release 二进制
    // zjuical.exe 直接解压到根）。每个位置都做 Windows .exe 扩展名兜底。
    final candidates = <String>[
      p.join(pluginDir, 'module', declared),
      p.join(pluginDir, declared),
    ];
    final withExe = <String>[];
    if (Platform.isWindows && !declared.toLowerCase().endsWith('.exe')) {
      for (final c in candidates) {
        withExe.add('$c.exe');
      }
    }
    for (final c in [...candidates, ...withExe]) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// 从 manifest `process` 中查找声明（按 exe 名或 id），白名单 fail-closed。
  ///
  /// 返回 null 表示未声明。供 `process.run` 与 `process.start` 共用。
  ProcessDescriptor? _findDeclaredProcess(String exe) {
    for (final proc in widget.descriptor.process) {
      if (proc.exe == exe || proc.id == exe) return proc;
    }
    return null;
  }

  // ═══════ 常驻进程（process.start/stop/write/read） ═══════

  /// 启动常驻进程（`scope:"long"`），返回 `{ok:true}`。
  ///
  /// 白名单：只允许 manifest `process` 里声明且 `scope:"long"` 的进程。
  /// 启动后 stdout/stderr 经 `process:output` 事件实时推送给页面，
  /// 退出经 `process:exit` 事件推送。重复 start 已存在的进程返回 `{ok:true}`（幂等）。
  Future<Map<String, dynamic>> _startLongProcess(
      String exe, Map<String, dynamic> opts) async {
    final declared = _findDeclaredProcess(exe);
    if (declared == null) {
      throw Exception(
          '进程 "$exe" 未在 manifest 的 process 中声明，拒绝执行（fail-closed）');
    }
    if (declared.scope != 'long') {
      throw Exception(
          '进程 "$exe" scope="${declared.scope}"，不是常驻进程（需 scope:"long"）。'
          '一次性任务请用 platform.process.run');
    }

    final key = declared.id ?? declared.exe;
    if (_longProcesses.containsKey(key) && _longProcesses[key]!.isAlive) {
      return {'ok': true}; // 幂等：已在运行
    }

    final args = (opts['args'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final pluginDir = _pluginDir();
    if (pluginDir == null) {
      throw Exception('无法定位插件目录');
    }
    final exePath = _resolveExePath(pluginDir, declared.exe);
    if (exePath == null) {
      throw Exception('exe 不存在: ${p.join(pluginDir, declared.exe)}');
    }

    final session = _LongProcessSession(
      key: key,
      onOutput: (stream, line) {
        if (!mounted || !_initialized) return;
        final payload = jsonEncode(
            {'exe': key, 'stream': stream, 'line': line});
        _executeJs('window.__evgFireEvent("process:output", $payload)');
      },
      onExit: (code) {
        _longProcesses.remove(key);
        if (!mounted || !_initialized) return;
        final payload = jsonEncode({'exe': key, 'exitCode': code});
        _executeJs('window.__evgFireEvent("process:exit", $payload)');
      },
    );

    final runner = await sharedPluginRunner;
    final process = await runner.startLong(
      exePath,
      args,
      workingDirectory: pluginDir,
      runtime: declared.runtime,
    );
    await session.attach(process);
    _longProcesses[key] = session;
    return {'ok': true};
  }

  /// 向常驻进程 stdin 写数据，返回 `{ok:true}`。
  Future<Map<String, dynamic>> _writeLongProcess(
      String exe, String data) async {
    final declared = _findDeclaredProcess(exe);
    final key = declared?.id ?? declared?.exe ?? exe;
    final session = _longProcesses[key];
    if (session == null || !session.isAlive) {
      throw Exception('进程 "$exe" 未在运行，请先 process.start');
    }
    session.write(data);
    return {'ok': true};
  }

  /// 终止常驻进程，返回 `{ok:true}`。
  Future<Map<String, dynamic>> _stopLongProcess(String exe) async {
    final declared = _findDeclaredProcess(exe);
    final key = declared?.id ?? declared?.exe ?? exe;
    final session = _longProcesses.remove(key);
    if (session == null) return {'ok': true}; // 幂等：已不存在
    await session.stop();
    return {'ok': true};
  }

  /// 读常驻进程当前累积的 stdout。
  String _readLongProcess(String exe) {
    final declared = _findDeclaredProcess(exe);
    final key = declared?.id ?? declared?.exe ?? exe;
    final session = _longProcesses[key];
    if (session == null) return '';
    return session.stdoutBuffer;
  }

  // ═══════ core 服务 HTTP 转发 ═══════

  /// 委托共享 [forwardCoreHttp]（bridge_script.dart）——端口发现 + HTTP 转发。
  Future<dynamic> _httpForward(
    CoreService service,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) => forwardCoreHttp(service, method, path, body);

  // ═══════ UI ═══════

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

    return Scaffold(body: SafeArea(child: Webview(_controller)));
  }
}

/// 常驻进程会话 —— 管理一个 `scope:"long"` 进程的 stdio 双向流。
///
/// - stdout/stderr 逐行解析，经 [onOutput] 推送给页面（`process:output` 事件）。
/// - stdin 经 [write] 写入，支持交互式终端。
/// - 进程退出经 [onExit] 通知（`process:exit` 事件）。
/// - [stdoutBuffer] 累积 stdout，供 `process.read` 拉取。
class _LongProcessSession {
  _LongProcessSession({
    required this.key,
    required this.onOutput,
    required this.onExit,
  });

  /// 会话标识（manifest `process[].id` 或 `exe`）。
  final String key;

  /// 输出回调：`(stream: 'stdout'|'stderr', line)`。
  final void Function(String stream, String line) onOutput;

  /// 退出回调：`(exitCode)`。
  final void Function(int exitCode) onExit;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final StringBuffer _stdoutBuf = StringBuffer();
  bool _stopped = false;

  /// 进程是否仍在运行。
  bool get isAlive => _process != null && !_stopped;

  /// 当前累积的 stdout（供 `process.read`）。
  String get stdoutBuffer => _stdoutBuf.toString();

  /// 挂载进程并订阅 stdout/stderr/exit。
  Future<void> attach(Process process) async {
    _process = process;

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stdoutBuf.writeln(line);
      onOutput('stdout', line);
    });

    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      onOutput('stderr', line);
    });

    // 进程退出：取消订阅并通知（fire-and-forget，避免未捕获异常）。
    process.exitCode.then((code) {
      _stdoutSub?.cancel();
      _stderrSub?.cancel();
      _stdoutSub = null;
      _stderrSub = null;
      _process = null;
      _stopped = true;
      onExit(code);
    }).catchError((_) {
      _stopped = true;
      onExit(-1);
    });
  }

  /// 向进程 stdin 写入数据（供交互式终端）。
  void write(String data) {
    final process = _process;
    if (process == null || _stopped) return;
    try {
      process.stdin.write(data);
    } catch (_) {
      // stdin 已关闭（进程已退出），忽略。
    }
  }

  /// 终止进程（先 SIGTERM，超时 SIGKILL）。
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    final process = _process;
    _process = null;
    if (process == null) return;

    try {
      process.stdin.close();
    } catch (_) {}
    try {
      process.kill(ProcessSignal.sigterm);
      final exited = await process.exitCode
          .timeout(const Duration(seconds: 2))
          .then((_) => true)
          .catchError((_) => false);
      if (!exited) {
        process.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      // 进程已退出
    }
  }
}

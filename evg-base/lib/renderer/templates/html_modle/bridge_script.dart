/// 共享 bridge 生成器 —— HTML 插件 JS Bridge + Dart 侧转发/订阅基础设施。
///
/// Phase C 收敛：运行期插件（`html_modle_view`）、创作中心预览
/// （`preview_panel`）、导出后热注册（复用运行期）三处统一到本模块，
/// 消除历史双份 script 改一处漏一处的回归风险。
///
/// ## 本模块提供
/// - [buildBridgeScript]：生成统一的 bridge JS（含 `platform.data.*` /
///   `platform.ai.*` / `platform.api.call` / `platform.settings.*` /
///   `platform.theme.getColors` / `platform.emit` / `platform.on`）。
/// - [forwardCoreHttp]：按 [CoreApiDiscovery] 发现的端口转发 HTTP 请求到
///   对应 core 服务（Agent/Config/Data/Module/Theme/Core）。
/// - [DataSubscriptionPoller]：`data.subscribe` 的**事件驱动 + 轮询兜底**
///   （订阅 core `dataChangeEvents`，命中订阅源即拉取推 `data:changed`；
///   5s 轮询兜底、事件命中后跳过当轮），值变化判定为 JSON 快照比对。
///
/// 纯 Dart（仅依赖 dart:io / dart:convert / dart:async / core data），
/// 可独立单测。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:evergreen_base/core/data/data_diff.dart' show DataChangeEvent;
import 'core_api_discovery.dart';

// ═══════════════════════════ JS bridge 生成 ═══════════════════════════

/// 生成统一的 Evergreen HTML 插件 bridge JS。
///
/// 注入时机由调用方决定（服务端内联于文档最顶部 / document-created /
/// onPageStarted 幂等兜底），本脚本自身带 `__evgBridgeInjected` 幂等守卫。
///
/// ## 插件侧可用 API（Promise 风格）
/// - `platform.data.get(name)` / `list()` / `refresh(name)` /
///   `testConnectivity()` / `subscribe(name, fn)`
/// - `platform.data.refresh(name)`：契约③ 语义降级——等价于 `data.get` 的缓存优先读，
///   不再强制重抓（POST /data/types/:name/refresh 已停用）；真实刷新由数据中枢
///   后台调度（startAutoRefresh / refreshAllStale）维护，插件请用 `subscribe` 感知变化。
/// - `platform.ai.chat(prompt, [style])`（style ∈ explanatory/learning/concise/socratic）
/// - `platform.api.call(service, path, {method, body})` 通用 core 服务转发
/// - `platform.settings.get(key)` / `set(key, value)`
/// - `platform.storage.get(key)` / `set(key, value)` / `remove(key)` / `list()` /
///   `clear()` —— 模块私有存储（持久化到插件私有目录 `storage/storage.json`，
///   字符串语义；`get` 未知 key 返回 null，`list` 返回全量 `{key: value}` Map）
/// - `platform.theme.getColors()`
/// - `platform.emit(event, payload)` / `platform.on(event, fn)`
///
/// ## localStorage / sessionStorage polyfill（注入时接管）
/// 因 WebView origin 随机端口隔离 + 跨平台 WebView 存储不一致导致插件进度丢失，
/// 本脚本在 bridge 注入时**接管 `window.localStorage`**（同步内存 Map + 异步
/// write-through 落盘到插件私有存储），现有插件零改造恢复进度保存：
/// - 读（`getItem` / `length` / `key`）全走内存，同步返回、绝不阻塞 UI 线程；
/// - 写（`setItem` / `removeItem` / `clear`）同步更新内存后异步 `_call('storage.*')`
///   落盘；预载失败 / 落盘失败静默降级为「会话内有效」（仅内存）；
/// - `sessionStorage` 同 API、仅内存不落盘；不做 IndexedDB（交付边界）。
///
/// 双通道发送：Windows `chrome.webview.postMessage` / Android `evgBridge` JS 通道。
String buildBridgeScript() {
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
      list: function() { return _call('data.list', []); },
      // refresh(name)：契约③ 语义降级——等价于 data.get 的缓存优先读（不再强制重抓），
      // 真实刷新由数据中枢后台调度（startAutoRefresh/refreshAllStale）维护。
      refresh: function(name) { return _call('data.refresh', [name]); },
      testConnectivity: function() { return _call('data.testConnectivity', []); },
      subscribe: function(name, fn) {
        if (!_listeners['data:changed']) _listeners['data:changed'] = [];
        _listeners['data:changed'].push(fn);
        return _call('data.subscribe', [name]);
      },
    },
    ai: {
      // chat(prompt) 或 chat(prompt, style)；style ∈ explanatory/learning/concise/socratic
      chat: function(prompt, style) { return _call('ai.chat', [prompt, style]); },
    },
    api: {
      // 通用 core 服务调用：api.call('agent', '/agent/tools', {method:'GET'})
      // service ∈ agent/config/data/module/theme/core
      call: function(service, path, opts) {
        return _call('api.call', [service, path, opts || {}]);
      },
    },
    process: {
      // 运行本插件 manifest `process` 里声明的 exe（白名单内才允许，方案 A）。
      // run(exe, {args}) → Promise<{stdout, stderr, exitCode}>
      run: function(exe, opts) {
        return _call('process.run', [exe, opts || {}]);
      },
      // 常驻进程（scope:"long"）：启动后可持续读写 stdio，作交互式终端。
      // start(exe, {args}) → Promise<{ok:true}>（进程启动，输出经 process:output 事件推送）
      // write(exe, data)   → Promise<{ok:true}>（向进程 stdin 写数据）
      // stop(exe)          → Promise<{ok:true}>（终止进程）
      // read(exe)          → Promise<{stdout}>（读当前累积 stdout）
      start: function(exe, opts) {
        return _call('process.start', [exe, opts || {}]);
      },
      write: function(exe, data) {
        return _call('process.write', [exe, String(data == null ? '' : data)]);
      },
      stop: function(exe) {
        return _call('process.stop', [exe]);
      },
      read: function(exe) {
        return _call('process.read', [exe]);
      },
      // 监听常驻进程输出事件：onOutput(fn) → fn({exe, stream:'stdout'|'stderr', line})
      onOutput: function(fn) {
        if (!_listeners['process:output']) _listeners['process:output'] = [];
        _listeners['process:output'].push(fn);
      },
      // 监听进程退出事件：onExit(fn) → fn({exe, exitCode})
      onExit: function(fn) {
        if (!_listeners['process:exit']) _listeners['process:exit'] = [];
        _listeners['process:exit'].push(fn);
      },
    },
    settings: {
      get: function(key) { return _call('settings.get', [key]); },
      set: function(key, value) { return _call('settings.set', [key, value]); },
    },
    storage: {
      // 模块私有存储（持久化到插件私有目录 storage/storage.json，字符串语义）。
      // get(key) → string | null（未知 key 返回 null，storage.json 缺失不报错）；
      // list() → 全量 {key: value} Map（供 polyfill 预载 / 遍历）；
      // set/remove/clear 为异步落盘（write-through），写失败经 __evgReject 抛错。
      get: function(key) { return _call('storage.get', [key]); },
      set: function(key, value) { return _call('storage.set', [key, value]); },
      remove: function(key) { return _call('storage.remove', [key]); },
      list: function() { return _call('storage.list', []); },
      clear: function() { return _call('storage.clear', []); },
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

  // ═══════════════════════════════════════════════════════════════════════
  // localStorage / sessionStorage polyfill（bridge 注入时接管）
  //
  // 背景：WebView origin 随机端口隔离 + 跨平台 WebView 存储不一致，插件
  // localStorage 进度保存不可靠。此处用「同步内存 Map + 异步 write-through」
  // 接管 window.localStorage（并在原生 localStorage 不存在/不稳定的 WebView
  // 中保证可用）：
  //   - 读（getItem/length/key）全走内存，同步返回，绝不阻塞 UI 线程；
  //   - 写（setItem/removeItem/clear）同步更新内存，再异步 _call('storage.*')
  //     落盘到插件私有目录 storage/storage.json；
  //   - 注入时异步预载一次（storage.list）；预载失败（core 未就绪等）→ 内存
  //     为空但 API 照常工作；写仍尝试落盘，失败静默降级为「会话内有效」（仅
  //     内存，重启丢失）。
  // sessionStorage 同 API、仅内存不落盘（会话内有效）。不做 IndexedDB。
  // 原生引用保留到 window.__evgNativeLocalStorage 供调试。
  // ═══════════════════════════════════════════════════════════════════════
  var _nativeLocalStorage = null;
  try { _nativeLocalStorage = window.localStorage; } catch (e) { _nativeLocalStorage = null; }

  // 存储后端工厂：persist=true 走落盘 write-through（localStorage），
  // persist=false 仅内存（sessionStorage）。
  function _evgStorageBackend(persist) {
    var data = {};    // 同步内存态（读的唯一来源）
    var dirty = {};   // 预载期间被插件写入的 key（防预载响应覆盖新写）
    var cleared = false; // 预载期间 clear() 过 → 丢弃预载合并
    var loaded = false;  // 已发起预载

    function ensureLoaded() {
      if (loaded) return;
      loaded = true;
      if (!persist) return; // 仅内存后端：无需预载
      try {
        _call('storage.list', []).then(function(entries) {
          if (!entries || cleared) return;
          for (var k in entries) {
            if (!dirty[k] && !(k in data)) data[k] = entries[k];
          }
        }).catch(function() {
          // 预载失败（core 未就绪等）：内存保持为空，API 照常工作（会话内有效）。
        });
      } catch (e) { /* 同上：静默降级 */ }
    }

    // 异步 write-through：同步内存已更新，落盘失败静默降级（仅内存）。
    function flush(method, args) {
      try {
        _call(method, args).catch(function() {
          // 落盘失败：会话内有效（内存保留，重启丢失）。
        });
      } catch (e) { /* 同上 */ }
    }

    return {
      getItem: function(key) {
        ensureLoaded();
        key = String(key);
        return Object.prototype.hasOwnProperty.call(data, key) ? String(data[key]) : null;
      },
      setItem: function(key, value) {
        ensureLoaded();
        key = String(key);
        value = String(value);
        data[key] = value;
        dirty[key] = true;
        if (persist) flush('storage.set', [key, value]);
      },
      removeItem: function(key) {
        ensureLoaded();
        key = String(key);
        if (Object.prototype.hasOwnProperty.call(data, key)) {
          delete data[key];
          dirty[key] = true;
          if (persist) flush('storage.remove', [key]);
        }
      },
      clear: function() {
        ensureLoaded();
        data = {};
        cleared = true;
        if (persist) flush('storage.clear', []);
      },
      key: function(index) {
        ensureLoaded();
        var keys = Object.keys(data);
        return (typeof index === 'number' && index >= 0 && index < keys.length)
            ? keys[index] : null;
      },
      get length() {
        ensureLoaded();
        return Object.keys(data).length;
      },
    };
  }

  // 接管 window.localStorage / window.sessionStorage（幂等：重复注入不重复接管；
  // bridge 顶部 __evgBridgeInjected 已整体防重，__evgStoragePolyfilled 作为
  // polyfill 段落的独立守卫）。优先 defineProperty（Chromium 可重定义），
  // 失败退回直接赋值；极少数只读 accessor 引擎两者均失败时保持原生行为。
  if (!window.__evgStoragePolyfilled) {
    var _evgLocalStorage = _evgStorageBackend(true);
    var _evgSessionStorage = _evgStorageBackend(false);
    try {
      Object.defineProperty(window, 'localStorage', {
        value: _evgLocalStorage, configurable: true, writable: true,
      });
    } catch (e) {
      try { window.localStorage = _evgLocalStorage; } catch (e2) {}
    }
    try {
      Object.defineProperty(window, 'sessionStorage', {
        value: _evgSessionStorage, configurable: true, writable: true,
      });
    } catch (e) {
      try { window.sessionStorage = _evgSessionStorage; } catch (e2) {}
    }
    window.__evgNativeLocalStorage = _nativeLocalStorage;
    window.__evgStoragePolyfilled = true;
  }

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

// ═══════════════════════════ core 服务 HTTP 转发 ═══════════════════════════

/// 按 [CoreApiDiscovery] 发现的端口转发 HTTP 请求到对应 core 服务。
///
/// - 端口文件缺失 → 抛「服务未启动」；HTTP 层失败 → 抛带状态码的异常。
/// - 响应 JSON 反序列化返回（空 body 返回 null）。
/// - [discovery] 可注入（测试用）；缺省用全局单例 [coreApiDiscovery]。
Future<dynamic> forwardCoreHttp(
  CoreService service,
  String method,
  String path, [
  Map<String, dynamic>? body,
  CoreApiDiscovery? discovery,
]) async {
  final d = discovery ?? coreApiDiscovery;
  final port = d.portOf(service);
  if (port == null) {
    throw Exception('${service.id} 服务未启动（端口文件 ${service.portFile} 缺失）');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final uri = Uri.parse('http://127.0.0.1:$port$path');
    final req =
        await (method == 'GET' ? client.getUrl(uri) : client.postUrl(uri))
            .timeout(const Duration(seconds: 5));
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final raw = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    debugPrint(
      '[Bridge] api.$method $path → ${res.statusCode} (${raw.length}B)',
    );
    if (res.statusCode >= 400) {
      final snippet = raw.length > 300 ? '${raw.substring(0, 300)}…' : raw;
      throw Exception('HTTP ${res.statusCode}: $snippet');
    }
    if (raw.isEmpty) return null;
    return jsonDecode(raw);
  } finally {
    client.close(force: true);
  }
}

// ═══════════════════════════ 数据订阅轮询 ═══════════════════════════

/// `platform.data.subscribe` 的 Dart 侧实现：**事件驱动为主 + 轮询兜底**。
///
/// - 事件驱动：订阅 core [DataChangeEvent] 流（[DataChangeEvent.sourceName] 命中
///   已订阅集合时立即拉取并推 `data:changed`），由调用方注入 [dataChangeEvents]；
/// - 轮询兜底：事件驱动失效/漏帧时，周期轮询仍能收敛到最新值；事件命中后
///   下一轮轮询跳过（避免重复拉取）；
/// - 值变化判定仍为 JSON 快照比对，`data:changed` 事件载荷结构与既有轮询一致。
///
/// 与 widget 解耦：拉取 / 执行 JS / 事件流均为注入回调，可独立单测。
class DataSubscriptionPoller {
  DataSubscriptionPoller({
    required Future<dynamic> Function(String name) fetch,
    required Future<void> Function(String js) executeJs,
    this.interval = const Duration(seconds: 5),
    Stream<DataChangeEvent>? dataChangeEvents,
  })  : _fetch = fetch,
        _executeJs = executeJs {
    if (dataChangeEvents != null) {
      _changeEventsSub = dataChangeEvents.listen(_onDataChange);
    }
  }

  /// 拉取指定数据源（返回 null 表示未注册/暂无数据，跳过本轮）。
  final Future<dynamic> Function(String name) _fetch;

  /// 向页面执行 JS（Windows executeScript / Android runJavaScript）。
  final Future<void> Function(String js) _executeJs;

  /// 轮询间隔（可调；测试可缩短）。
  final Duration interval;

  final Map<String, Timer> _subscriptions = {};
  final Map<String, String> _subscribedValues = {};

  /// 事件驱动已刷新过的源：命中后下一轮轮询跳过（避免重复拉取）。
  final Set<String> _eventFresh = {};

  StreamSubscription<DataChangeEvent>? _changeEventsSub;

  /// 当前已订阅的数据源名。
  Set<String> get subscribedNames => _subscriptions.keys.toSet();

  /// 订阅 [name] 数据源（幂等：已订阅则忽略）。
  void subscribe(String name) {
    if (_subscriptions.containsKey(name)) return;
    _fetchAndPush(name); // 立即拉取一次（不等首个周期）
    _subscriptions[name] = Timer.periodic(interval, (_) => _poll(name));
    debugPrint('[Bridge] 数据订阅已启动: $name (事件驱动 + ${interval.inSeconds}s 轮询兜底)');
  }

  /// core 变更事件命中已订阅源 → 立即拉取并推 `data:changed`（事件驱动路径）。
  void _onDataChange(DataChangeEvent event) {
    final name = event.sourceName;
    if (!_subscriptions.containsKey(name)) return; // 未订阅该源：忽略
    _eventFresh.add(name);
    _fetchAndPush(name);
  }

  /// 周期轮询兜底：事件驱动刚命中过则跳过本轮（值已最新，避免重复拉取）。
  Future<void> _poll(String name) async {
    if (_eventFresh.remove(name)) return;
    await _fetchAndPush(name);
  }

  /// 拉取 [name] 并与上次快照比对；变化则推 `data:changed` 事件给页面。
  Future<void> _fetchAndPush(String name) async {
    try {
      final data = await _fetch(name);
      if (data == null) return; // 未注册/暂无数据：保留上次快照，下轮重试
      final snapshot = jsonEncode(data);
      final prev = _subscribedValues[name];
      _subscribedValues[name] = snapshot;
      if (prev == snapshot) return; // 无变化
      final payload = jsonEncode({'name': name, 'data': data});
      debugPrint('[Bridge] 数据变化推送: $name');
      await _executeJs('window.__evgFireEvent("data:changed", $payload)');
    } catch (e) {
      debugPrint('[Bridge] 订阅拉取 $name 失败: $e');
    }
  }

  /// 取消 core 事件流订阅、全部轮询订阅并清理快照（防泄漏）。
  void dispose() {
    _changeEventsSub?.cancel();
    _changeEventsSub = null;
    for (final t in _subscriptions.values) {
      t.cancel();
    }
    _subscriptions.clear();
    _subscribedValues.clear();
    _eventFresh.clear();
  }
}

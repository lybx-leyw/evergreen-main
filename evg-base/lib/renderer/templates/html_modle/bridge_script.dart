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
/// - [DataSubscriptionPoller]：`data.subscribe` 的 5s 轮询 + JSON 快照比对，
///   值变化推送 `data:changed` 事件给页面。
///
/// 纯 Dart（仅依赖 dart:io / dart:convert / dart:async / core data），
/// 可独立单测。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
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
/// - `platform.ai.chat(prompt, [style])`（style ∈ explanatory/learning/concise/socratic）
/// - `platform.api.call(service, path, {method, body})` 通用 core 服务转发
/// - `platform.settings.get(key)` / `set(key, value)`
/// - `platform.theme.getColors()`
/// - `platform.emit(event, payload)` / `platform.on(event, fn)`
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
    final req = await (method == 'GET' ? client.getUrl(uri) : client.postUrl(uri))
        .timeout(const Duration(seconds: 5));
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final raw =
        await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    debugPrint('[Bridge] api.$method $path → ${res.statusCode} (${raw.length}B)');
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

/// `platform.data.subscribe` 的 Dart 侧实现：5s 轮询拉取 + JSON 快照比对，
/// 值变化时通过 [executeJs] 推送 `data:changed` 事件给页面。
///
/// 与 widget 解耦：拉取与执行 JS 均为注入回调，纯 Dart 可单测。
class DataSubscriptionPoller {
  DataSubscriptionPoller({
    required Future<dynamic> Function(String name) fetch,
    required Future<void> Function(String js) executeJs,
    this.interval = const Duration(seconds: 5),
  })  : _fetch = fetch,
        _executeJs = executeJs;

  /// 拉取指定数据源（返回 null 表示未注册/暂无数据，跳过本轮）。
  final Future<dynamic> Function(String name) _fetch;

  /// 向页面执行 JS（Windows executeScript / Android runJavaScript）。
  final Future<void> Function(String js) _executeJs;

  /// 轮询间隔（测试可缩短）。
  final Duration interval;

  final Map<String, Timer> _subscriptions = {};
  final Map<String, String> _subscribedValues = {};

  /// 当前已订阅的数据源名。
  Set<String> get subscribedNames => _subscriptions.keys.toSet();

  /// 订阅 [name] 数据源（幂等：已订阅则忽略）。
  void subscribe(String name) {
    if (_subscriptions.containsKey(name)) return;
    _poll(name);
    _subscriptions[name] =
        Timer.periodic(interval, (_) => _poll(name));
    debugPrint('[Bridge] 数据订阅已启动: $name (每 ${interval.inSeconds}s)');
  }

  /// 拉取 [name] 并与上次快照比对；变化则推 `data:changed` 事件给页面。
  Future<void> _poll(String name) async {
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
      debugPrint('[Bridge] 订阅轮询 $name 失败: $e');
    }
  }

  /// 取消全部订阅并清理快照。
  void dispose() {
    for (final t in _subscriptions.values) {
      t.cancel();
    }
    _subscriptions.clear();
    _subscribedValues.clear();
  }
}

/// 全局 scraper 能力注册表——DSH 双向 RPC 的核心接缝。
///
/// B 方案：DSH 常驻进程通过 HTTP RPC 驱动平台真实的 scraper WebView。
/// 但 scraper WebView 是 UI 组件，随插件挂载/卸载。本注册表维护「当前活跃的
/// scraper 能力」引用：
/// - scraper 插件（WebView）挂载时 → [registerBridge] 注册 bridge + workflow；
/// - 卸载时 → [unregisterBridge] 注销；
/// - DSH RPC 到达时，[ScraperBridgeServer] 通过 [activeBridge] 拿到当前能力执行。
///
/// 全局单例（进程级），不随插件切换销毁——与「DSH 连接 app 不关则不断」一致。
library;

import 'dart:async';

import 'package:evergreen_base/core/agent/tool.dart';

import 'web/scraper_webview.dart';
import 'workflow/scraper_workflow.dart';
import 'scraper_bridge_server.dart';

/// 全局 scraper 能力注册表（进程级单例）。
class ScraperBridgeRegistry {
  ScraperBridgeRegistry._();

  static final ScraperBridgeRegistry instance = ScraperBridgeRegistry._();

  ScraperWebViewBridge? _bridge;
  ScraperWorkflow? _workflow;
  Registry? _toolRegistry;

  /// 常驻 ScraperBridgeServer 引用（app_bootstrap 启动后赋值，
  /// UI 层通过它注入 activateScraper 自动切换回调）。
  ScraperBridgeServer? server;

  /// 是否已有活跃的 scraper 能力（WebView 已挂载且就绪）。
  bool get isActive => _bridge != null && (_bridge?.ready ?? false);

  /// 当前活跃的 bridge（未挂载/未就绪返回 null）。
  ScraperWebViewBridge? get activeBridge => isActive ? _bridge : null;

  /// 当前活跃的 workflow（日志来源，未挂载返回 null）。
  ScraperWorkflow? get activeWorkflow => isActive ? _workflow : null;

  /// 当前活跃的官方工具 Registry（ScraperAIPanel 的 AgentAssembly.registry）。
  ///
  /// DSH 的工具 RPC 经 [ScraperBridgeServer] 转发到本 registry 的 `call()`，
  /// 复用官方工具链真实执行逻辑（run_python_scraper / export_and_register 等）。
  Registry? get toolRegistry => isActive ? _toolRegistry : null;

  /// scraper WebView 挂载时注册其能力（bridge + workflow + 工具 registry）。
  void registerBridge(
    ScraperWebViewBridge bridge,
    ScraperWorkflow workflow, {
    Registry? toolRegistry,
  }) {
    _bridge = bridge;
    _workflow = workflow;
    if (toolRegistry != null) _toolRegistry = toolRegistry;
  }

  /// 单独更新活跃工具 Registry（ScraperAIPanel 的 Agent 异步初始化完成后调用）。
  void registerToolRegistry(Registry registry) {
    _toolRegistry = registry;
  }

  /// scraper WebView 卸载时注销。
  void unregisterBridge(ScraperWebViewBridge bridge) {
    if (identical(_bridge, bridge)) {
      _bridge = null;
      _workflow = null;
      _toolRegistry = null;
    }
  }

  /// 等待 scraper 能力就绪（自动切换后 WebView 初始化完成的短暂等待）。
  Future<bool> waitReady({Duration timeout = const Duration(seconds: 5)}) async {
    if (isActive) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (isActive) return true;
    }
    return false;
  }
}

/// 便捷单例访问。
final ScraperBridgeRegistry scraperBridgeRegistry = ScraperBridgeRegistry.instance;

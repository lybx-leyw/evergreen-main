/// 爬虫脚本生成器主视图——#64 特制组件。
///
/// 所见即所得爬虫脚本生成器（WYSIWYG Web Scraper Script Generator）
///
/// 界面采用 dock 布局（左右分栏）：
/// - 左侧：内嵌 WebView（flutter_inappwebview）浏览目标网站
/// - 右侧上：请求日志面板（实时展示捕获的 HTTP 请求）
/// - 右侧下：AI 工作区（隔离 Agent + 专用工具）
///
/// 工作流：
/// 1. 用户在 WebView 中浏览目标网站 → 后台自动捕获 HTTP 请求
/// 2. 点击"分析日志" → AI 分析请求、提取凭证、生成爬虫
/// 3. AI 自动执行并调试爬虫代码（最多 5 轮）
/// 4. 成功后支持导出 .py 或 .exe
library scraper_generator_view;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';

import 'scraper_workflow.dart';
import 'scraper_webview.dart';
import 'request_log_panel.dart';
import 'scraper_ai_panel.dart';
import 'scraper_terminal.dart';

/// 爬虫脚本生成器组件视图。
///
/// 在 [composite_view.dart] 的 SlotDispatch 中注册为 `'scraper-generator'` 类型。
class ScraperGeneratorView extends StatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor config;
  final String slotKey;
  final PageEventBus? pageEventBus;

  /// Optional: override the initial URL (set by wizard from step ①).
  final String? initialUrl;

  const ScraperGeneratorView({
    super.key,
    required this.descriptor,
    required this.config,
    required this.slotKey,
    this.pageEventBus,
    this.initialUrl,
  });

  @override
  State<ScraperGeneratorView> createState() => ScraperGeneratorViewState();
}

class ScraperGeneratorViewState extends State<ScraperGeneratorView> {
  late final ScraperWorkflow _workflow;
  final GlobalKey<ScraperAIPanelState> _aiPanelKey = GlobalKey();

  /// WebView 初始化完成门控——命名弹窗等它放行后再弹出，
  /// 避免 Webview 在弹窗覆盖期间才挂载 → WebView2 纹理丢帧 → 黑屏。
  final Completer<void> _webViewReady = Completer<void>();

  /// 命名弹窗关闭后 +1，强制 Webview 重挂载恢复纹理帧。
  int _refreshTick = 0;

  /// 竖版窄屏：当前激活的 Tab（0=浏览 1=日志 2=终端 3=AI）
  int _narrowTab = 0;

  /// Public access to the workflow for external consumers (e.g., wizard
  /// reads captured logs after step ②).
  ScraperWorkflow get workflow => _workflow;

  late final String _moduleId;
  late final String _workspaceDir;
  late final String _projectRoot;
  late final String _initialUrl;

  @override
  void initState() {
    super.initState();
    _workflow = ScraperWorkflow();
    // 工作流状态变更时触发重建
    _workflow.onChanged = () {
      if (mounted) setState(() {});
    };

    _moduleId = widget.descriptor.id;
    _workspaceDir = greenixWorkspaceDir('${_moduleId}/scraper_output');
    Directory(_workspaceDir).createSync(recursive: true);

    // 项目根目录——向上找 pubspec.yaml 所在目录
    _projectRoot = _findProjectRoot();

    // 初始 URL（wizard 显式传入优先 > config > 默认百度）
    _initialUrl = widget.initialUrl ??
        widget.config.config['initialUrl'] as String? ??
        'https://www.baidu.com';

    // 自动开始抓包
    _workflow.startCapturing();

    debugPrint(
        '[ScraperGeneratorView] 初始化: $_moduleId, workspace=$_workspaceDir');
  }

  @override
  void dispose() {
    if (!_webViewReady.isCompleted) _webViewReady.complete();
    _workflow.dispose();
    super.dispose();
  }

  String _findProjectRoot() {
    var dir = Directory.current;
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return Directory.current.path;
  }

  /// WebView 初始化完成（首帧绘制）——放行命名弹窗门控。
  void _onWebViewInitialized() {
    if (!_webViewReady.isCompleted) _webViewReady.complete();
  }

  /// 命名弹窗关闭（确认或跳过）——强制 Webview 重挂载，
  /// 恢复弹窗覆盖期间可能丢失的 WebView2 纹理帧。
  void _onFirstNamingDone() {
    if (!mounted) return;
    setState(() => _refreshTick++);
    debugPrint(
        '[ScraperGeneratorView] 命名弹窗关闭，WebView 表面重同步 (tick=$_refreshTick)');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;

              // 左右分栏 —— 左侧 60% WebView + 终端 / 右侧 40% 面板
              // 窄屏（<500px）自动切换为上下布局
              final isNarrow = totalWidth < 500;

              final terminalHeight = constraints.maxHeight * 0.28;

              if (isNarrow) {
                // 竖版窄屏：Tab 切换 + 全宽渲染（保持各面板原有风格）。
                // IndexedStack 保证切换 Tab 不销毁面板——WebView 不重新加载、
                // AI 会话/终端日志/请求列表状态全部保留。
                return Column(
                  children: [
                    _buildNarrowTabBar(),
                    Expanded(
                      child: IndexedStack(
                        index: _narrowTab,
                        children: [
                          // 0 浏览：WebView 全高
                          ScraperWebView(
                            initialUrl: _initialUrl,
                            refreshTick: _refreshTick,
                            onInitialized: _onWebViewInitialized,
                            onRequestCaptured: (log) {
                              _workflow.addLog(log);
                            },
                          ),
                          // 1 日志
                          RequestLogPanel(
                            workflow: _workflow,
                            onAnalyze: () {
                              _aiPanelKey.currentState?.triggerAnalyze();
                            },
                          ),
                          // 2 终端
                          ScraperTerminal(
                            workflow: _workflow,
                            workspaceDir: _workspaceDir,
                            resolvePython: () => resolvePythonExe(),
                          ),
                          // 3 AI
                          ScraperAIPanel(
                            key: _aiPanelKey,
                            workflow: _workflow,
                            moduleId: _moduleId,
                            slotKey: widget.slotKey,
                            workspaceDir: _workspaceDir,
                            projectRoot: _projectRoot,
                            startupGate: _webViewReady.future,
                            onFirstNamingDone: _onFirstNamingDone,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // 宽屏：左右分栏
              final leftWidth = totalWidth * 0.6;
              final rightWidth = totalWidth - leftWidth - 4; // 4 = 分割线

              return Row(
                children: [
                  // ── 左侧：WebView（上）+ 终端（下）──
                  SizedBox(
                    width: leftWidth,
                    child: Column(
                      children: [
                        // WebView —— 上半部分
                        Expanded(
                          child: ScraperWebView(
                            initialUrl: _initialUrl,
                            refreshTick: _refreshTick,
                            onInitialized: _onWebViewInitialized,
                            onRequestCaptured: (log) {
                              _workflow.addLog(log);
                            },
                          ),
                        ),
                        // 终端输出 —— 左下角
                        SizedBox(
                          height: terminalHeight.clamp(120, 250),
                          child: ScraperTerminal(
                            workflow: _workflow,
                            workspaceDir: _workspaceDir,
                            resolvePython: () => resolvePythonExe(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── 分割线 ──
                  _buildDivider(context),
                  // ── 右侧面板 ──
                  SizedBox(
                    width: rightWidth.clamp(200, double.infinity),
                    child: Column(
                      children: [
                        // 请求日志面板（上半部分 35%）
                        Expanded(
                          flex: 35,
                          child: RequestLogPanel(
                            workflow: _workflow,
                            onAnalyze: () {
                              _aiPanelKey.currentState?.triggerAnalyze();
                            },
                          ),
                        ),
                        _buildDivider(context, horizontal: true),
                        // AI 工作区（下半部分 65%）
                        Expanded(
                          flex: 65,
                          child: ScraperAIPanel(
                            key: _aiPanelKey,
                            workflow: _workflow,
                            moduleId: _moduleId,
                            slotKey: widget.slotKey,
                            workspaceDir: _workspaceDir,
                            projectRoot: _projectRoot,
                            startupGate: _webViewReady.future,
                            onFirstNamingDone: _onFirstNamingDone,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // ── 底部状态栏 ──
        _buildStatusBar(context),
      ],
    );
  }

  // ── 竖版窄屏 Tab 导航 ──

  /// 竖版 Tab 顺序：浏览 / 日志 / 终端 / AI。
  static const _narrowTabs = <(IconData, String)>[
    (Icons.travel_explore, '浏览'),
    (Icons.http_rounded, '日志'),
    (Icons.terminal, '终端'),
    (Icons.smart_toy_rounded, 'AI'),
  ];

  Widget _buildNarrowTabBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border:
            Border(bottom: BorderSide(color: scheme.outlineVariant, width: 0.5)),
      ),
      child: Row(children: [
        for (var i = 0; i < _narrowTabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(child: _buildNarrowTabItem(i)),
        ],
      ]),
    );
  }

  Widget _buildNarrowTabItem(int index) {
    final (icon, label) = _narrowTabs[index];
    final active = _narrowTab == index;
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: () => setState(() => _narrowTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : null)),
        ]),
      ),
    );
  }

  Widget _buildDivider(BuildContext context, {bool horizontal = false}) {
    final theme = Theme.of(context);
    return Container(
      width: horizontal ? double.infinity : 1,
      height: horizontal ? 1 : double.infinity,
      color: theme.dividerColor,
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final theme = Theme.of(context);
    final phase = _workflow.phase;
    final phaseLabel = _phaseLabel(phase);
    final phaseIcon = _phaseIcon(phase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 阶段标识
          Icon(phaseIcon, size: 12, color: _phaseColor(phase)),
          const SizedBox(width: 4),
          Text(
            phaseLabel,
            style: TextStyle(
              fontSize: 10,
              color: _phaseColor(phase),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // 日志计数
          Text(
            '📋 ${_workflow.logs.length} 条请求',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          // 调试轮数
          if (_workflow.debugCount > 0)
            Text(
              '🔧 调试 $_debugPhase/${ScraperWorkflow.maxDebugRounds}',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const Spacer(),
          // 重置按钮
          GestureDetector(
            onTap: () {
              _workflow.reset();
              _aiPanelKey.currentState?.resetAll();
            },
            child: Text(
              '🔄 重置',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(ScraperPhase p) => switch (p) {
        ScraperPhase.idle => '待机',
        ScraperPhase.capturing => '抓包中',
        ScraperPhase.analyzing => '分析中',
        ScraperPhase.questioning => '追问中',
        ScraperPhase.generating => '生成中',
        ScraperPhase.running => '运行中',
        ScraperPhase.debugging => '调试中',
        ScraperPhase.done => '✅ 完成',
        ScraperPhase.failed => '❌ 失败',
      };

  IconData _phaseIcon(ScraperPhase p) => switch (p) {
        ScraperPhase.idle => Icons.pause_circle_outline,
        ScraperPhase.capturing => Icons.wifi_find_rounded,
        ScraperPhase.analyzing => Icons.analytics_rounded,
        ScraperPhase.questioning => Icons.help_outline_rounded,
        ScraperPhase.generating => Icons.code_rounded,
        ScraperPhase.running => Icons.play_circle_outline,
        ScraperPhase.debugging => Icons.bug_report_rounded,
        ScraperPhase.done => Icons.check_circle_rounded,
        ScraperPhase.failed => Icons.error_rounded,
      };

  Color _phaseColor(ScraperPhase p) => switch (p) {
        ScraperPhase.capturing => Colors.green,
        ScraperPhase.running ||
        ScraperPhase.analyzing ||
        ScraperPhase.generating ||
        ScraperPhase.debugging =>
          Colors.orange,
        ScraperPhase.done => const Color(0xFF52C41A),
        ScraperPhase.failed => Colors.red,
        _ => Colors.grey,
      };

  String get _debugPhase =>
      _workflow.debugCount > ScraperWorkflow.maxDebugRounds
          ? '${ScraperWorkflow.maxDebugRounds}+'
          : '${_workflow.debugCount}';
}

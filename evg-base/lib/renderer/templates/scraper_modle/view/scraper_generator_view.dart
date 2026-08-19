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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';

import '../workflow/scraper_workflow.dart';
import '../workflow/scraper_workflow_stepper.dart';
import '../workflow/scraper_workflow_graph.dart';
import '../explore/explore_workflow.dart';
import '../explore/explore_panel.dart';
import '../board/scraper_board.dart';
import '../board/data_source_binding.dart';
import '../web/scraper_webview.dart';
import '../scraper_bridge_registry.dart';
import 'request_log_panel.dart';
import '../agent/scraper_ai_panel.dart';
import 'scraper_terminal.dart';
import 'scraper_view_switch.dart';
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_view.dart';

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

  /// 画板模式（Phase 4 · A23）：定向 capture / 探索 explore。
  final ScraperBoardMode mode;

  /// 画板 id（Phase 4：探索会话按画板隔离，A21）。
  final String? boardId;

  const ScraperGeneratorView({
    super.key,
    required this.descriptor,
    required this.config,
    required this.slotKey,
    this.pageEventBus,
    this.initialUrl,
    this.mode = ScraperBoardMode.capture,
    this.boardId,
  });

  @override
  State<ScraperGeneratorView> createState() => ScraperGeneratorViewState();
}

class ScraperGeneratorViewState extends State<ScraperGeneratorView> {
  late final ScraperWorkflow _workflow;
  final GlobalKey<ScraperAIPanelState> _aiPanelKey = GlobalKey();

  /// Phase 4：探索模式工作流（D9 与定向并列的第二个状态机）。
  late final ExploreWorkflow _exploreWorkflow = ExploreWorkflow();

  /// Phase 4：浏览器 JS/导航执行通道（WebView 填充，探索工具消费）。
  final ScraperWebViewBridge _webBridge = ScraperWebViewBridge();

  bool get _isExplore => widget.mode == ScraperBoardMode.explore;

  /// WebView 表面重挂载计数（A18：重抓确认后 +1，强制 WebView 重挂载恢复纹理帧）。
  int _refreshTick = 0;

  /// WebView 是否被锁定（A18：日志快照冻结后锁定，重抓时解锁）。
  bool _webViewLocked = false;

  /// 竖版窄屏：当前激活的 Tab（0=浏览 1=日志 2=终端 3=AI）
  int _narrowTab = 0;

  /// 主视图模式（Phase 2 · B1：工作区 / workflow 流程图 / trace 占位）。
  ScraperMainView _view = ScraperMainView.workspace;

  // ── 断点续作（重启恢复工作流/会话，不重走流程） ──

  /// 画板状态防抖保存计时器。
  Timer? _saveTimer;

  /// 恢复的产物根名/插件目录（数据源建板等场景由容器写入）。
  String? _resumeDataName;
  String? _resumePluginDir;

  /// 恢复后一次性发送给 AI 的续作 prompt（数据源建板注入）。
  String? _resumePrompt;

  /// 画板绑定数据源 JSON（向画板 AI 告知数据状态）。
  String? _boundSourcesJson;

  /// 画板专属目录（工作流/会话/产物引用，A21 沙盒）。
  String get _boardDir =>
      p.join(_workspaceDir, 'boards', widget.boardId ?? 'default');

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
    // DSH 双向 RPC（B 方案）：把本画板的 WebView bridge + workflow 注册给
    // 全局 registry，供常驻 ScraperBridgeServer 驱动（DSH 操作 WebView）。
    // 注意：isActive 依赖 bridge.ready（WebView 初始化完成才 true），
    // 因此这里注册后，未就绪时 DSH RPC 会得到「未激活」——正确。
    scraperBridgeRegistry.registerBridge(_webBridge, _workflow);
    // 工作流状态变更时触发重建 + 防抖落盘（断点续作）
    _workflow.onChanged = () {
      if (mounted) setState(() {});
      _scheduleSave();
    };
    // Phase 4：探索工作流状态变更同样触发重建（ExplorePanel/状态栏消费）
    _exploreWorkflow.onChanged = () {
      if (mounted) setState(() {});
      _scheduleSave();
    };
    // A18：快照冻结 → 锁定 WebView
    _workflow.onWebViewLock = () {
      if (!mounted) return;
      setState(() => _webViewLocked = true);
      debugPrint('[ScraperGeneratorView] 🔒 WebView 已锁定（快照冻结）');
    };
    // A18：重抓确认 → 回首页解锁重启抓取
    _workflow.onRestartCapture = () {
      if (!mounted) return;
      setState(() {
        _webViewLocked = false;
        _refreshTick++; // 强制 WebView 重挂载
      });
      debugPrint('[ScraperGeneratorView] 🔓 WebView 解锁，重启抓取');
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

    // ── 断点续作：恢复上次画板状态（工作流/产物名/续作 prompt） ──
    _restoreBoardState();

    // 恢复出非 idle 工作流 → 断点续作；否则全新画板自动开始抓包
    if (_workflow.phase == ScraperPhase.idle && !_workflow.snapshotFrozen) {
      _workflow.startCapturing();
    } else {
      _webViewLocked = _workflow.snapshotFrozen;
      debugPrint(
          '[ScraperGeneratorView] ♻ 断点续作: phase=${_workflow.phase.name}');
    }

    debugPrint(
        '[ScraperGeneratorView] 初始化: $_moduleId, workspace=$_workspaceDir');
  }

  /// 从画板目录恢复工作流快照 + 产物名 + 续作 prompt + 绑定数据源。
  void _restoreBoardState() {
    try {
      final dir = Directory(_boardDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final wfFile = File(p.join(_boardDir, 'workflow.json'));
      if (wfFile.existsSync()) {
        final data =
            jsonDecode(wfFile.readAsStringSync()) as Map<String, dynamic>;
        final wfJson = data['workflow'] as Map<String, dynamic>?;
        if (wfJson != null) _workflow.restoreFromJson(wfJson);
        _resumeDataName = data['dataName'] as String?;
        _resumePluginDir = data['pluginDir'] as String?;
      }

      final exFile = File(p.join(_boardDir, 'explore_workflow.json'));
      if (exFile.existsSync()) {
        _exploreWorkflow.restoreFromJson(
            jsonDecode(exFile.readAsStringSync()) as Map<String, dynamic>);
      }

      final promptFile = File(p.join(_boardDir, 'resume_prompt.txt'));
      if (promptFile.existsSync()) {
        final v = promptFile.readAsStringSync().trim();
        if (v.isNotEmpty) _resumePrompt = v;
      }

      final boundFile = File(p.join(_boardDir, 'bound_sources.json'));
      if (boundFile.existsSync()) {
        final v = boundFile.readAsStringSync().trim();
        if (v.isNotEmpty) {
          _boundSourcesJson = v;
        } else {
          // 空文件 → 兜底扫描
          _boundSourcesJson = _scanBoundSourcesFallback();
        }
      } else {
        // D3 配套：bound_sources.json 缺失时用 manifest 溯源字段动态扫描，
        // 探索创建的老画板也能向 AI 告知数据状态。
        _boundSourcesJson = _scanBoundSourcesFallback();
      }
    } catch (e) {
      debugPrint('[ScraperGeneratorView] ⚠ 恢复画板状态失败: $e');
    }
  }

  /// D3 配套兜底：bound_sources.json 缺失/为空时，用
  /// [scanDataSourcePlugins] 按 boardId（创建画板）过滤生成绑定数据源摘要。
  String? _scanBoundSourcesFallback() {
    try {
      final boardId = widget.boardId;
      if (boardId == null || boardId.isEmpty) return null;
      final list = scanDataSourcePlugins()
          .where((ds) => ds.boardId == boardId)
          .map((ds) => ds.toSummaryJson())
          .toList();
      if (list.isEmpty) return null;
      return jsonEncode(list);
    } catch (e) {
      debugPrint('[ScraperGeneratorView] ⚠ 兜底扫描绑定数据源失败: $e');
      return null;
    }
  }

  /// 防抖保存画板状态（workflow.json + explore_workflow.json）。
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveBoardStateNow);
  }

  void _saveBoardStateNow() {
    try {
      final dir = Directory(_boardDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final panel = _aiPanelKey.currentState;
      final payload = <String, dynamic>{
        'workflow': _workflow.toJson(),
        if (panel?.dataName != null) 'dataName': panel?.dataName,
        if (panel?.pluginDir != null) 'pluginDir': panel?.pluginDir,
      };
      File(p.join(_boardDir, 'workflow.json'))
          .writeAsStringSync(jsonEncode(payload));
      File(p.join(_boardDir, 'explore_workflow.json'))
          .writeAsStringSync(jsonEncode(_exploreWorkflow.toJson()));
    } catch (e) {
      debugPrint('[ScraperGeneratorView] ⚠ 保存画板状态失败: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveBoardStateNow();
    scraperBridgeRegistry.unregisterBridge(_webBridge);
    _workflow.dispose();
    _exploreWorkflow.dispose();
    super.dispose();
  }

  String _findProjectRoot() {
    // 安卓：进程 CWD=/ 且无 pubspec.yaml，greenix 根 = 插件目录的父级
    //（与 AppBootstrap._stepGreenixPaths 一致：.config_port 写在这里）。
    // 若按桌面逻辑返回 '/'，SaveCredentialTool 等会去读 /.config_port → 找不到。
    if (Platform.isAndroid) {
      return p.dirname(androidPluginsDir);
    }
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

  /// 重抓确认（A18）：确认框 → 同意后回首页解锁重启抓取。
  Future<void> _requestRestartCapture() async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新抓取？'),
        content: const Text('将清空当前日志快照，浏览器回到首页并重新开始抓取。'
            '请重新完成目标操作后再点「确认操作完毕」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新抓取'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // 通知 AI 面板重置会话状态，再重启 workflow
      _aiPanelKey.currentState?.onRestartCaptureConfirmed();
      _workflow.restartCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── 视图切换栏（Phase 2 · B1 + Phase 3 轨迹）──
        ScraperViewSwitch(
          current: _view,
          onChanged: (v) => setState(() => _view = v),
          traceEnabled: true, // Phase 3：轨迹视图可用（C2 随时切换进出）
        ),
        // ── 非 workflow 视图：顶部常驻紧凑步骤条（用户 UI 决策）──
        if (_view != ScraperMainView.workflow)
          ScraperWorkflowStepper(workflow: _workflow, compact: true),
        // ── 主视图区：IndexedStack 保状态（C2：切换不销毁 AI 面板/WebView）──
        Expanded(
          child: IndexedStack(
            index: _viewIndex(_view),
            children: [
              // 0 工作区（含 WebView / 终端 / AI 面板——始终保活）
              _buildWorkspace(context),
              // 1 workflow 流程图
              ScraperWorkflowGraph(workflow: _workflow),
              // 2 轨迹（Phase 3）：消费 AI 面板的 Trace 记录器
              _TraceSlot(aiPanelKey: _aiPanelKey),
            ],
          ),
        ),
        // ── 底部状态栏 ──
        if (_view != ScraperMainView.workflow) _buildStatusBar(context),
      ],
    );
  }

  /// ScraperMainView → IndexedStack index（与枚举顺序解耦，显式映射）。
  static int _viewIndex(ScraperMainView v) {
    switch (v) {
      case ScraperMainView.workspace:
        return 0;
      case ScraperMainView.workflow:
        return 1;
      case ScraperMainView.trace:
        return 2;
    }
  }

  /// 主工作区（现有 dock 布局，含窄屏适配）。
  Widget _buildWorkspace(BuildContext context) {
    return LayoutBuilder(
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
                      locked: _webViewLocked,
                      onRestartCapture: _requestRestartCapture,
                      bridge: _webBridge,
                      onRequestCaptured: (log) {
                        if (!_webViewLocked) _workflow.addLog(log);
                      },
                    ),
                    // 1 日志
                    RequestLogPanel(
                      workflow: _workflow,
                      // 探索模式没有"分析日志"流程（不同工作流，D9）
                      onAnalyze: _isExplore
                          ? null
                          : () {
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
                      mode: widget.mode,
                      boardId: widget.boardId,
                      exploreWorkflow: _exploreWorkflow,
                      webBridge: _webBridge,
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
                            locked: _webViewLocked,
                            onRestartCapture: _requestRestartCapture,
                            bridge: _webBridge,
                            onRequestCaptured: (log) {
                              if (!_webViewLocked) _workflow.addLog(log);
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
                        // 上半部分 35%：探索模式 → 探索进度面板；定向模式 → 请求日志面板
                        Expanded(
                          flex: 35,
                          child: _isExplore
                              ? ExplorePanel(
                                  exploreWorkflow: _exploreWorkflow,
                                  onStartExplore: () async =>
                                      _aiPanelKey.currentState?.startExplore(),
                                  onReselectSources: () =>
                                      _aiPanelKey.currentState
                                          ?.reopenSourcePicker(),
                                )
                              : RequestLogPanel(
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
                            mode: widget.mode,
                            boardId: widget.boardId,
                            exploreWorkflow: _exploreWorkflow,
                            webBridge: _webBridge,
                            resumeDataName: _resumeDataName,
                            resumePluginDir: _resumePluginDir,
                            resumePrompt: _resumePrompt,
                            boundSourcesJson: _boundSourcesJson,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
        },
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
    final isExplore = _isExplore;
    final phaseLabel =
        isExplore ? _explorePhaseLabel(_exploreWorkflow.phase) : _phaseLabel(phase);
    final phaseIcon =
        isExplore ? _explorePhaseIcon(_exploreWorkflow.phase) : _phaseIcon(phase);
    final phaseColor = isExplore
        ? _explorePhaseColor(_exploreWorkflow.phase, theme.colorScheme)
        : _phaseColor(phase, theme.colorScheme);

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
          Icon(phaseIcon, size: 12, color: phaseColor),
          const SizedBox(width: 4),
          Text(
            phaseLabel,
            style: TextStyle(
              fontSize: 10,
              color: phaseColor,
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
          // Phase 4：探索计数（页数/请求/同域）
          if (isExplore) ...[
            Text(
              '🧭 ${_exploreWorkflow.uniquePages}/${_exploreWorkflow.limits.maxPages} 页 · '
              '${_exploreWorkflow.requestsCaptured}/${_exploreWorkflow.limits.maxRequests} 请求'
              '${_exploreWorkflow.baseHost.isNotEmpty ? ' · ${_exploreWorkflow.baseHost}' : ''}',
              style: TextStyle(
                fontSize: 10,
                color: _exploreWorkflow.phase == ExplorePhase.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 调试轮次（A15：连续失败计数；3 轮后 warning）
          if (_workflow.debugCount > 0)
            Text(
              _workflow.warningSent3
                  ? '🔧 连续失败 ${_workflow.consecutiveFailures} 轮 ⚠️'
                  : '🔧 调试 ${_workflow.consecutiveFailures}/'
                      '${ScraperWorkflow.debugWarningThreshold} 轮',
              style: TextStyle(
                fontSize: 10,
                color: _workflow.warningSent3
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 8),
          // refining 轮次（A19：仅展示）
          if (_workflow.refineCount > 0)
            Text(
              '🔄 优化第 ${_workflow.refineCount} 轮',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.primary,
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

  /// 阶段色——从全局 colorScheme 派生（主题规约：不硬编码）。
  Color _phaseColor(ScraperPhase p, ColorScheme scheme) => switch (p) {
        ScraperPhase.capturing => scheme.tertiary,
        ScraperPhase.running ||
        ScraperPhase.analyzing ||
        ScraperPhase.generating ||
        ScraperPhase.debugging =>
          scheme.secondary,
        ScraperPhase.done => scheme.primary,
        ScraperPhase.failed => scheme.error,
        _ => scheme.outline,
      };

  // ── Phase 4：探索阶段状态栏映射 ──

  String _explorePhaseLabel(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => '探索待机',
        ExplorePhase.exploring => '探索中',
        ExplorePhase.categorizing => '归类中',
        ExplorePhase.confirming => '等待确认',
        ExplorePhase.building => '构建中',
        ExplorePhase.registering => '注册中',
        ExplorePhase.done => '✅ 探索完成',
        ExplorePhase.failed => '❌ 探索失败',
      };

  IconData _explorePhaseIcon(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => Icons.travel_explore_rounded,
        ExplorePhase.exploring => Icons.radar_rounded,
        ExplorePhase.categorizing => Icons.category_rounded,
        ExplorePhase.confirming => Icons.checklist_rounded,
        ExplorePhase.building => Icons.construction_rounded,
        ExplorePhase.registering => Icons.link_rounded,
        ExplorePhase.done => Icons.check_circle_rounded,
        ExplorePhase.failed => Icons.error_rounded,
      };

  Color _explorePhaseColor(ExplorePhase p, ColorScheme scheme) => switch (p) {
        ExplorePhase.exploring => scheme.tertiary,
        ExplorePhase.categorizing ||
        ExplorePhase.confirming ||
        ExplorePhase.building ||
        ExplorePhase.registering =>
          scheme.secondary,
        ExplorePhase.done => scheme.primary,
        ExplorePhase.failed => scheme.error,
        _ => scheme.outline,
      };
}

/// 「轨迹」视图槽：每次 build 实时读取 AI 面板的 Trace 记录器
/// （面板在 IndexedStack 中保活；未挂载时显示空态）。
class _TraceSlot extends StatelessWidget {
  final GlobalKey<ScraperAIPanelState> aiPanelKey;

  const _TraceSlot({required this.aiPanelKey});

  @override
  Widget build(BuildContext context) {
    final recorder = aiPanelKey.currentState?.traceRecorder;
    if (recorder == null) {
      return const Center(
        child: Text('暂无轨迹，开始一次对话后自动记录'),
      );
    }
    return AgentTraceView(recorder: recorder);
  }
}

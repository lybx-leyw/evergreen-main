/// 爬虫生成器 AI 交互面板。
///
/// 右侧面板下半部分——提供 AI 聊天输入/输出。
/// 使用 AgentAssembly 隔离模式，注册爬虫专用工具，注入 Skill 系统提示。
library scraper_ai_panel;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';

import '../workflow/scraper_workflow.dart';
import 'tools/scraper_tools.dart';
import '../workflow/scraper_guard.dart';
import '../explore/explore_workflow.dart';
import '../explore/explore_scope.dart';
import '../explore/explore_evidence.dart';
import '../explore/scraper_explore_tools.dart';
import '../explore/explore_panel.dart';
import '../web/scraper_webview.dart';
import '../board/scraper_board.dart';
import 'scraper_gate.dart';
import 'scraper_hooks.dart';
import 'scraper_journal.dart';
import 'python_capabilities.dart';
import '../scraper_skill_const.dart' show scraperSkillBody, scraperExploreSkillBody;
import '../scraper_exporter.dart';
import '../scraper_env.dart';
import '../scraper_json_validator.dart';
import '../scraper_flow_facade.dart';
import '../scraper_bridge_registry.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/config_register.dart';
import 'package:evergreen_base/core/config/register_config.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/core/services/ui_operation_log.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/agent_step_indicator.dart';
import 'package:evergreen_base/renderer/components/shared/trace/agent_trace_recorder.dart';
import 'package:evergreen_base/core/agent/guardian/guardian.dart';
import 'package:evergreen_base/core/agent/guardian/guardian_policy.dart';
import 'package:evergreen_base/core/agent/tools/guardian_review_tool.dart';

// ═══════ ScraperAIPanel ═══════

/// 爬虫 AI 面板——隔离 Agent + 专用工具 + 定制 Skill。
class ScraperAIPanel extends ConsumerStatefulWidget {
  final ScraperWorkflow workflow;
  final String moduleId;
  final String slotKey;
  final String workspaceDir;
  final String projectRoot;

  /// 画板模式（Phase 4 · A23：定向 capture / 探索 explore）。
  /// explore 模式切换工具集、Skill、harness 约束（D9 两套工作流）。
  final ScraperBoardMode mode;

  /// 画板 id（探索会话命名隔离用；A21 沙盒）。
  final String? boardId;

  /// 探索工作流（Phase 4；探索模式由父级 GeneratorView 持有并传入）。
  final ExploreWorkflow? exploreWorkflow;

  /// 浏览器 JS/导航执行通道（Phase 4；探索工具消费）。
  final ScraperWebViewBridge? webBridge;

  /// 断点续作：恢复的产物根名 / 插件目录（GeneratorView 从画板状态恢复）。
  final String? resumeDataName;
  final String? resumePluginDir;

  /// 断点续作：恢复后一次性发送给 AI 的续作 prompt（数据源建板注入）。
  final String? resumePrompt;

  /// 画板绑定数据源 JSON（注入系统提示，向画板 AI 告知数据状态）。
  final String? boundSourcesJson;

  const ScraperAIPanel({
    super.key,
    required this.workflow,
    required this.moduleId,
    required this.slotKey,
    required this.workspaceDir,
    required this.projectRoot,
    this.mode = ScraperBoardMode.capture,
    this.boardId,
    this.exploreWorkflow,
    this.webBridge,
    this.resumeDataName,
    this.resumePluginDir,
    this.resumePrompt,
    this.boundSourcesJson,
  });

  @override
  ConsumerState<ScraperAIPanel> createState() => ScraperAIPanelState();
}

class ScraperAIPanelState extends ConsumerState<ScraperAIPanel> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  // _messages 代理到当前会话，所有旧代码无需改动
  List<ChatMessage> get _messages {
    if (_currentIdx < 0 || _currentIdx >= _sessions.length) return const [];
    return _sessions[_currentIdx].messages;
  }

  // ── 多会话管理 ──
  List<_ScraperSession> _sessions = [];
  int _currentIdx = -1;

  late final ScraperFlowFacade _facade;
  AgentAssembly? _assembly;
  StreamSubscription<agent.AgentEvent>? _eventSub;

  /// Trace 记录器（Phase 3 · C1-C5）：实现 TraceBuffer，订阅事件流，
  /// 供 GeneratorView 的「轨迹」视图消费。
  late final AgentTraceRecorder _traceRecorder;

  /// Guardian 审查会话（Phase 3 · A12/A13）：G5/G6 门禁自动审查 + guardian_review 工具。
  GuardianSession? _guardian;

  /// 爬虫环境变量存储（set_env_var 写入 → 子进程注入；镜像 .greenix/config.json）。
  ///
  /// 修复（用户反馈 bug）：探索模式此前无法写账号密码等凭据到环境变量，
  /// 本存储让 AI 把用户提供的凭据持久化并注入所有 Python 子进程环境。
  late final ScraperEnvStore _envStore =
      ScraperEnvStore(mirrorConfigPath: greenixConfigPath);

  /// DeepSeek Provider（用于 AI 字段推断，P1 B3）。
  agent.DeepSeekProvider? _provider;

  // ── 流式累积 ──
  final StringBuffer _pendingText = StringBuffer();
  final StringBuffer _pendingReasoning = StringBuffer();
  bool _isRunning = false;
  String _currentTool = '';

  /// 本轮已执行工具步骤数（AgentStepIndicator 显示"第 N 步"）。
  int _stepCount = 0;

  bool _initialized = false;
  String _error = '';

  // ── 阶段 UI 占位 ──
  String _phaseBanner = '';

  // ── 插件生成命名 ──
  /// 用户指定的数据名称（如 `courses`）。
  /// 由 AI 在工作流中通过 `set_data_name` 工具写入（取代原页面打开即弹的命名弹窗）。
  /// 插件目录自动推导为 `data-{name}`，manifest name = name；为 null 时回退 'scraper'。
  String? _dataName;
  /// 最近一次生成的插件目录路径（供 _hotRegister 复用）。
  String? _pluginDir;

  // ── 断点续作标记 ──
  bool _resumePromptSent = false;
  bool _resumeBubbleShown = false;

  /// 产物根名 / 插件目录（GeneratorView 持久化画板状态读取用）。
  String? get dataName => _dataName;
  String? get pluginDir => _pluginDir;

  // ── 多会话持久化（画板沙盒：<workspace>/boards/<boardId>/） ──
  String get _boardDir =>
      p.join(widget.workspaceDir, 'boards', widget.boardId ?? 'default');
  String get _sessionsPath => p.join(_boardDir, 'session.json');

  /// Agent 上下文侧车文件（与主文件分离：主文件只存 UI 消息，侧车存完整
  /// LLM 上下文——修复「重启后对话历史不完整/1MB 整体丢弃」）。
  String _agentSessionSidecarPath(int idx) =>
      p.join(_boardDir, 'agent_session_$idx.json');

  void _loadSessions() {
    try {
      final file = File(_sessionsPath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        final boardId = widget.boardId;
        // 双向绑定（会话 → 画板）：孤儿会话（boardId 缺失或与所在画板不符）
        // 一律不承认、不显示。旧数据无 boardId → 视为孤儿过滤。
        _sessions = json
            .whereType<Map<String, dynamic>>()
            .map(_ScraperSession.fromJson)
            .where((s) => s.boardId != null && s.boardId == boardId)
            .toList();
        // 侧车恢复 Agent 上下文（完整工具结果）
        for (var i = 0; i < _sessions.length; i++) {
          final sidecar = File(_agentSessionSidecarPath(i));
          if (sidecar.existsSync()) {
            try {
              _sessions[i].agentSessionJson =
                  jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
            } catch (_) {}
          }
        }
        _currentIdx = _sessions.isNotEmpty ? 0 : -1;
        debugPrint('[ScraperAIPanel] 📂 加载 ${_sessions.length} 个会话'
            '（画板 ${widget.boardId ?? 'default'}）');
      }
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 加载会话失败: $e');
      _sessions = [];
      _currentIdx = -1;
    }
  }

  void _saveSessions() {
    // ① 写盘前将当前 Agent 内部 Session 快照同步到当前 ScraperSession
    try {
      if (_assembly != null && _currentIdx >= 0 && _currentIdx < _sessions.length) {
        _sessions[_currentIdx].agentSessionJson =
            _assembly!.controller.session.toJson();
      }
    } catch (_) {
      // Agent 可能正在初始化/销毁，安全忽略
    }
    try {
      final dir = Directory(_boardDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      const maxMsgLen = 50000;
      for (final s in _sessions) {
        for (var i = 0; i < s.messages.length; i++) {
          final m = s.messages[i];
          if (m.text.length > maxMsgLen) {
            s.messages[i] = ChatMessage(
              role: m.role,
              text: '${m.text.substring(0, maxMsgLen)}\n…[已截断 ${m.text.length - maxMsgLen} 字符]',
            );
          }
        }
      }
      // 主文件：仅 UI 消息 + 元数据（不含 Agent 快照，避免巨型工具结果撑爆）
      final light = _sessions
          .map((s) => <String, dynamic>{
                'name': s.name,
                'id': s.id,
                'boardId': s.boardId,
                'messages': s.messages.map((m) => m.toJson()).toList(),
                'createdAt': s.createdAt.toIso8601String(),
              })
          .toList();
      File(_sessionsPath).writeAsStringSync(jsonEncode(light));
      // 侧车：完整 Agent 上下文（单条工具结果 >50KB 才截断，不再整体丢弃）
      for (var i = 0; i < _sessions.length; i++) {
        final snap = _sessions[i].agentSessionJson;
        if (snap == null) continue;
        File(_agentSessionSidecarPath(i))
            .writeAsStringSync(jsonEncode(_clampAgentSessionJson(snap)));
      }
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 保存会话失败: $e');
    }
  }

  /// 截断 Agent 上下文中过大的工具结果消息（保留结构与对话流）。
  Map<String, dynamic> _clampAgentSessionJson(Map<String, dynamic> json) {
    try {
      final msgs = json['messages'] as List<dynamic>?;
      if (msgs == null) return json;
      const maxLen = 50000;
      for (final m in msgs.whereType<Map<String, dynamic>>()) {
        if (m['role'] == 'tool') {
          final content = m['content'];
          if (content is String && content.length > maxLen) {
            m['content'] =
                '${content.substring(0, maxLen)}\n…[工具结果已截断 ${content.length - maxLen} 字符]';
          }
        }
      }
    } catch (_) {}
    return json;
  }

  /// 切换到已有会话或创建新会话（以数据名称命名）。
  void _switchOrCreateSession(String name) {
    // ① 保存当前 Agent Session 到旧 ScraperSession
    if (_assembly != null && _currentIdx >= 0 && _currentIdx < _sessions.length) {
      _sessions[_currentIdx].agentSessionJson = _assembly!.controller.session.toJson();
    }

    final existingIdx = _sessions.indexWhere((s) => s.name == name);
    if (existingIdx >= 0) {
      setState(() => _currentIdx = existingIdx);
      _restoreAgentSession(existingIdx);
      debugPrint('[ScraperAIPanel] ♻ 切换到已有会话: $name');
    } else {
      final session = _ScraperSession(name: name, boardId: widget.boardId);
      setState(() {
        _sessions.add(session);
        _currentIdx = _sessions.length - 1;
      });
      // 新会话 → 清空 Agent Session
      _assembly?.controller.newSession();
      // 新会话加欢迎消息
      final msgs = _sessions[_currentIdx].messages;
      msgs.add(ChatMessage.assistant(
        '👋 **$name 会话已创建**\n\n'
        '我可以通过以下步骤帮你生成 Python 爬虫：\n\n'
        '1. **浏览目标网站** — 在左侧 WebView 中登录并操作\n'
        '2. **保存凭证** — 我会引导你设置凭据（平台配置 或 环境变量）\n'
        '3. **分析请求日志** — 我会分析后台捕获的 HTTP 请求\n'
        '4. **生成并验证爬虫** — 自动生成代码、终端执行、排除错误直到成功\n\n'
        '🔐 **凭证双保险**：生成的脚本内置双策略降级机制（HTTP 配置 → 环境变量兜底），'
        '确保即使平台配置同步有延迟也能正常运行。\n\n'
        '请先浏览目标网站，然后点击"分析日志"。',
      ));
      debugPrint('[ScraperAIPanel] ✨ 新建会话: $name');
    }
    _saveSessions();
  }

  void _switchSession(int idx) {
    if (idx < 0 || idx >= _sessions.length || idx == _currentIdx) return;
    // ① 保存当前 Agent Session 到旧 ScraperSession
    if (_assembly != null && _currentIdx >= 0 && _currentIdx < _sessions.length) {
      _sessions[_currentIdx].agentSessionJson = _assembly!.controller.session.toJson();
    }
    // ② 切换 UI 索引
    setState(() {
      _currentIdx = idx;
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    // ③ 恢复目标会话的 Agent Session（含 LLM 上下文）
    _restoreAgentSession(idx);
    _saveSessions();
    debugPrint('[ScraperAIPanel] 📋 切换会话 → ${_sessions[idx].name}');
  }

  /// 将指定 ScraperSession 的 Agent Session 快照恢复到 Agent Controller。
  ///
  /// 断点续作三级回退（修复「重启后传给 AI 的对话历史不完整」）：
  /// 1. 有 Agent 快照（侧车）→ 完整恢复 LLM 上下文（含工具结果）；
  /// 2. 无快照但存在 UI 消息 → 从 UI 消息重建上下文；
  /// 3. 都没有 → 全新会话。
  void _restoreAgentSession(int idx) {
    if (_assembly == null) return;
    final target = _sessions[idx];
    try {
      if (target.agentSessionJson != null) {
        final restored = agent.Session.fromJson(target.agentSessionJson!);
        _assembly!.controller.setSession(restored);
        debugPrint('[ScraperAIPanel] ♻ 恢复 Agent Session (${restored.messages.length} 条)');
      } else if (target.messages.isNotEmpty) {
        final rebuilt = agent.Session();
        for (final m in target.messages) {
          if (m.role == 'user') {
            rebuilt.add(
                agent.Message(role: agent.Role.user, content: m.text));
          } else if (m.role == 'assistant') {
            rebuilt.add(
                agent.Message(role: agent.Role.assistant, content: m.text));
          }
        }
        _assembly!.controller.setSession(rebuilt);
        debugPrint('[ScraperAIPanel] ♻ 从 UI 消息重建 Agent 上下文 (${rebuilt.messages.length} 条)');
      } else {
        _assembly!.controller.newSession();
        debugPrint('[ScraperAIPanel] 🆕 无历史快照，新建 Agent Session');
      }
      // 确保 system prompt 是当前模式最新版本 + 断点续作状态块
      // （Skill 只作为角色定义注入一次，续作块告知已完成步骤，避免掩盖）
      _assembly!.controller.setSystemPrompt(_skillBodyWithResume);
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 恢复 Agent Session 失败: $e → 新建');
      _assembly!.controller.newSession();
    }
  }

  void _deleteSession(int idx) {
    if (idx < 0 || idx >= _sessions.length) return;
    final name = _sessions[idx].name;
    final wasCurrent = _currentIdx == idx;
    setState(() {
      _sessions.removeAt(idx);
      if (_currentIdx == idx) {
        _currentIdx = _sessions.isEmpty ? -1 : (idx >= _sessions.length ? _sessions.length - 1 : idx);
      } else if (_currentIdx > idx) {
        _currentIdx--;
      }
    });
    // 若删除的是当前会话 → 恢复新当前会话的 Agent 状态
    if (wasCurrent && _currentIdx >= 0) {
      _restoreAgentSession(_currentIdx);
    }
    _saveSessions();
    debugPrint('[ScraperAIPanel] 🗑 删除会话: $name');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除会话「$name」'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _facade = ScraperFlowFacade(workflow: widget.workflow);
    _traceRecorder = AgentTraceRecorder(
      jsonlPath: p.join(widget.workspaceDir, 'trace.jsonl'),
    );
    // 断点续作：恢复产物根名/插件目录（GeneratorView 从画板状态注入）
    if (widget.resumeDataName != null) _dataName = widget.resumeDataName;
    if (widget.resumePluginDir != null) _pluginDir = widget.resumePluginDir;
    _loadSessions();
    _initAgent();
  }

  @override
  void dispose() {
    _saveSessions();
    _eventSub?.cancel();
    _traceRecorder.dispose();
    _assembly?.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAgent() async {
    if (_initialized) return;

    final assemblyModuleId = '${widget.moduleId}/${widget.slotKey}/scraper';

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (apiKey.isEmpty) {
        if (mounted) {
          setState(() {
            _error = '未配置 DeepSeek API Key';
            _initialized = true;
          });
        }
        return;
      }

      final model = getSetting(prefs, 'DEEPSEEK_MODEL');
      final baseUrl = getSetting(prefs, 'DEEPSEEK_BASE_URL');

      final provider = agent.DeepSeekProvider(
        dio: Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )),
        apiKey: apiKey,
        model: model.isNotEmpty ? model : 'deepseek-v4-flash',
        baseUrl: baseUrl,
      );

      // 保存 provider 引用（B3：AI 字段推断）
      _provider = provider;

      // 注入 AI 字段推断器到 Facade（B3）
      _facade.aiFieldInferrer = (logs) => _inferFieldsWithDeepSeek(logs);

      final skillIdx = ref.read(skillIndexProvider);
      final memStore = ref.read(memoryStoreProvider);

      // 创建爬虫专用 Agent 配置
      final agentConfig = {
        'tools': {'mode': 'all'},
        'skills': {'mode': 'all'},
        'max_steps': 50,
        'temperature': 0.3,
      };

      // ── Phase 1 harness 接线：Gate + Hooks + AskTool ──
      // Phase 4（D9）：探索模式接入 ExploreWorkflow（阶段白名单等探索约束）
      final isExplore = widget.mode == ScraperBoardMode.explore;
      final ew = widget.exploreWorkflow;
      if (isExplore && ew == null) {
        // 显式契约：探索画板必须由 GeneratorView 传入 ExploreWorkflow
        throw StateError('探索模式缺少 ExploreWorkflow（GeneratorView 必须传入）');
      }
      final gate = ScraperGate(onConfirm: _confirmToolCall);
      final hooks = ScraperHooks(
        workflow: widget.workflow,
        traceBuffer: _traceRecorder,
        exploreWorkflow: isExplore ? ew : null,
      );
      // 工作流级回调接线（G5 弹窗 / 3 轮 warning / 快照锁定）
      widget.workflow.onUserConfirmRequest = _confirmFakeDataGate;
      widget.workflow.onWarning = (warn) {
        if (!mounted) return;
        _messages.add(ChatMessage.assistant('⚠️ **$warn**'));
        _saveSessions();
      };

      // ── Phase 3 Guardian（A12/A13）：独立 LLM 会话 + 安全策略 prompt ──
      // 先建会话（seedTools 需要），assembly 创建后再绑事件输出。
      final guardian = GuardianSession(
        llm: ProviderGuardianLlm(provider),
        policyPrompt: guardianPolicyPrompt,
      );
      _guardian = guardian;
      // G5/G6 门禁自动审查接线（A13 另调 API；fail-closed：失败走规则守卫）
      widget.workflow.onGuardianReview = _guardianReview;
      widget.workflow.onGuardianDenied = (rationale) {
        if (!mounted || _currentIdx < 0) return; // 尚无会话时不注入气泡
        _messages.add(ChatMessage.assistant('🛡️ **Guardian 审查拒绝**\n$rationale'));
        _saveSessions();
      };

      _assembly = AgentAssembly.fromConfig(
        moduleId: assemblyModuleId,
        config: agentConfig,
        sharedProvider: provider,
        globalSkillIndex: skillIdx,
        globalMemoryStore: memStore,
        gate: gate,
        hooks: hooks,
        seedTools: isExplore
            ? [
                // ── Phase 4 探索工具集（D1-D9）+ AskTool + GuardianReviewTool ──
                ...createScraperExploreTools(
                  exploreWorkflow: ew!,
                  captureWorkflow: widget.workflow,
                  evaluateJs: (script) async {
                    final b = widget.webBridge;
                    if (b == null || !b.ready) return null;
                    return b.evaluateJavaScript!(script);
                  },
                  navigateTo: (url) async {
                    final b = widget.webBridge;
                    if (b == null || !b.ready) {
                      throw StateError('浏览器导航通道不可用（WebView 未就绪）');
                    }
                    await b.navigateTo!(url);
                  },
                  presentSources: _presentExploreSources,
                  buildSource: _buildExploreSource,
                  registerBatch: _registerExploreBatch,
                  verifyLoginFlow: _runLoginCheck,
                  executeBuiltSource: _executeBuiltSource,
                  // P2-1 工具事实源：运行时扫描嵌入 Python 的 site-packages
                  listPythonCapabilities: () =>
                      scanPythonSitePackages(greenixPythonDir),
                  // 探索模式凭据路径：set_env_var 写入环境变量（修复无法写凭据）
                  envStore: _envStore,
                  // 补齐白名单已放行但未注册的工具（修复 AI 报"工具不存在"）
                  workspaceDir: widget.workspaceDir,
                  requestOverride: _requestGuardOverride,
                  // 环境诊断：区分「AI 自身错误」vs「浏览器未就绪」
                  checkExploreReady: _checkExploreReady,
                ),
                // AskTool：AI 结构化 ask 用户（A11）
                agent.AskTool(asker: _asker),
                // GuardianReviewTool（A13 显式 tool 审核）：AI 可主动调用自审
                GuardianReviewTool(
                  session: guardian,
                  evidenceProvider: () => _buildGuardianEvidence(gate: 'tool'),
                ),
              ]
            : [
                ...createScraperTools(
                  workspaceDir: widget.workspaceDir,
                  projectRoot: widget.projectRoot,
                  resolvePython: () => resolvePythonExe(),
                  getLogsSummary: () => widget.workflow.requestLogsSummary(),
                  envStore: _envStore,
                  enqueueCommand: (cmd) => widget.workflow.setTerminalCommand(cmd),
                  getTerminalResult: () async {
                    // 轮询等待终端执行完成并写入 terminalResult
                    String result = '';
                    final deadline = DateTime.now().add(const Duration(seconds: 30));
                    while (result.isEmpty && DateTime.now().isBefore(deadline)) {
                      result = widget.workflow.consumeTerminalResult();
                      if (result.isEmpty) {
                        await Future.delayed(const Duration(milliseconds: 200));
                      }
                    }
                    return result.isEmpty ? '[error: 终端命令执行超时（30s）]' : result;
                  },
                  // root cause B：让 AI 能主动触发导出+注册并看到「检验失败」日志。
                  exportAndRegister: () => _generatePlugin(),
                  // 三层名称防护：将用户命名注入 tool，强制校验/纠正 AI 传参
                  dataNameProvider: () => _dataName,
                  // AI 在工作流中向用户索取产物根名后回写（取代页面打开即弹的命名窗）
                  setDataName: setDataName,
                  // guard_override：门控一次性豁免（用户放行本次拦截）
                  requestOverride: _requestGuardOverride,
                ),
                // AskTool：AI 结构化 ask 用户（A11）
                agent.AskTool(asker: _asker),
                // GuardianReviewTool（A13 显式 tool 审核）：AI 可主动调用自审
                GuardianReviewTool(
                  session: guardian,
                  evidenceProvider: () => _buildGuardianEvidence(gate: 'tool'),
                ),
              ],
      );

      // Phase 3：Trace 订阅事件流（round 边界 / think / reply 兜底）+ Guardian 裁决事件
      _traceRecorder.attach(_assembly!.eventSink.stream);
      guardian.sink = _assembly!.eventSink;

      // 设置系统提示（探索/定向 Skill + 断点续作状态块）
      _assembly!.controller.setSystemPrompt(_skillBodyWithResume);

      // 订阅事件
      _eventSub = _assembly!.eventSink.stream.listen(_onAgentEvent);
      debugPrint('[ScraperAIPanel] ✅ Agent 初始化完毕');
    } catch (e, st) {
      debugPrint('[ScraperAIPanel] ❌ Agent 初始化失败: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Agent 初始化失败: $e';
          _initialized = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _initialized = true);
      // B 方案：把本面板的官方工具 Registry 注册给全局 registry，
      // 供 ScraperBridgeServer 转发 DSH 的工具 RPC（复用官方工具链）。
      scraperBridgeRegistry.registerToolRegistry(_assembly!.registry);
      // 探索模式：按画板 id 隔离会话（A21）；
      // 定向模式：自动创建默认会话（不再弹命名窗，产物根名由 AI 在工作流中 ask 用户后 set_data_name 写入）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.mode == ScraperBoardMode.explore) {
          _ensureExploreSession();
        } else {
          _ensureCaptureSession();
        }
        _maybeSendResumePrompt();
      });
    }
  }

  /// 定向模式会话初始化（无命名弹窗）：自动创建/切换到默认会话，
  /// 产物根名待 AI 在工作流中通过 `set_data_name` 工具向用户索取后写入。
  void _ensureCaptureSession() {
    if (widget.mode == ScraperBoardMode.explore || !mounted) return;
    if (_sessions.isEmpty) {
      final session = _ScraperSession(name: 'scraper', boardId: widget.boardId);
      setState(() {
        _sessions.add(session);
        _currentIdx = 0;
      });
      _assembly?.controller.newSession();
    } else if (_currentIdx < 0) {
      setState(() => _currentIdx = 0);
    }
    // 断点续作提示（仅恢复场景；新会话不提示）
    if (!_resumeBubbleShown &&
        _currentIdx >= 0 &&
        (widget.workflow.phase != ScraperPhase.idle ||
            widget.workflow.snapshotFrozen)) {
      _resumeBubbleShown = true;
      _messages.add(ChatMessage.assistant(
          '🔄 **断点续作**：已恢复上次会话（${_messages.length} 条消息）。\n'
          '工作流阶段: ${widget.workflow.phase.name}，'
          '快照 ${widget.workflow.snapshot.length} 条，'
          'Python 代码 ${widget.workflow.pythonCode.isEmpty ? '无' : '${widget.workflow.pythonCode.length} 字符'}。\n'
          '可点击「分析日志」继续，或直接输入反馈。'));
    }
    _saveSessions();
  }

  /// 数据源建板等场景：恢复后一次性发送续作 prompt 给 AI
  /// （并索引到 debug 工作流状态）。
  void _maybeSendResumePrompt() {
    if (_resumePromptSent || _assembly == null || _isRunning || !mounted) {
      return;
    }
    final prompt = (widget.resumePrompt ?? '').trim();
    if (prompt.isEmpty) return;
    if (_currentIdx < 0 || _currentIdx >= _sessions.length) return;
    _resumePromptSent = true;
    setState(() {
      _isRunning = true;
      _pendingText.clear();
      _pendingReasoning.clear();
      _messages.add(ChatMessage.assistant(
          '🔄 **断点续作**：已载入数据源工作区，AI 开始调试…'));
    });
    _saveSessions();
    _assembly!.controller.send(prompt);
  }

  /// 当前模式的 Skill 内容（D9：探索 / 定向两套角色提示词）。
  String get _skillBody =>
      widget.mode == ScraperBoardMode.explore
          ? scraperExploreSkillBody
          : scraperSkillBody;

  /// Skill + 断点续作状态块（告知 AI 已完成步骤，禁止重做/掩盖）。
  String get _skillBodyWithResume {
    final ctx = _resumeContext;
    return ctx.isEmpty ? _skillBody : '$_skillBody\n\n$ctx';
  }

  /// 断点续作状态块：工作流阶段 + 已有产物 + 绑定数据源状态。
  String get _resumeContext {
    final buf = StringBuffer();
    final wf = widget.workflow;
    final ew = widget.exploreWorkflow;
    if (widget.mode == ScraperBoardMode.explore && ew != null) {
      if (ew.phase != ExplorePhase.idle) {
        buf.writeln('## 断点续作（上次会话已完成的状态，禁止重做）');
        buf.writeln('- 探索阶段: ${ew.phase.name}');
        buf.writeln('- 候选数据源: ${ew.candidates.length} 个；'
            '已确认: ${ew.selected.length} 个');
        buf.writeln('- 已访问页: ${ew.uniquePages}；已捕获请求: ${ew.requestsCaptured}');
        if (ew.baseHost.isNotEmpty) buf.writeln('- 锁定域名: ${ew.baseHost}');
        if (ew.stallDetected) {
          buf.writeln('- 空转熔断已触发: ${ew.stallMessage}');
        }
      }
    } else {
      if (wf.phase != ScraperPhase.idle || wf.snapshotFrozen) {
        buf.writeln('## 断点续作（上次会话已完成的状态，禁止重做）');
        buf.writeln('- 工作流阶段: ${wf.phase.name}');
        buf.writeln('- 活动日志: ${wf.logs.length} 条；'
            '冻结快照: ${wf.snapshot.length} 条（frozen=${wf.snapshotFrozen}）');
        buf.writeln('- Python 代码: ${wf.pythonCode.isEmpty ? '无' : '${wf.pythonCode.length} 字符'}');
        if (wf.errorMessage.isNotEmpty) {
          buf.writeln('- 最近错误: ${wf.errorMessage}');
        }
        if (_dataName != null && _dataName!.isNotEmpty) {
          buf.writeln('- 产物根名: $_dataName'
              '（插件目录 plugins/data-$_dataName/）');
        }
      }
    }
    final bound = (widget.boundSourcesJson ?? '').trim();
    if (bound.isNotEmpty) {
      buf.writeln('## 本画板绑定的数据源（事实状态，向 AI 告知数据状态）');
      buf.writeln(bound);
    }
    if (buf.isNotEmpty) {
      buf.writeln('> 从当前阶段直接继续；已完成步骤不要重新执行。');
    }
    return buf.toString();
  }

  // ── Phase 1 harness UI 回调 ──

  /// Gate 确认弹窗（命令白名单外 / save_credential）。
  Future<bool> _confirmToolCall(
      String toolName, Map<String, dynamic> args, String subject) async {
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 请求确认'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('工具: `$toolName`',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(subject, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  /// G5 假数据门禁弹窗（A10）：展示守卫原因 + AI 澄清文本，用户裁决放行/拒绝。
  Future<bool> _confirmFakeDataGate(String reason, String aiClarification) async {
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 疑似硬编码假数据'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('守卫检测：', style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.error,
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(reason, style: const TextStyle(fontSize: 13)),
              if (aiClarification.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('AI 澄清：', style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.primary,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(aiClarification,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
              const SizedBox(height: 12),
              Text('若确认是真实抓取（如静态 JSON 页无 API 日志），可放行；'
                  '否则拒绝并要求 AI 修正为真实抓取。',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝，要求修正'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放行'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  /// guard_override 工具回调：弹窗询问用户是否放行本次门控拦截。
  ///
  /// 用户同意 → `workflow.requestOverride(toolName)` 登记一次性豁免，
  /// AI 重新调用被拦工具时 hook 消费该豁免并放行。
  Future<bool> _requestGuardOverride(String toolName, String reason) async {
    if (!mounted) return false;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🟢 放行门控拦截？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('被拦截工具：$toolName',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.primary)),
              const SizedBox(height: 8),
              Text('AI 的放行理由：',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(reason, style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 12),
              Text('仅放行本次拦截（一次性）；下次同类拦截仍需重新放行。',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('拒绝，要求修正'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放行'),
          ),
        ],
      ),
    );
    if (approved == true) {
      widget.workflow.requestOverride(toolName);
      // 放行时同时清除假数据标记：G5/G6 的 suspectedFakeData 门禁是「堵住
      // 工作流」的最常见拦点，用户放行即视为认可数据真实性。
      widget.workflow.clearGuardFlag(GuardFlags.suspectedFakeData);
    }
    return approved ?? false;
  }

  /// AskTool 的 Asker 实现：渲染多选问题弹窗。
  agent.Asker get _asker => _ScraperAsker(this);

  // ── Phase 3：Trace 视图数据源（GeneratorView 的「轨迹」视图消费）──

  /// Trace 记录器（共享组件）。
  AgentTraceRecorder get traceRecorder => _traceRecorder;

  // ── Phase 3：Guardian 自动审查（A12/A13）──

  /// workflow.onGuardianReview 实现：G5/G6 门禁前自动调 Guardian。
  /// 审查失败/未接线 → null（fail-closed：维持规则守卫 + 用户弹窗）。
  Future<GuardianVerdict?> _guardianReview(
      GuardianReviewRequest request) async {
    final g = _guardian;
    if (g == null) return null;
    try {
      final evidence = await _buildGuardianEvidence(gate: request.gate);
      final merged = GuardianReviewRequest(
        gate: request.gate,
        action: request.action,
        arguments: '${request.arguments.isEmpty ? '{}' : request.arguments}\n'
            'Evidence:\n$evidence',
        violations: request.violations,
      );
      return await g.review(
        request: merged,
        parentTranscript: _assembly?.controller.session.messages,
      );
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ Guardian 审查失败（fail-closed 走规则守卫）: $e');
      return null;
    }
  }

  /// 调试层真实数据验收（G5 增强）：把 `scraper.py` 脚本 + 本次 stdout 输出
  /// 交给 Guardian LLM 判断是否为**真实抓取数据**（非空、非占位符、非字面量假数据）。
  ///
  /// 背景（用户反馈）：门控验收过去只做静态 lint + JSON 格式校验，从不验证
  /// 「输出到底是不是真实数据」。静态启发式会漏判（脚本有网络库但实际产出
  /// 空列表/字面量假数据）。现改为在 run 成功后用大模型看脚本+输出裁决。
  ///
  /// 判定 deny（假数据）→ `startDebugging()` + 回灌 AI 继续修正；
  /// allow / Guardian 未接线（fail-open，规则守卫兜底）→ 正常 `requestDone`。
  Future<void> _verifyScraperRealDataAndDone(String toolOutput) async {
    final g = _guardian;
    if (g == null) {
      // Guardian 未接线（如测试/无 API key）→ 不阻断，走既有 requestDone
      unawaited(widget.workflow.requestDone(aiClarification: _lastAiClarification));
      return;
    }
    try {
      final py = File(p.join(widget.workspaceDir, 'scraper.py'));
      final code = py.existsSync() ? py.readAsStringSync() : '';
      final stdoutExcerpt = toolOutput.length > 3000
          ? '${toolOutput.substring(0, 3000)}…'
          : toolOutput;
      final verdict = await _guardianReview(GuardianReviewRequest(
        gate: 'G5',
        action: '验证 scraper.py 的输出是否为真实抓取数据（非空、非占位符、'
            '非字面量假数据）。若输出为空列表/占位符(example.com/lorem/张三)/'
            '字面量硬编码数据，或脚本未真实发起网络请求，应判 deny。',
        arguments: '## scraper.py 脚本\n'
            '${code.isEmpty ? '（未找到 scraper.py）' : (code.length > 3000 ? '${code.substring(0, 3000)}…' : code)}\n'
            '\n## 本次执行 stdout 输出\n$stdoutExcerpt',
      ));
      if (!mounted) return;
      if (verdict != null && !verdict.allow) {
        // 判定为假数据 → 回灌 AI 继续调试
        final reason = verdict.reason.isEmpty ? '输出疑似非真实抓取数据' : verdict.reason;
        widget.workflow.setLastError('G5 真实数据验收未通过: $reason');
        widget.workflow.startDebugging();
        _messages.add(ChatMessage.assistant(
            '🛡️ **真实数据验收未通过**\n$reason\n'
            '请修正 scraper.py 使其真实抓取并产出真实数据后重试。'));
        _saveSessions();
      } else {
        unawaited(widget.workflow
            .requestDone(aiClarification: _lastAiClarification));
      }
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 真实数据验收异常（不阻断）: $e');
      if (mounted) {
        unawaited(widget.workflow
            .requestDone(aiClarification: _lastAiClarification));
      }
    }
  }

  /// 拼装 Guardian 证据：关键 trace（最近 20 条工具序列）+ guard flags + 产物摘要。
  Future<String> _buildGuardianEvidence({required String gate}) async {
    final buf = StringBuffer();
    // ① 关键 trace：工具序列摘要（含 [error] 标记）
    final all = <TraceEvent>[];
    for (final r in _traceRecorder.rounds) {
      all.addAll(r.events);
    }
    final tail = all.length > 20 ? all.sublist(all.length - 20) : all;
    buf.writeln('## 关键 trace（最近 ${tail.length} 条）');
    if (tail.isEmpty) {
      buf.writeln('（暂无工具/思考/回复记录）');
    }
    for (final e in tail) {
      switch (e) {
        case TraceToolEvent():
          buf.writeln(
              '[tool${e.isError ? '·error' : ''}] ${e.tool}(${e.argsSummary})'
              ' → ${e.resultSummary}');
          break;
        case TraceThinkEvent():
          buf.writeln('[think] ${e.elapsed.inMilliseconds}ms');
          break;
        case TraceReplyEvent():
          buf.writeln('[reply] ${e.preview}');
          break;
      }
    }
    // ② 违规记录（guard flags）
    final flags = widget.workflow.guardFlags;
    if (flags.isNotEmpty) {
      buf.writeln('## guard flags');
      buf.writeln(flags.join(', '));
    }
    // ③ 产物（scraper.py，若已写盘）
    if (gate != 'tool') {
      final py = File(p.join(widget.workspaceDir, 'scraper.py'));
      if (py.existsSync()) {
        final code = py.readAsStringSync();
        buf.writeln('## scraper.py（${code.length} 字符）');
        buf.writeln(code.length > 1500
            ? '${code.substring(0, 1500)}…'
            : code);
      }
    }
    return buf.toString();
  }

  /// 当前 AI 最后一条澄清文本（G5 弹窗用）。
  String get _lastAiClarification {
    for (final m in _messages.reversed) {
      if (m.role == 'assistant' && m.text.trim().isNotEmpty) {
        return m.text.length > 500 ? '${m.text.substring(0, 500)}…' : m.text;
      }
    }
    return '';
  }

  // ── Phase 7：AI 工具活动驱动定向工作流阶段推进 ──

  /// AI 调用 run_python_scraper（写代码）→ analyzing/questioning/debugging → generating。
  /// 不合法转换（如 done/failed 等）静默忽略，状态机自身有门槛守卫。
  void _enterGeneratingFromTool() {
    widget.workflow.startGenerating();
  }

  /// AI 调用 run_terminal_command（执行）→ generating/debugging → running。
  /// 若从 analyzing 直接执行（未显式走生成阶段），先补 generating 再 running。
  void _enterRunningFromTool() {
    if (!widget.workflow.startRunning()) {
      if (widget.workflow.startGenerating()) {
        widget.workflow.startRunning();
      }
    }
  }

  void _onAgentEvent(agent.AgentEvent event) {
    if (!mounted) return;

    switch (event.kind) {
      case agent.EventKind.turnStarted:
        setState(() {
          _isRunning = true;
          _pendingText.clear();
          _pendingReasoning.clear();
          _stepCount = 0;
        });
        break;

      case agent.EventKind.reasoning:
        if (event.reasoning != null) {
          _pendingReasoning.write(event.reasoning);
        }
        break;

      case agent.EventKind.text:
        if (event.text != null) {
          _pendingText.write(event.text);
          _flushAssistantBubble();
        }
        break;

      case agent.EventKind.toolDispatch:
        if (event.tool != null) {
          setState(() {
            _currentTool = event.tool!.name;
            _stepCount++;
          });
          // Phase 7 修复：AI 工具活动驱动定向工作流阶段推进——否则
          // 状态机永远停在 analyzing（生成/运行阶段从不进入），
          // 顶部步骤条与 workflow 图「形同虚设」。
          if (widget.mode != ScraperBoardMode.explore) {
            final toolName = event.tool!.name;
            if (toolName == 'run_python_scraper') {
              _enterGeneratingFromTool();
            } else if (toolName == 'run_terminal_command') {
              _enterRunningFromTool();
            }
          }
        }
        break;

      case agent.EventKind.toolResult:
        setState(() => _currentTool = '');
        final tool = event.tool;
        if (tool != null) {
          // ⚠️ 截断：巨型工具输出（曾达 2.1MB）会撑爆 UI 气泡与 Agent 上下文
          // → DeepSeek API 400 死循环。校验判断用截断后文本即可。
          final output = truncateToolOutput((tool.output ?? tool.error ?? '').trim());
          if (tool.isError) {
            _pendingText.writeln('\n⚠️ **${tool.name} 执行失败**\n');
            _pendingText.writeln('```\n${output.length > 500 ? '${output.substring(0, 500)}...' : output}\n```\n');
            // 守卫拦截（lint/命令黑名单/凭证非法）→ 调试计数（R5 不消耗？）
            // 守卫 block 消息含 "[error:"，此处回灌 AI 已由 hook 完成，UI 仅展示。
            widget.workflow.setLastError(output);
          } else if (tool.name == 'run_python_scraper') {
            // 根据退出码判断成功/失败（不再依赖特定字符串）
            final success = output.contains('✅ 爬虫执行成功') ||
                output.contains('✅ 命令执行成功') ||
                (!output.contains('❌') && !output.contains('Traceback') && output.isNotEmpty);
            if (success) {
              // G5 门禁：先做「真实数据验收」（LLM 判定脚本+输出是否为真实抓取数据），
              // 通过才 resetDebugLoop + requestDone；判定为假数据 → 回灌 AI 继续调试。
              widget.workflow.resetDebugLoop();
              unawaited(_verifyScraperRealDataAndDone(output));
              _pendingText.writeln('\n🎉 **爬虫执行成功，正在进行真实数据验收…**');
            } else if (output.contains('❌') || output.contains('Traceback')) {
              widget.workflow.setPythonOutput(output);
              widget.workflow.startDebugging();
            }
          } else if (tool.name == 'run_terminal_command') {
            final success = output.contains('✅ 命令执行成功') ||
                (!output.contains('❌') && !output.contains('Traceback') && output.isNotEmpty);
            if (success) {
              widget.workflow.resetDebugLoop();
              unawaited(widget.workflow
                  .requestDone(aiClarification: _lastAiClarification));
              _pendingText.writeln('\n🎉 **终端命令执行成功！**');
            } else if (output.contains('❌') || output.contains('Traceback')) {
              widget.workflow.setPythonOutput(output);
              widget.workflow.startDebugging();
            }
          } else if (tool.name == 'save_credential') {
            if (output.contains('✅') || output.contains('registered')) {
              _pendingText.writeln('\n💾 **已保存凭证**\n');
            } else {
              _pendingText.writeln('\n⚠️ **凭证保存异常**: $output\n');
              _pendingText.writeln('请告知用户在终端手动设置环境变量作为备用。\n');
            }
          }
          _flushAssistantBubble();
        }
        break;

      case agent.EventKind.turnDone:
        setState(() => _isRunning = false);
        _flushAssistantBubble();
        if (event.error != null) {
          _messages.add(ChatMessage.assistant(
            '❌ **出错了**\n${event.error}',
          ));
        }
        _saveSessions();
        break;

      default:
        break;
    }
  }

  // ── B3：AI 字段推断 ──

  /// 使用 DeepSeek 从 HTTP 请求日志中智能推断数据结构字段。
  ///
  /// 构建 prompt → 流式调用 DeepSeek → 解析 JSON 响应 → 返回 [InferredField] 列表。
  /// 失败时返回空列表，由 Facade 自动回退到 URL 推断。
  Future<List<InferredField>> _inferFieldsWithDeepSeek(List<HttpRequestLog> selected) async {
    if (_provider == null) return [];

    // 构建日志摘要
    final buf = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      buf.writeln('--- 请求 #${i + 1} ---');
      buf.writeln(selected[i].toAiSummary());
      buf.writeln();
    }

    const systemPrompt =
        '你是一个数据结构分析专家。你的任务是根据 HTTP 请求日志推断 API 返回的数据字段结构。'
        '你必须只返回合法的 JSON 数组，不要包含任何解释、markdown 标记或代码块。';

    final userPrompt =
        '请分析以下 HTTP 请求日志。根据 URL 路径、查询参数、请求体、响应特征等信息，'
        '推断出该 API 可能返回的数据字段。\n\n'
        '返回一个 JSON 数组，每个元素包含：\n'
        '- name: 字段名（英文 camelCase，如 userId, userName, createdAt）\n'
        '- type: 数据类型（string / number / boolean / date，必填）\n'
        '- description: 字段的中文描述（可选）\n\n'
        '例如：\n'
        '[{"name": "userId", "type": "number", "description": "用户ID"}, '
        '{"name": "userName", "type": "string", "description": "用户名"}, '
        '{"name": "createdAt", "type": "date", "description": "创建时间"}]\n\n'
        '请确保字段名有意义，能反映实际数据内容。\n\n'
        '=== HTTP 请求日志 ===\n\n'
        '${buf.toString()}';

    try {
      final messages = [
        agent.Message(role: agent.Role.system, content: systemPrompt),
        agent.Message(role: agent.Role.user, content: userPrompt),
      ];

      final response = StringBuffer();
      await for (final event in _provider!.chat(messages: messages)) {
        if (event.kind == agent.ProviderEventKind.content && event.text != null) {
          response.write(event.text);
        }
      }

      final text = response.toString().trim();
      if (text.isEmpty) {
        debugPrint('[ScraperAIPanel] ⚠ AI 返回空响应');
        return [];
      }

      // 尝试提取 JSON（可能被 markdown 代码块包裹）
      String jsonText = text;
      final jsonMatch = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(text);
      if (jsonMatch != null) {
        jsonText = jsonMatch.group(1)!.trim();
      }

      final json = jsonDecode(jsonText) as List<dynamic>;
      final fields = json.map((f) {
        final map = f as Map<String, dynamic>;
        return InferredField(
          name: map['name'] as String,
          type: map['type'] as String? ?? 'string',
          description: map['description'] as String?,
        );
      }).toList();

      debugPrint('[ScraperAIPanel] ✅ AI 推断 ${fields.length} 个字段: '
          '${fields.map((f) => f.name).join(', ')}');
      return fields;
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ AI 字段推断异常: $e');
      return [];
    }
  }

  void _flushAssistantBubble() {
    final text = _pendingText.toString();
    if (text.isEmpty) return;

    // 替换上次助手气泡（流式更新），或添加新气泡
    if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _isRunning) {
      _messages.last = ChatMessage.assistant(text);
    } else {
      _messages.add(ChatMessage.assistant(text));
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _assembly == null || _isRunning) return;

    // A16：done 状态下用户对话反馈 → refining（debugging 路线，不重新抓包）
    if (widget.workflow.phase == ScraperPhase.done) {
      widget.workflow.feedbackTriggered();
      _messages.add(ChatMessage.assistant(
          '🔄 **收到反馈**：已进入优化模式第 ${widget.workflow.refineCount} 轮'
          '（保留快照与产物），AI 将基于你的反馈调整。'));
    }

    _inputCtrl.clear();
    setState(() {
      _messages.add(ChatMessage.user(text));
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    _saveSessions();

    _assembly!.controller.send(text);
  }

  /// 停止当前 AI 运行（A17：停止按钮 + 阶段保留）。
  void _cancelRunning() {
    _assembly?.controller.cancel();
    setState(() => _isRunning = false);
    _messages.add(ChatMessage.assistant('⏹ **已停止**（当前阶段保留，可继续补充要求）'));
    _saveSessions();
    _scrollToBottom();
  }

  /// 确认操作完毕（A18：冻结日志快照 + 锁定 WebView）。
  void _confirmCaptureDone() {
    widget.workflow.confirmCaptureDone();
    _messages.add(ChatMessage.assistant(
        '📸 **日志快照已冻结**（${widget.workflow.snapshot.length} 条），WebView 已锁定。'
        '\n现在可以点击「分析日志」让 AI 基于快照分析，或继续对话。'));
    _saveSessions();
    _scrollToBottom();
  }

  /// 触发分析流程。
  ///
  /// 分析日志：先强制选择会话，再发起 AI 分析。
  void triggerAnalyze() async {
    // 探索模式走 startExplore（不同工作流，D9），不触发定向分析
    if (widget.mode == ScraperBoardMode.explore) return;
    // A18 快照语义：快照冻结后以快照为准；未冻结用活动日志
    final wf = widget.workflow;
    final hasData = wf.hasSnapshot || wf.hasLogs || wf.pythonCode.isNotEmpty;
    if (_assembly == null || _isRunning || !hasData) return;

    // 断点续作：上次停在 分析/追问/生成/执行/调试 中段 → 续作而非全新分析
    final midPhase = wf.phase == ScraperPhase.analyzing ||
        wf.phase == ScraperPhase.questioning ||
        wf.phase == ScraperPhase.generating ||
        wf.phase == ScraperPhase.running ||
        wf.phase == ScraperPhase.debugging;
    if (midPhase) {
      final picked = await _showSessionPicker();
      if (picked == null || !mounted) return;
      if (picked != _currentIdx) _switchSession(picked);
      setState(() {
        _isRunning = true;
        _pendingText.clear();
        _pendingReasoning.clear();
      });
      final resume = '''
断点续作：继续上次未完成的工作流（阶段: ${wf.phase.name}），不要重头开始。
- 已捕获日志: ${wf.logs.length} 条；冻结快照: ${wf.snapshot.length} 条
- Python 代码: ${wf.pythonCode.isEmpty ? '无' : '${wf.pythonCode.length} 字符'}
${wf.errorMessage.isNotEmpty ? '- 最近错误: ${wf.errorMessage}' : ''}
请从当前阶段继续（生成 → 终端执行 → 调试），复用已有产物，禁止重复已完成步骤。''';
      _messages.add(ChatMessage.assistant(
          '🔄 **断点续作**：从阶段 ${wf.phase.name} 继续。'));
      _saveSessions();
      _assembly!.controller.send(resume);
      return;
    }

    // ⚠️ 分析前强制选择会话（确保数据名称与会话一致）
    final picked = await _showSessionPicker();
    if (picked == null || !mounted) return; // 用户取消

    // 更新当前会话及数据名称
    if (picked != _currentIdx) {
      _switchSession(picked);
    }
    final dataName = _sessions[picked].name;
    setState(() {
      _dataName = dataName;
    });

    widget.workflow.startAnalyzing();

    final logsSummary = widget.workflow.requestLogsSummary();
    final prompt = '''
请分析以下 HTTP 请求日志。严格按 Skill 规定的流程执行，禁止跳步：

**⚠️ 命名信息（所有路径/类型名称必须以以下为准，禁止自行推断）：**
- 数据名称: $dataName
- 插件目录: plugins/data-$dataName/
- manifest name: $dataName

流程：
0. ⚠️ **首先检查现有凭证**：调用 `read_existing_credential(plugin_name="$dataName")` — 如果已有凭证配置则直接复用，跳过注册
1. 识别登录流程和目标数据 API
2. 凭证处理：**优先复用现有凭证**（仅登录反复失败后才调用 save_credential 注册新凭证）
3. 生成完整的 scraper.py，**必须逐字包含 Skill 中的锁定配置模板**，只替换 {CREDENTIAL_PLACEHOLDER}
4. 用 run_terminal_command 在终端执行 `python scraper.py`，观察输出并调试

重要规则：
- 🔒 **锁定模板不可修改**：_get_config() 代码逻辑必须原样保留，你只能填写占位符处的变量声明
- 📟 **执行用终端**：run_terminal_command，用户可在终端面板实时看到结果
- 🤫 **少问问题**：日志中已有答案的信息不要追问（目标 API、登录方式、字段等），默认 JSON 输出、默认全部字段
- 🚫 **禁止硬编码**：凭证必须通过 _get_config() 读取（模板已内置双策略降级：HTTP → 环境变量）
- 📁 **命名规范**：插件路径 `plugins/data-$dataName/`，数据源类型 `$dataName`，不可更改

## 当前捕获的请求日志

''';

    setState(() {
      _isRunning = true;
      _messages.add(ChatMessage.assistant(
        '🔍 **开始分析请求日志**（${widget.workflow.logs.length} 条）…\n'
        '📁 插件: `data-$dataName` | 数据源: `$dataName`',
      ));
    });
    _saveSessions();

    _assembly!.controller.send(prompt + logsSummary);
  }

  // ── Phase 4：探索模式（D1-D9）──

  /// 探索会话名（按画板 id 隔离，A21 沙盒）。
  String get _exploreSessionName => 'explore_${widget.boardId ?? 'board'}';

  /// 探索模式会话初始化（无命名弹窗；复用已有会话则恢复上下文）。
  Future<void> _ensureExploreSession() async {
    if (widget.mode != ScraperBoardMode.explore || !mounted) return;
    final name = _exploreSessionName;
    final existingIdx = _sessions.indexWhere((s) => s.name == name);
    if (existingIdx >= 0) {
      setState(() => _currentIdx = existingIdx);
      _restoreAgentSession(existingIdx);
      if (!_resumeBubbleShown) {
        _resumeBubbleShown = true;
        final ew = widget.exploreWorkflow;
        _messages.add(ChatMessage.assistant(
            '🔄 **断点续作**：已恢复探索会话（上次阶段: ${ew?.phase.name ?? '?'}，'
            '候选 ${ew?.candidates.length ?? 0} 个，'
            '已确认 ${ew?.selected.length ?? 0} 个）。\n'
            '点击「开始探索」将从当前阶段继续，不会重走流程。'));
      }
    } else {
      final session = _ScraperSession(name: name, boardId: widget.boardId);
      setState(() {
        _sessions.add(session);
        _currentIdx = _sessions.length - 1;
      });
      _assembly?.controller.newSession();
      _messages.add(ChatMessage.assistant(
        '🧭 **探索会话已就绪**\n\n'
        '我可以探索当前网站的同域 GET 接口并归类为候选数据源，'
        '由你勾选后批量构建注册。\n\n'
        '1. 请先在左侧浏览器**登录目标网站**\n'
        '2. 点击「开始探索」，或直接告诉我目标数据\n'
        '3. 我探索完毕后会弹出多选框让你确认要构建的数据源',
      ));
    }
    _saveSessions();
  }

  /// 「开始探索」入口（ExplorePanel 按钮，D1）。
  ///
  /// Scope 确认弹窗（授权范围，Scope Contract）→ 落盘 `.greenix/scope.json`
  /// → 锁定当前域名 → 进入 exploring → 给 AI 发送探索任务 prompt。
  /// Guardian 的 system prompt 同时注入授权范围，超出范围的 action 视为
  /// 未授权（user_authorization = unknown）。
  Future<void> startExplore() async {
    if (_assembly == null || _isRunning || !mounted) return;
    final ew = widget.exploreWorkflow;
    if (ew == null) return;

    // 断点续作：恢复出的非 idle 探索状态 → 不重发 scope 确认与全新任务 prompt
    if (ew.phase != ExplorePhase.idle) {
      await _resumeExplore();
      return;
    }

    String startUrl = '';
    try {
      startUrl = (await widget.webBridge?.currentUrl?.call()) ?? '';
    } catch (_) {}
    final existing = _loadScopeFromDisk();
    final result = await showExploreScopeConfirm(
      context,
      startUrl: startUrl,
      existing: existing,
    );
    if (result == null || !mounted) return;

    // 授权范围落盘（持久化授权，跨会话复用）
    _saveScopeToDisk(result.scope);

    // Phase 1：应用用户在授权弹窗配置的探索上限（页数/请求）。
    ew.configureLimits(ExploreLimits(
      maxPages: result.maxPages,
      maxRequests: result.maxRequests,
    ));

    // P1-1 空转熔断：触发即回灌聊天（AI 应切换策略或结束探索）
    ew.onStallDetected = (msg) {
      if (!mounted) return;
      _messages.add(ChatMessage.assistant('⚡ **探索空转熔断**\n$msg'));
      _saveSessions();
    };
    // 触达上限：回灌聊天提示 AI 停止循环并进入归类
    ew.onLimitReached = (msg) {
      if (!mounted) return;
      _messages.add(ChatMessage.assistant('⛔ **探索上限提示**\n$msg'));
      _saveSessions();
    };

    if (!ew.startExploring(
        startUrl: result.startUrl, scope: result.scope)) {
      _messages.add(ChatMessage.assistant(
          '⚠️ 无法开始探索（${ew.errorMessage.isEmpty ? '状态异常' : ew.errorMessage}）'));
      _saveSessions();
      return;
    }

    // Guardian 以持久化授权范围为事实源（超出范围 → 未授权）
    _guardian?.scopePromptSuffix = result.scope.toPromptSummary();

    setState(() {
      _isRunning = true;
      _pendingText.clear();
      _pendingReasoning.clear();
      _messages.add(ChatMessage.assistant(
          '🔎 **开始探索**（授权范围: ${result.scope.toDisplaySummary()}）\n'
          'AI 将循环：枚举链接 → GET 导航 → 读取捕获日志，'
          '直到无新链接或触达上限（${ew.limits.maxPages} 页 / ${ew.limits.maxRequests} 请求）。\n'
          '超出授权范围的主机/路径将被守卫拒绝。'));
    });
    _saveSessions();

    // P1-2 经验 Journal：同域历史经验注入探索任务（只做加速参考，不替代验证）
    JournalEntry? journalEntry;
    try {
      journalEntry = await ScraperJournal(baseDir: greenixJournalDir)
          .loadLatest(ew.baseHost);
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ journal 读取失败: $e');
    }

    // P1-A 用户需求注入：dataScope 是用户授权的数据目标，直接写进任务 prompt，
    // 让 AI 的探索优先级围绕用户目标展开；为空时先 ask 确认，禁止盲目乱扫。
    final userGoal = result.scope.dataScope.trim();
    final goalPrompt = userGoal.isNotEmpty
        ? '【用户数据目标】$userGoal\n'
            '优先深挖与该目标相关的栏目/列表/详情/接口，其余页面只扫骨架不下钻。'
        : '【用户数据目标】未填写 —— 先用 ask() 向用户确认本次想抓取的数据目标，'
            '再据此制定探索优先级（该目标决定下钻哪些栏目，禁止无差别乱扫）。';

    _assembly!.controller.send('''
【探索任务开始】请按探索 Skill 流程严格执行：
${journalEntry != null ? '\n【本域历史经验】\n${journalEntry.toPromptSummary()}\n' : ''}
$goalPrompt
Step 1 探索：explore_page_links() 枚举当前页链接；navigate_get(url) 逐页访问疑似
数据接口（仅 GET、同域、注意 1s 节流与页数上限）；list_captured_requests() 阅读
捕获的 GET 请求与响应体样本。直到无新链接或触达上限。
Step 2 归类：把 GET 数据接口细粒度归类为候选数据源 JSON。每个候选源必须附
sourceLogId（list_captured_requests 返回的证据 id，如 log-3），每个字段必须附
sourceJsonPath（对应响应 JSON 中的真实路径，如 \$.data[0].courseName）。
url 无捕获日志证据的源会被守卫拒绝，禁止臆造字段或路径。
Step 3 确认：调用 present_data_sources(sources) 弹出多选框让用户勾选（可改名）。
Step 4 构建：对每个确认的数据源调用 build_selected_source(name, code)。
构建环境（P2-1 运行时事实源）：${pythonCapabilitiesPrompt(scanPythonSitePackages(greenixPythonDir))}
未列出的模块禁止 import。
Step 5 注册：全部构建完成后调用 register_batch(names) 批量注册并验证。

当前锁定域名: ${ew.baseHost.isEmpty ? '（尚未锁定，首次导航自动锁定）' : ew.baseHost}
''');
  }

  /// 断点续作：恢复出的非 idle 探索状态 → 从当前阶段继续，不重走流程。
  Future<void> _resumeExplore() async {
    final ew = widget.exploreWorkflow;
    if (ew == null || _assembly == null || !mounted) return;

    // 上次停在候选确认 → 直接重新打开选择框
    if (ew.phase == ExplorePhase.confirming) {
      _messages.add(ChatMessage.assistant(
          '🔄 **断点续作**：上次停在候选确认，正在重新打开选择框…'));
      _saveSessions();
      await reopenSourcePicker();
      return;
    }

    setState(() {
      _isRunning = true;
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    final resume = '''
断点续作：继续未完成的探索任务，不要重头开始。
- 当前阶段: ${ew.phase.name}
${(ew.scope?.dataScope ?? '').trim().isNotEmpty ? '- 用户数据目标: ${ew.scope!.dataScope.trim()}（继续围绕该目标下钻相关栏目）' : ''}
- 已访问页: ${ew.uniquePages} / ${ew.limits.maxPages}；已捕获请求: ${ew.requestsCaptured} / ${ew.limits.maxRequests}
- 候选数据源: ${ew.candidates.length} 个${ew.selected.isNotEmpty ? '（已确认 ${ew.selected.length} 个待构建）' : ''}
${ew.stallDetected ? '- 空转熔断已触发，请切换策略（换入口/换链接层级），不要重复已探索页面。' : ''}
请基于以上状态继续：exploring 阶段继续枚举链接并导航；building/registering 阶段继续构建/注册已确认的数据源。''';
    _messages.add(ChatMessage.assistant(
        '🔄 **断点续作**：继续探索（上次阶段: ${ew.phase.name}）。'));
    _saveSessions();
    _assembly!.controller.send(resume);
  }

  // ── Scope 持久化（Scope Contract：.greenix/scope.json）──

  /// 读取持久化授权范围（无文件/损坏返回 null）。
  ExploreScope? _loadScopeFromDisk() {
    try {
      final f = File(greenixScopePath);
      if (!f.existsSync()) return null;
      final map = jsonDecode(f.readAsStringSync());
      if (map is! Map<String, dynamic>) return null;
      final scope = ExploreScope.fromJson(map);
      return scope.isActive ? scope : null;
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ scope.json 读取失败: $e');
      return null;
    }
  }

  /// 落盘授权范围（跨会话复用；写入失败仅告警不阻断探索）。
  void _saveScopeToDisk(ExploreScope scope) {
    try {
      final f = File(greenixScopePath);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(scope.toJson()));
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ scope.json 写入失败: $e');
    }
  }

  /// present_data_sources 工具回调：弹出多选弹窗（D4）。
  Future<List<CandidateDataSource>> _presentExploreSources(
      List<CandidateDataSource> candidates) async {
    if (!mounted) return const [];
    return showExploreSourcePicker(context, candidates);
  }

  /// ExplorePanel「重新打开选择框」按钮：用当前候选重新弹窗并确认。
  Future<void> reopenSourcePicker() async {
    if (!mounted) return;
    final ew = widget.exploreWorkflow;
    if (ew == null || ew.candidates.isEmpty) return;
    final sel = await showExploreSourcePicker(context, ew.candidates);
    if (sel.isNotEmpty) {
      ew.confirmSelection(sel);
      setState(() {});
    }
  }

  /// 查找候选数据源定义（build 时回填 displayName/category/fields）。
  CandidateDataSource? _findCandidate(String name) {
    final ew = widget.exploreWorkflow;
    if (ew == null) return null;
    for (final c in ew.selected) {
      if (c.name == name) return c;
    }
    for (final c in ew.candidates) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// build_selected_source 工具回调：逐源构建 data-{name} 插件（D5/D8）。
  ///
  /// 复用定向模式同一产物契约：lint 防线 → 注入 JSON 验证器 →
  /// scraper.py + data/manifest.json（含 displayName/category）→ config/config.json。
  Future<String> _buildExploreSource(String name, String code) async {
    final buf = StringBuffer();
    void say(String m) {
      if (mounted) _messages.add(ChatMessage.assistant(m));
      buf.writeln(m);
    }

    try {
      final candidate = _findCandidate(name);
      say('🔧 构建 data-$name（${candidate?.displayName ?? name}）…');

      // G6 防线：lint（violation 拒绝；假数据 warning → guardFlags，注册前强制修正）
      final urls = widget.workflow.logs
          .map((l) => l.url)
          .where((u) => u.startsWith('http'))
          .toSet();
      final lint = lintScraperCode(code, capturedUrls: urls);
      if (lint.hasViolations) {
        say('❌ data-$name 代码审查未通过\n${lint.toMessage()}');
        widget.workflow.setLastError(lint.toMessage());
        return buf.toString();
      }
      if (lint.suspectedFakeData) {
        widget.workflow.setGuardFlag(GuardFlags.suspectedFakeData);
        say('⚠️ data-$name 命中疑似假数据 warning（已记 guard flag，批量注册前必须修正）');
      }

      final fields = candidate?.fields
              .map((f) => InferredField(
                  name: f.name, type: f.type, description: f.description))
              .toList() ??
          const <InferredField>[];
      final schema = InferredSchema(
        sourceUrl: candidate?.url ?? '',
        title: candidate?.displayName ?? name,
        fields: fields,
      );

      final validated = injectValidatorIntoCode(code);
      final pluginDir = p.join(resolvePluginsRoot(), 'data-$name');
      final dataResult = await _facade.generateAsDataPlugin(
        schema: schema,
        pluginName: name,
        outputDir: pluginDir,
        pythonCode: validated,
        dataTypeName: name,
        category: candidate?.category,
        displayName: candidate?.displayName,
        // Phase 6：字段 schema 落盘（含 sourceJsonPath 证据）
        fields: candidate?.fields.map((f) => f.toJson()).toList(),
      );
      if (!dataResult.success) {
        say('❌ data-$name 打包失败: ${dataResult.message}');
        return buf.toString();
      }
      say('✅ data-$name scraper.py + data/manifest.json 已生成');
      // D1 溯源：探索创建的数据源回写创建画板 + 来源
      _patchManifestProvenance(
        pluginDir,
        boardId: widget.boardId,
        createdBy: 'scraper-explore',
      );

      final configReg = ConfigRegister();
      final configResult = await configReg.generateConfig(
        pluginDir: pluginDir,
        fields: fields
            .map((f) => {
                  'name': f.name,
                  'type': f.type,
                  'description': f.description ?? '',
                })
            .toList(),
      );
      say('${configResult.success ? "✅" : "❌"} data-$name config/config.json');
      say('📁 data-$name 构建完毕 → `$pluginDir`');
    } catch (e) {
      say('❌ data-$name 构建异常: $e');
    }
    _saveSessions();
    return buf.toString();
  }

  /// register_batch 工具回调：批量热注册 + orch.get 验证（D6）。
  Future<String> _registerExploreBatch(List<String> names) async {
    final buf = StringBuffer();
    void say(String m) {
      if (mounted) _messages.add(ChatMessage.assistant(m));
      buf.writeln(m);
    }

    try {
      final ew = widget.exploreWorkflow;
      if (ew != null && ew.phase != ExplorePhase.registering) {
        ew.startRegistering();
      }

      // G6 Guardian 自动审查（Phase 3 复用）：注册前审 trace + 产物
      final verdict = await _guardianReview(GuardianReviewRequest(
        gate: 'G6',
        action: '批量注册 ${names.length} 个探索数据源'
            '（${names.map((n) => 'data-$n').join('/')}）到数据中心',
        arguments: jsonEncode({'names': names, 'mode': 'explore'}),
      ));
      if (verdict != null && !verdict.allow) {
        say('🛡️ Guardian 拒绝批量注册\n${verdict.reason}');
        widget.workflow.setLastError('G6 Guardian 拒绝批量注册: ${verdict.reason}');
        return buf.toString();
      }
      if (verdict != null && verdict.allow) {
        say('🛡️ Guardian 审查通过（risk=${verdict.assessment.riskLevel}）');
      }

      final orch = ref.read(dataOrchestratorProvider);
      var successCount = 0;
      for (final name in names) {
        final pluginDir = p.join(resolvePluginsRoot(), 'data-$name');
        say('🔗 注册 data-$name …');
        final lineBuf = StringBuffer();
        lineBuf.writeln('**$name**:');
        try {
          final registered = registerDataSourcesFromManifest(
            orch: orch,
            pluginDir: pluginDir,
            projectRoot: widget.projectRoot,
          );
          // 注册配置项 + 自动保存凭据默认值（复用 _hotRegister 逻辑）
          final configPath = p.join(pluginDir, 'config', 'config.json');
          if (File(configPath).existsSync()) {
            final configServer = ref.read(configHttpServerProvider);
            final cfg = registerConfigFromManifest(
              configServer: configServer,
              pluginDir: pluginDir,
            );
            if (cfg.count > 0) {
              lineBuf.writeln('- 📝 配置项 ${cfg.count} 个: ${cfg.registered.join(', ')}');
              if (cfg.savedDefaults.isNotEmpty) {
                final prefs = ref.read(sharedPreferencesProvider);
                for (final key in cfg.savedDefaults) {
                  final configJson = jsonDecode(
                      File(configPath).readAsStringSync()) as Map<String, dynamic>;
                  final settingsList =
                      (configJson['settings'] as List<dynamic>?) ?? [];
                  for (final item in settingsList) {
                    if (item is! Map<String, dynamic> || item['key'] != key) {
                      continue;
                    }
                    final defaultValue = item['default'] as String? ?? '';
                    if (defaultValue.isNotEmpty && !prefs.containsKey(key)) {
                      await prefs.setString(key, defaultValue);
                    }
                    break;
                  }
                }
                lineBuf.writeln('- 💾 凭据默认值已保存（${cfg.savedDefaults.length} 项）');
              }
            }
          }
          for (final typeName in registered) {
            try {
              final dataType = DataType<Map<String, dynamic>>(name: typeName);
              final data = await orch.get(dataType);
              if (data != null) {
                // Phase 5：非 null 之外，再核对返回结构与声明字段是否一致。
                final candidate = _findCandidate(typeName);
                final missing = candidate != null && candidate.fields.isNotEmpty
                    ? validateFetchedShape(data, candidate.fields)
                    : const <String>[];
                if (missing.isEmpty) {
                  lineBuf.writeln('- ✅ $typeName 拉取成功');
                  successCount++;
                } else {
                  lineBuf.writeln('- ⚠ $typeName 拉取成功但缺字段: '
                      '${missing.join(', ')}（结构与归类声明不一致，请修正脚本）');
                }
              } else {
                final status = orch.status(typeName);
                lineBuf.writeln('- ⚠ $typeName 返回 null'
                    '${status?.lastError != null ? ' · lastError: ${status!.lastError}' : ''}');
              }
            } catch (e) {
              lineBuf.writeln('- ❌ $typeName 拉取异常: $e');
            }
          }
        } catch (e) {
          lineBuf.writeln('- ❌ 注册失败: $e');
        }
        say(lineBuf.toString());
      }

      if (successCount > 0 && ew != null && ew.phase == ExplorePhase.registering) {
        ew.markDone();
      }
      say('🎉 批量注册完成：$successCount/${names.length} 个数据源验证通过'
          '${ew != null && ew.phase == ExplorePhase.done ? '\n✅ 探索流程全部完成' : ''}');

      // P1-2 经验 Journal：注册有产出即回写站点经验（下次探索注入复用）
      if (successCount > 0 && ew != null && ew.baseHost.isNotEmpty) {
        try {
          final domain = ew.baseHost;
          await ScraperJournal(baseDir: greenixJournalDir).append(JournalEntry(
            domain: domain,
            authMethod: inferAuthMethod(widget.workflow.logs),
            flow: '探索 ${ew.uniquePages} 页 · 构建 ${names.length} 个数据源'
                ' · 验证通过 $successCount 个',
            pitfalls: widget.workflow.errorMessage.trim(),
            keyParams: inferKeyParams(widget.workflow.logs, domain: domain),
            recordedAt: DateTime.now(),
          ));
          debugPrint('[ScraperAIPanel] 📔 已回写探索经验: $domain');
        } catch (e) {
          debugPrint('[ScraperAIPanel] ⚠ journal 回写失败: $e');
        }
      }
    } catch (e) {
      say('❌ 批量注册异常: $e');
    }
    _saveSessions();
    return buf.toString();
  }

  // ── Phase 2/3：探索模式登录验证 + 逐源执行验证 ──

  /// 截断长输出（防撑爆上下文，与工具输出契约一致）。
  String _truncateRunOutput(String s, {int maxChars = 3000}) {
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars)}\n…(截断 ${s.length - maxChars} 字符)';
  }

  /// 执行单个 Python 文件并返回 stdout/stderr 摘要（Phase 2/3 共用）。
  ///
  /// [requireJson]：true 时对 exitCode=0 的 stdout 做与平台一致的 JSON 校验
  /// （execute_built_source 用——数据源脚本输出必须是合法 JSON；登录验证
  /// verify_login_flow 输出为人类文本，不校验）。
  Future<String> _runPythonFile(String filePath,
      {bool requireJson = false}) async {
    try {
      final runner = await sharedPluginRunner;
      final r = await runner
          .runOnce(
            filePath,
            const [],
            workingDirectory: p.dirname(filePath),
            runtime: 'python',
            // 注入 AI/用户写入的环境变量（账号密码等凭据，set_env_var 写入）
            environment: _envStore.envForSubprocess(widget.workspaceDir),
          )
          .timeout(const Duration(seconds: 60));
      final stdout = r.stdout.trim();
      final stderr = r.stderr.trim();
      if (r.exitCode != 0) {
        return '❌ 执行失败 (exitCode=${r.exitCode})\n'
            '--- STDOUT ---\n${_truncateRunOutput(stdout)}\n'
            '--- STDERR ---\n${_truncateRunOutput(stderr)}\n'
            '请根据错误信息修正后重试。';
      }
      // 数据源脚本：exitCode=0 但 stdout 非合法 JSON → 明确回灌校验失败，
      // 避免 AI 误判「跑通即成功」（与定向模式 run_python_scraper 同语义）。
      if (requireJson) {
        final validation = validateScraperStdout(stdout);
        if (!validation.isValid) {
          return '❌ 执行成功 (exitCode=0) 但 JSON 输出校验失败：'
              '${validation.error}\n'
              '--- STDOUT ---\n${_truncateRunOutput(stdout)}\n'
              '→ 数据源脚本 main() 必须用 json.dumps(...) 输出合法 JSON'
              '（第一字节为 { 或 [），请修正后重新 build_selected_source。';
        }
      }
      final stderrPart = stderr.isEmpty ? '' : '\n--- STDERR ---\n${_truncateRunOutput(stderr)}';
      return '✅ 执行成功 (exitCode=0)\n'
          '--- STDOUT ---\n${_truncateRunOutput(stdout)}$stderrPart';
    } catch (e) {
      debugPrint('[ScraperAIPanel] 💥 执行 Python 异常: $e');
      return '[error: Python 执行异常: $e]';
    }
  }

  /// check_explore_ready 工具回调：生成探索环境诊断报告（区分
  /// 「AI 自身行为错误」vs「浏览器/环境未就绪」——修复 AI 误抱怨工具设计）。
  Future<String> _checkExploreReady() async {
    final buf = StringBuffer();
    final b = widget.webBridge;
    final ew = widget.exploreWorkflow;
    buf.writeln('## 探索环境诊断');
    buf.writeln('- 探索阶段: ${ew?.phase.name ?? '（无探索工作流）'}');
    buf.writeln('- WebView JS 通道: ${b != null && b.ready ? '✅ 就绪' : '❌ 未就绪'
        '（浏览器可能未加载完成，等待页面加载或 ask 用户刷新）'}');
    try {
      final url = await b?.currentUrl?.call();
      buf.writeln('- 当前页面: ${url == null || url.isEmpty ? '（未知）' : url}');
    } catch (_) {
      buf.writeln('- 当前页面: （获取失败）');
    }
    final wf = widget.workflow;
    buf.writeln('- 已捕获请求: ${wf.logs.length} 条'
        '（探索计数: ${ew?.requestsCaptured ?? 0}，按真实捕获日志同步）');
    buf.writeln('- 已访问页: ${ew?.uniquePages ?? 0} / ${ew?.limits.maxPages ?? 20}'
        ' · 请求上限: ${ew?.limits.maxRequests ?? 50}');
    buf.writeln('- 锁定域名: ${(ew?.baseHost ?? '').isEmpty ? '（未锁定）' : ew!.baseHost}');
    if (ew != null && ew.stallDetected) {
      buf.writeln('- ⚡ 空转熔断已触发: ${ew.stallMessage}');
    }
    // Python 可用性
    try {
      final py = await resolvePythonExe();
      buf.writeln('- Python 解释器: ${py == null ? '❌ 未找到' : '✅ $py'}');
    } catch (e) {
      buf.writeln('- Python 解释器: ❌ 探测失败: $e');
    }
    buf.writeln('- 已设置环境变量: ${_envStore.keys().length} 个'
        '（set_env_var 写入；list_env_vars 查看 key）');
    buf.writeln();
    buf.writeln('> 自检指引：JS 通道/页面未就绪 → 等页面加载或 ask 用户刷新；'
        '就绪但无捕获日志 → 是你的探索行为问题（navigate_get 访问数据接口）；'
        'Python 不可用 → 环境问题，ask 用户检查 Python 配置。');
    return buf.toString();
  }

  /// verify_login_flow 工具回调：写 login_check.py 并执行（Phase 2）。
  Future<String> _runLoginCheck(String code) async {
    try {
      // 注入锁定配置模板（若缺失），保证 _get_config 可读凭证。
      var finalized = code;
      if (!finalized.contains('def _get_config(key)')) {
        final injected = scraperConfigTemplate.replaceFirst(
          '{CREDENTIAL_PLACEHOLDER}',
          '# 按需声明：USERNAME = _get_config(\'SCRAPER_USERNAME\')',
        );
        finalized = '$injected\n$finalized';
      }
      final filePath = p.join(widget.workspaceDir, 'login_check.py');
      await File(filePath).writeAsString(finalized);
      debugPrint('[ScraperAIPanel] 🔑 登录验证脚本已写入: $filePath');
      return await _runPythonFile(filePath);
    } catch (e) {
      debugPrint('[ScraperAIPanel] 💥 登录验证失败: $e');
      return '[error: 登录验证执行异常: $e]';
    }
  }

  /// execute_built_source 工具回调：执行已构建脚本并回传结果（Phase 3）。
  Future<String> _executeBuiltSource(String name) async {
    try {
      final scriptPath =
          p.join(resolvePluginsRoot(), 'data-$name', 'data', 'scraper.py');
      final file = File(scriptPath);
      if (!file.existsSync()) {
        return '[error: 脚本不存在: $scriptPath（请先 build_selected_source 构建 data-$name）]';
      }
      debugPrint('[ScraperAIPanel] ▶️ 执行已构建脚本: $scriptPath');
      return await _runPythonFile(scriptPath, requireJson: true);
    } catch (e) {
      debugPrint('[ScraperAIPanel] 💥 执行 data-$name 异常: $e');
      return '[error: 执行 data-$name 脚本异常: $e]';
    }
  }

  /// 导出爬虫（.py）+ data/manifest.json。
  Future<void> exportPy() async {
    final dataName = _dataName ?? 'scraper';
    // 先用 basic 推断生成 InferredSchema（P1+ 将接入 Agent 智能推断）
    final schema = await _facade.analyzeSelection(widget.workflow.logs);
    final result = await _facade.generateAsDataPlugin(
      schema: schema,
      pluginName: dataName,
      outputDir: widget.workspaceDir,
      pythonCode: widget.workflow.pythonCode,
      dataTypeName: dataName,
    );
    if (mounted) {
      _messages.add(ChatMessage.assistant(
          result.success ? '✅ ${result.message}' : '❌ ${result.message}'));
      _saveSessions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 导出爬虫（.exe）+ data/manifest.json。
  Future<void> exportExe() async {
    setState(() => _isRunning = true);
    final dataName = _dataName ?? 'scraper';
    final exeResult = await exportAsExe(
      widget.workflow.pythonCode,
      widget.workspaceDir,
      () => resolvePythonExe(),
    );
    // .exe 编译后附加 manifest（script 恒为 scraper.py + runtime: python，
    // .exe 仅是用户显式导出的独立产物，不参与数据源注册）
    if (exeResult.success) {
      final schema = await _facade.analyzeSelection(widget.workflow.logs);
      await _facade.generateAsDataPlugin(
        schema: schema,
        pluginName: dataName,
        outputDir: widget.workspaceDir,
        dataTypeName: dataName,
      );
    }
    if (mounted) {
      setState(() => _isRunning = false);
      _messages.add(ChatMessage.assistant(
          exeResult.success ? '✅ ${exeResult.message}' : '❌ ${exeResult.message}'));
      _saveSessions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exeResult.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// AI 在工作流中拿到用户给定的产物根名后回写（取代原页面打开即弹的命名弹窗）。
  ///
  /// 修复（用户反馈 bug）：旧实现调用 `_switchOrCreateSession` →
  /// `controller.newSession()` / `setSession()`，会在 **工具执行中途** 取消并
  /// 清空/替换 Agent 会话（`newSession` 内部 `if (isRunning) cancel()`），
  /// 导致 `set_data_name` 的工具结果永远无法回填给 AI、AI 循环直接中断。
  ///
  /// 现在只做两件无副作用的事：
  /// 1. 记录 `_dataName`（导出/注册/插件目录立即生效）；
  /// 2. 把**当前会话**原地改名为该名称（保持会话名与数据名一致，
  ///    不创建新会话、不切换会话、不触碰 Agent 会话——正在运行的 AI 循环不被打断）。
  void setDataName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !mounted) return;
    setState(() => _dataName = trimmed);
    if (_currentIdx >= 0 && _currentIdx < _sessions.length) {
      final cur = _sessions[_currentIdx];
      final conflict = _sessions.any((s) => !identical(s, cur) && s.name == trimmed);
      if (!conflict) {
        cur.rename(trimmed);
      } else {
        debugPrint('[ScraperAIPanel] ⚠ 会话名 "$trimmed" 已被其它会话占用，仅记录 dataName');
      }
    }
    _saveSessions();
    debugPrint('[ScraperAIPanel] 🏷 产物根名已设定: dataName=$_dataName');
  }

  /// 分析前强制会话选择对话框。
  ///
  /// 列出所有已有会话（高亮当前），提供"创建新会话"入口。
  /// 返回选中会话的索引；null 表示用户取消。
  Future<int?> _showSessionPicker() async {
    // ⚠️ 同 _showNameDialog：controller 生命周期交给弹窗 State 管理
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SessionPickerDialog(
        sessions: List<_ScraperSession>.from(_sessions),
        currentIdx: _currentIdx,
        formatTime: _formatTime,
      ),
    );

    if (result == null) return null;   // 取消
    if (result is int) return result as int;  // 已有会话

    // result is String → 创建新会话
    _switchOrCreateSession(result as String);
    return _currentIdx;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  // ── ③ 生成插件（打包 scraper.py + 三件套 + 放入 plugins/）──

  /// 导出插件（打包 scraper.py + 三件套 + 放入 plugins/）并热注册、验证数据中心拉取。
  ///
  /// 返回**完整结果日志**（每步成功/失败详情）。日志既写入 UI 气泡（_messages），
  /// 也作为返回值——后者被 `export_and_register_scraper` 工具作为工具结果回灌给 AI，
  /// 让 `scraper.py 打包失败`、`lastError`、`拉取异常` 等平台期「检验失败」对 AI 可见（root cause B）。
  Future<String> _generatePlugin() async {
    setState(() => _isRunning = true);
    final buf = StringBuffer();
    // 同时写入 UI 气泡与回传缓冲，保证两端一致。
    void say(String m) {
      if (mounted) _messages.add(ChatMessage.assistant(m));
      buf.writeln(m);
    }

    say('🔧 **开始生成插件**...');
    try {
      final schema = await _facade.analyzeSelection(widget.workflow.logs);
      // 数据名称即一切：插件目录 data-{name}，manifest name = name
      final dataName = _dataName ?? 'scraper';
      final pluginDirName = 'data-$dataName';
      final workspaceDir = widget.workspaceDir;
      final pluginsDir = resolvePluginsRoot();
      final pluginDir = p.join(pluginsDir, pluginDirName);
      // 存到状态，供 _hotRegister 复用
      _pluginDir = pluginDir;
      debugPrint('[ScraperAIPanel] 🏷 插件目录: $pluginDir (data=$dataName)');

      // Step 1: 注入 JSON 验证器，直接打包 scraper.py（统一 .py 契约——
      // 不再编译 .exe：PyInstaller 产物在安卓无法 exec PE，桌面亦白背打包负担）。
      // pythonCode 常为空（AI 经 run_python_scraper 直接写盘），回退读取磁盘 scraper.py。
      var baseCode = widget.workflow.pythonCode;
      if (baseCode.trim().isEmpty) {
        final diskPy = File(p.join(workspaceDir, 'scraper.py'));
        if (diskPy.existsSync()) {
          baseCode = diskPy.readAsStringSync();
        }
      }
      if (baseCode.trim().isEmpty) {
        say('❌ 未找到 scraper.py 代码：请先用 run_python_scraper 生成并跑通脚本，再导出插件。');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }

      // ═══ G6 注册防线（A3/A5）：注册前强制 lint 磁盘/内存代码 ═══
      // violation → 拒绝注册（格式/安全硬伤）；suspectedFakeData 未清除 → 拒绝注册。
      final lintResult = lintScraperCode(
        baseCode,
        capturedUrls: widget.workflow.logs
            .map((l) => l.url)
            .where((u) => u.startsWith('http'))
            .toSet(),
      );
      if (lintResult.hasViolations) {
        say('❌ **代码审查未通过，拒绝注册**\n${lintResult.toMessage()}'
            '\n\n请修正后重新执行 scraper.py，再调用 export_and_register_scraper。');
        widget.workflow.setLastError(lintResult.toMessage());
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }
      if (lintResult.suspectedFakeData) {
        // 同步 guardFlags（若 hooks 漏标，这里兜底）
        widget.workflow.setGuardFlag(GuardFlags.suspectedFakeData);
      }
      if (widget.workflow.suspectedFakeData) {
        say('❌ **检测到疑似硬编码假数据未澄清/未修正，拒绝注册**。'
            '\n请向用户说明数据来源（如静态 JSON 页），经用户确认放行后再注册。');
        widget.workflow.setLastError('G6 拒绝注册：疑似假数据未清除');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }

      // ═══ G6 Guardian 自动审查（Phase 3 · A12/A13）：注册前审 trace + 产物 ═══
      // 单次 LLM 调用（审产物 + 关键 trace）；deny → 拒绝注册 + rationale 回灌 AI；
      // 失败/未接线 → null（fail-closed 走上方规则守卫，用户弹窗兜底）。
      final g6Verdict = await _guardianReview(GuardianReviewRequest(
        gate: 'G6',
        action: '注册 data-$dataName 插件（scraper.py + manifest + config）到数据中心',
        arguments: jsonEncode({'plugin_dir': pluginDirName, 'data_name': dataName}),
      ));
      if (g6Verdict != null && !g6Verdict.allow) {
        say('🛡️ **Guardian 拒绝注册**\n${g6Verdict.reason}');
        widget.workflow.setLastError('G6 Guardian 拒绝注册: ${g6Verdict.reason}');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }
      if (g6Verdict != null && g6Verdict.allow) {
        say('🛡️ Guardian 审查通过（risk=${g6Verdict.assessment.riskLevel}）');
      }

      final validatedCode = injectValidatorIntoCode(baseCode);

      // Step 1.5: 清理旧 .exe 残留（新契约只注册 .py）
      final staleExe = File(p.join(workspaceDir, 'data', 'scraper.exe'));
      if (staleExe.existsSync()) {
        try {
          staleExe.deleteSync();
          say('🧹 已清理旧 data/scraper.exe（新契约不再使用 .exe）');
        } catch (e) {
          debugPrint('[ScraperAIPanel] ⚠ 清理旧 scraper.exe 失败: $e');
        }
      }

      // Step 2: 打包 scraper.py + 生成 data/manifest.json
      //（facade 写入 workspaceDir/scraper.py → data/scraper.py，
      //  manifest 使用新契约 script: scraper.py + runtime: python）
      final dataResult = await _facade.generateAsDataPlugin(
        schema: schema,
        pluginName: dataName,
        outputDir: workspaceDir,
        pythonCode: validatedCode,
        dataTypeName: dataName,
      );
      if (!dataResult.success) {
        say('❌ scraper.py 打包失败: ${dataResult.message}');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }
      say('✅ scraper.py 已打包（含 JSON 验证器，script: scraper.py / runtime: python）');

      // Step 4: 生成 config/config.json
      final configReg = ConfigRegister();
      final configResult = await configReg.generateConfig(
        pluginDir: workspaceDir,
        fields: schema.fields.map((f) => {
          'name': f.name, 'type': f.type,
          'description': f.description ?? '',
        }).toList(),
      );
      say('${configResult.success ? "✅" : "❌"} config/config.json');

      // Step 5: 组装完整插件目录 → plugins/<name>/
      Directory(pluginDir).createSync(recursive: true);
      for (final sub in ['data', 'config', 'module']) {
        final src = Directory(p.join(workspaceDir, sub));
        if (src.existsSync()) {
          final dst = Directory(p.join(pluginDir, sub));
          if (dst.existsSync()) dst.deleteSync(recursive: true);
          _copyDirSync(src, dst);
        }
      }

      say('✅ **插件生成完毕** → `$pluginDir`\n自动执行热注册并验证数据中心拉取...');
      // D1 溯源：定向导出的数据源回写创建画板 + 来源
      _patchManifestProvenance(
        pluginDir,
        boardId: widget.boardId,
        createdBy: 'scraper-capture',
      );

      // 自动执行注册 + 验证（其日志一并累积回传给 AI）
      buf.write(await _hotRegister());
    } catch (e) {
      say('❌ 插件生成失败: $e');
    }
    if (mounted) setState(() => _isRunning = false);
    _saveSessions();
    return buf.toString();
  }

  /// D1 溯源：向 plugins/data-<name>/data/manifest.json 顶层写入
  /// boardId（创建画板）与 createdBy（scraper-explore / scraper-capture）。
  /// 附加字段不影响注册解析；失败静默。
  void _patchManifestProvenance(
    String pluginDir, {
    String? boardId,
    String? createdBy,
  }) {
    try {
      final manifestPath = p.join(pluginDir, 'data', 'manifest.json');
      final file = File(manifestPath);
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (boardId != null) json['boardId'] = boardId;
      if (createdBy != null) json['createdBy'] = createdBy;
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      debugPrint('[ScraperAIPanel] 🏷 manifest 溯源: boardId=$boardId createdBy=$createdBy');
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 写入 manifest 溯源字段失败: $e');
    }
  }

  /// 递归复制目录。
  static void _copyDirSync(Directory src, Directory dst) {
    dst.createSync(recursive: true);
    for (final entity in src.listSync()) {
      if (entity is File) {
        entity.copySync(p.join(dst.path, p.basename(entity.path)));
      } else if (entity is Directory) {
        _copyDirSync(entity, Directory(p.join(dst.path, p.basename(entity.path))));
      }
    }
  }

  // ── ④ 热注册 ──

  /// 热注册数据源 + 配置项，并验证数据中心 orch.get 拉取。
  ///
  /// ① 调用 [registerDataSourcesFromManifest] 注册数据源
  /// ② 调用 [registerConfigFromManifest] 注册 config/config.json 设置项到 ConfigHttpServer
  /// ③ 自动将凭据默认值写入 SharedPreferences
  /// ④ 自动验证 orch.get 拉取
  ///
  /// 返回**完整结果日志**（含 `lastError` / `拉取异常` / `返回 null` 等检验失败详情）。
  /// 日志既写入 UI 气泡，也返回给调用方回灌 AI（root cause B）。
  Future<String> _hotRegister() async {
    setState(() => _isRunning = true);
    final buf = StringBuffer();
    void say(String m) {
      if (mounted) _messages.add(ChatMessage.assistant(m));
      buf.writeln(m);
    }
    try {
      final pluginsDir = resolvePluginsRoot();
      // 复用 _generatePlugin 存入的插件目录；若单独点「注册」且未生成过则回退到用户命名
      final pluginDir = _pluginDir ?? p.join(pluginsDir, 'data-${_dataName ?? 'scraper'}');
      final dataManifestPath = p.join(pluginDir, 'data', 'manifest.json');
      if (!File(dataManifestPath).existsSync()) {
        say('⚠️ 未找到 $dataManifestPath，请先点击"插件"按钮生成。');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }

      // ① 注册数据源
      final orch = ref.read(dataOrchestratorProvider);
      final registered = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: pluginDir,
        projectRoot: widget.projectRoot,
      );

      // ② 注册配置项到 ConfigHttpServer + 自动保存凭据默认值
      final configPath = p.join(pluginDir, 'config', 'config.json');
      if (File(configPath).existsSync()) {
        final configServer = ref.read(configHttpServerProvider);
        final cfg = registerConfigFromManifest(
          configServer: configServer,
          pluginDir: pluginDir,
        );
        if (cfg.count > 0) {
          say('📝 **配置项注册** (${cfg.count} 项): ${cfg.registered.join(', ')}');

          // ③ 自动保存凭据默认值到 SharedPreferences
          if (cfg.savedDefaults.isNotEmpty) {
            final prefs = ref.read(sharedPreferencesProvider);
            for (final key in cfg.savedDefaults) {
              // 读取 config.json 中声明的 default 值
              final configJson = jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
              final settingsList = (configJson['settings'] as List<dynamic>?) ?? [];
              for (final item in settingsList) {
                if (item is! Map<String, dynamic>) continue;
                if (item['key'] != key) continue;
                final defaultValue = item['default'] as String? ?? '';
                if (defaultValue.isNotEmpty && !prefs.containsKey(key)) {
                  await prefs.setString(key, defaultValue);
                  stderr.writeln('[ScraperAIPanel] 💾 自动保存凭证 $key = ${defaultValue.length > 8 ? '${defaultValue.substring(0, 8)}…' : defaultValue}');
                }
                break;
              }
            }
            say('💾 **凭据已保存** (${cfg.savedDefaults.length} 项)');
          }
        }
      }

      say('✅ **热注册完成** (${registered.length} 个类型)。正在验证数据中心拉取...');

      // 自动验证：调 orch.get() 拉取数据，失败时获取详细状态日志
      final verifyResults = <String>[];
      for (final typeName in registered) {
        final verifyBuf = StringBuffer();
        verifyBuf.writeln('**$typeName**:');
        try {
          final dataType = DataType<Map<String, dynamic>>(name: typeName);
          final data = await orch.get(dataType);
          if (data != null) {
            verifyBuf.writeln('- ✅ 拉取成功');
          } else {
            final status = orch.status(typeName);
            verifyBuf.writeln('- ⚠ 返回 null');
            if (status != null) {
              verifyBuf.writeln('- lastError: ${status.lastError ?? "(无)"}');
              verifyBuf.writeln('- connected: ${status.connected}');
              verifyBuf.writeln('- lastFetchedAt: ${status.lastFetchedAt?.toIso8601String() ?? "(从未)"}');
            }
          }
        } catch (e) {
          final status = orch.status(typeName);
          verifyBuf.writeln('- ❌ 拉取异常: $e');
          if (status != null) {
            verifyBuf.writeln('- lastError: ${status.lastError ?? "(无)"}');
            verifyBuf.writeln('- connected: ${status.connected}');
          }
        }
        verifyResults.add(verifyBuf.toString());
      }

      say('🎉 **全部完成**\n${verifyResults.join('\n')}');
    } catch (e) {
      say('❌ 热注册失败: $e');
    }
    if (mounted) setState(() => _isRunning = false);
    _saveSessions();
    return buf.toString();
  }

  // ── 手动按钮触发导出/注册：结果回灌 AI（root cause B）──

  /// 「插件」按钮：导出+注册，结果回灌 AI 自我修正。
  Future<void> _generatePluginFromButton() async {
    final log = await _generatePlugin();
    _feedbackExportResultToAgent('插件生成/热注册', log);
  }

  /// 「注册」按钮：热注册，并把检验失败结果回灌给 AI。
  Future<void> _hotRegisterFromButton() async {
    final log = await _hotRegister();
    _feedbackExportResultToAgent('热注册', log);
  }

  /// 把导出/注册的完整日志回灌给隔离 Agent。
  ///
  /// 仅在日志存在「检验失败」标记时回灌（[exportRegisterLogHasFailure]），
  /// 避免成功时打扰 AI；回灌后 AI 能看到平台期检验失败并修改代码/凭证后重试。
  void _feedbackExportResultToAgent(String title, String log) {
    if (_assembly == null) return;
    if (!exportRegisterLogHasFailure(log)) return;
    setState(() {
      _messages.add(ChatMessage.user('[系统] $title 检验失败，请分析并修复'));
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    _saveSessions();
    _assembly!.controller.send(
      '【$title 检验失败】以下是导出/注册与数据中心验证的完整日志。'
      '请分析失败原因（如 lastError、scraper.py 写入失败、orch.get 返回 null/拉取异常），'
      '修改 scraper 代码或凭证后，重新调用 export_and_register_scraper 工具重试'
      '（最多 5 轮）：\n\n$log',
    );
  }

  // ── 重置 ──

  void resetAll() {
    setState(() {
      _pendingText.clear();
      _pendingReasoning.clear();
      _dataName = null;
      _pluginDir = null;
    });
    widget.workflow.reset();
    widget.exploreWorkflow?.reset();
    // 重置后下次进入自动创建默认会话（旧记录保留）
  }

  /// 重抓确认后回调（A18）：由 generator_view 在用户确认重抓时调用。
  void onRestartCaptureConfirmed() {
    if (!mounted) return;
    setState(() {
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    _messages.add(ChatMessage.assistant(
        '🔄 **重新抓取开始**：请重新完成目标操作，完成后点击「操作完毕」。'));
    _saveSessions();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = widget.workflow.phase == ScraperPhase.done;

    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 8),
              Text(_error, textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 头部 ──
        _buildHeader(theme, done),
        // ── 消息列表 ──
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'AI 工作区就绪\n浏览目标网站后点击"分析日志"开始',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) => _buildMessage(theme, _messages[i]),
                ),
        ),
        // ── 输入栏 ──
        _buildInputBar(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          const Icon(Icons.smart_toy_rounded, size: 14),
          const SizedBox(width: 4),
          // ── 会话切换下拉 ──
          if (_sessions.isNotEmpty)
            PopupMenuButton<int>(
              initialValue: _currentIdx >= 0 ? _currentIdx : null,
              offset: const Offset(0, 32),
              padding: EdgeInsets.zero,
              tooltip: '切换会话',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _currentIdx >= 0 ? _sessions[_currentIdx].name : '无会话',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
              itemBuilder: (ctx) => [
                for (var i = 0; i < _sessions.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        if (i == _currentIdx)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
                          ),
                        Expanded(
                          child: Text(
                            _sessions[i].name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: i == _currentIdx ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text(
                          '${_sessions[i].messages.length} 条',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _deleteSession(i);
                          },
                          child: Icon(Icons.delete_outline, size: 16,
                              color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: _switchSession,
            ),
          if (_isRunning) ...[
            const SizedBox(width: 8),
            // B2：事件驱动的统一进度指示（真实反映 AI 步骤）
            AgentStepIndicator(
              running: true,
              currentTool: _currentTool,
              step: _stepCount,
              maxSteps: 50,
            ),
          ],
          // ⚠️ 禁止在此 Row 内使用 Spacer/Expanded：外层是横向
          // SingleChildScrollView（无界宽度），非零 flex 子项会抛
          // "RenderFlex children have non-zero flex but incoming width
          // constraints are unbounded" → 整页布局崩坏 → 黑屏。
          const SizedBox(width: 8),
          if (done) ...[
            // 导出 .py
            SizedBox(
              height: 24,
              child: TextButton.icon(
                onPressed: () => uiOp('ScraperAIPanel', '导出.py', () => exportPy()),
                icon: const Icon(Icons.save, size: 12),
                label: const Text('.py', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            ),
            // 导出 .exe（仅桌面：PyInstaller 子进程在安卓不可用）
            if (!Platform.isAndroid) ...[
              const SizedBox(width: 4),
              SizedBox(
                height: 24,
                child: TextButton.icon(
                  onPressed: () => uiOp('ScraperAIPanel', '导出.exe', () => exportExe()),
                  icon: const Icon(Icons.desktop_windows, size: 12),
                  label: const Text('.exe', style: TextStyle(fontSize: 10)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),
              ),
            ],
            const SizedBox(width: 4),
            // ③ 生成插件（ConfigRegister）
            SizedBox(
              height: 24,
              child: TextButton.icon(
                onPressed: () => uiOp('ScraperAIPanel', '生成插件', () => _generatePluginFromButton()),
                icon: const Icon(Icons.extension, size: 12),
                label: const Text('插件', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            ),
            const SizedBox(width: 4),
            // ④ 热注册
            SizedBox(
              height: 24,
              child: TextButton.icon(
                onPressed: () => uiOp('ScraperAIPanel', '热注册', () => _hotRegisterFromButton()),
                icon: const Icon(Icons.link, size: 12),
                label: const Text('注册', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            ),
          ],
          // 重置
          SizedBox(
            height: 24,
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 14),
              onPressed: resetAll,
              tooltip: '重置',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 6),
              child: Icon(Icons.smart_toy_rounded, size: 16),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.35,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: isUser
                  ? Text(
                      msg.text,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface,
                        height: 1.4,
                      ),
                    )
                  : MarkdownRenderer(
                      text: msg.text,
                      useCard: false,
                      fontScale: 0.73,
                      padding: EdgeInsets.zero,
                    ),
            ),
          ),
          if (isUser) ...[
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 6),
              child: Icon(Icons.person, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 探索模式：开始探索按钮（D1）；定向模式：分析日志按钮
          if (widget.mode == ScraperBoardMode.explore)
            SizedBox(
              height: 30,
              child: FilledButton.icon(
                onPressed: (_assembly != null &&
                        !_isRunning &&
                        widget.exploreWorkflow?.phase == ExplorePhase.idle)
                    ? startExplore
                    : null,
                icon: const Icon(Icons.travel_explore_rounded, size: 12),
                label: const Text('开始探索', style: TextStyle(fontSize: 10)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            )
          else
            SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                onPressed: (_assembly != null &&
                        !_isRunning &&
                        widget.workflow.hasLogs)
                    ? triggerAnalyze
                    : null,
                icon: const Icon(Icons.analytics_rounded, size: 12),
                label: const Text('分析日志', style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          const SizedBox(width: 6),
          // 输入框
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: _assembly != null && !_isRunning,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                hintText: '输入消息...',
                hintStyle: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              onSubmitted: (_) => _sendMessage(),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 6),
          // 发送 / 停止（A17：AI 运行时停止按钮，阶段保留）
          if (_isRunning)
            SizedBox(
              height: 30,
              child: IconButton(
                onPressed: _cancelRunning,
                icon: Icon(Icons.stop_rounded, size: 16,
                    color: theme.colorScheme.error),
                tooltip: '停止（保留当前阶段）',
                style: IconButton.styleFrom(
                  minimumSize: const Size(30, 30),
                  padding: EdgeInsets.zero,
                  backgroundColor:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                ),
              ),
            )
          else
            SizedBox(
              height: 30,
              child: IconButton.filled(
                onPressed:
                    (_assembly != null && !_isRunning) ? _sendMessage : null,
                icon: const Icon(Icons.send_rounded, size: 14),
                style: IconButton.styleFrom(
                  minimumSize: const Size(30, 30),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          // 确认操作完毕（A18：冻结日志快照 + 锁定 WebView）——仅定向模式
          if (widget.mode != ScraperBoardMode.explore) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: '确认操作完毕：冻结日志快照并锁定 WebView，AI 据此分析',
              child: SizedBox(
                height: 30,
                child: OutlinedButton.icon(
                  onPressed: (_assembly != null &&
                          !_isRunning &&
                          widget.workflow.hasLogs &&
                          !widget.workflow.snapshotFrozen)
                      ? _confirmCaptureDone
                      : null,
                  icon: const Icon(Icons.lock_rounded, size: 12),
                  label: Text(
                    widget.workflow.snapshotFrozen
                        ? '已锁定 (${widget.workflow.snapshot.length})'
                        : '操作完毕',
                    style: const TextStyle(fontSize: 10),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════ ChatMessage model ═══════

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;

  const ChatMessage({required this.role, required this.text});

  factory ChatMessage.user(String text) =>
      ChatMessage(role: 'user', text: text);

  factory ChatMessage.assistant(String text) =>
      ChatMessage(role: 'assistant', text: text);

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      ChatMessage(role: json['role'] as String, text: json['text'] as String);
}

// ═══════ ScraperSession 模型 ═══════

/// 一个命名会话，存储完整的 AI 对话记录 + Agent 内部 Session 快照。
class _ScraperSession {
  /// 会话名（= 数据名称；AI 经 `set_data_name` 锁定后原地改名，不切换会话）。
  String name;

  /// 会话稳定唯一 id（双向绑定画板用）。
  ///
  /// 新建时生成 `session_<微秒时间戳>`；旧数据无 id 时按 name 派生兜底，
  /// 保证与画板 `sessionIds` 交叉校验有稳定锚点。
  final String id;

  /// 所属画板 id（双向绑定：会话 → 画板）。加载时校验，与所在画板不符即孤儿。
  final String? boardId;

  final List<ChatMessage> messages;
  final DateTime createdAt;
  /// Agent 内部 Session 的 JSON 快照（切换会话时保存/恢复 LLM 上下文）。
  Map<String, dynamic>? agentSessionJson;

  _ScraperSession({required this.name, String? id, String? boardId})
      : id = id ?? 'session_${DateTime.now().microsecondsSinceEpoch}',
        boardId = boardId,
        messages = [],
        createdAt = DateTime.now(),
        agentSessionJson = null;

  /// 原地改名（AI 经 `set_data_name` 锁定数据名称后调用）。
  ///
  /// ⚠️ 只改会话名，**不**切换/重建 Agent 会话——避免在工具执行中途
  /// 打断正在运行的 AI 循环（旧实现切换会话导致 set_data_name 结果丢失）。
  void rename(String newName) {
    name = newName;
  }

  _ScraperSession._({
    required this.name,
    required this.id,
    required this.boardId,
    required this.messages,
    required this.createdAt,
    this.agentSessionJson,
  });

  factory _ScraperSession.fromJson(Map<String, dynamic> json) =>
      _ScraperSession._(
        name: json['name'] as String,
        id: (json['id'] as String?) ??
            'session_${json['name']}', // 旧数据无 id → name 派生兜底
        boardId: (json['boardId'] as String?)?.isNotEmpty == true
            ? json['boardId'] as String
            : null,
        messages: (json['messages'] as List<dynamic>?)
                ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        agentSessionJson:
            json['agentSession'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        if (boardId != null) 'boardId': boardId,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        if (agentSessionJson != null) 'agentSession': agentSessionJson,
      };
}

/// 分析会话选择弹窗（controller 生命周期由 State 管理）。
class _SessionPickerDialog extends StatefulWidget {
  const _SessionPickerDialog({
    required this.sessions,
    required this.currentIdx,
    required this.formatTime,
  });

  final List<_ScraperSession> sessions;
  final int currentIdx;
  final String Function(DateTime) formatTime;

  @override
  State<_SessionPickerDialog> createState() => _SessionPickerDialogState();
}

class _SessionPickerDialogState extends State<_SessionPickerDialog> {
  final TextEditingController _newNameCtrl = TextEditingController();

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = widget.sessions;
    return AlertDialog(
      title: const Text('📋 选择分析会话'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请选择本次分析使用的数据会话',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('暂无会话，请在下方创建新会话',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(sessions.length, (i) {
                      final s = sessions[i];
                      final isCurrent = i == widget.currentIdx;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isCurrent ? Icons.circle : Icons.circle_outlined,
                          size: isCurrent ? 16 : 18,
                          color: isCurrent ? theme.colorScheme.primary : null,
                        ),
                        title: Text(s.name,
                            style: TextStyle(
                                fontWeight:
                                    isCurrent ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text(
                            '${s.messages.length} 条消息 · ${widget.formatTime(s.createdAt)}'),
                        onTap: () => Navigator.pop(context, i),
                      );
                    }),
                  ),
                ),
              ),
            const Divider(height: 24),
            const Text('或创建新会话：',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNameCtrl,
                    decoration: const InputDecoration(
                      hintText: '新数据名称（如 courses）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      final name = v.trim();
                      if (name.isNotEmpty) Navigator.pop(context, name);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final name = _newNameCtrl.text.trim();
                    if (name.isNotEmpty) Navigator.pop(context, name);
                  },
                  child: const Text('创建'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

// ═══════ _ScraperAsker ═══════

/// AskTool 的 UI 实现（A11）：把结构化问题渲染为多选弹窗，返回用户选择。
class _ScraperAsker implements agent.Asker {
  final ScraperAIPanelState _state;

  _ScraperAsker(this._state);

  @override
  Future<List<agent.AskAnswer>> ask(agent.AskRequest request) async {
    final ctx = _state.context;
    if (!_state.mounted) return const [];

    // 构建每个问题的状态：当前选中项（多选集合 / 单选 index）
    final selected = <String, Set<int>>{};
    for (final q in request.questions) {
      selected[q.id] = <int>{};
    }

    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text('AI 提问（${request.questions.length}）',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final q in request.questions) ...[
                      if (q != request.questions.first)
                        const Divider(height: 24),
                      Text(q.header.isNotEmpty ? q.header : '问题',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(dialogCtx)
                                  .colorScheme
                                  .primary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(q.question,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      for (var i = 0; i < q.options.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(q.options[i].label,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: q.options[i].description.isNotEmpty
                              ? Text(q.options[i].description,
                                  style: const TextStyle(fontSize: 11))
                              : null,
                          value: q.multiSelect
                              ? selected[q.id]!.contains(i)
                              : selected[q.id]!.length == 1 &&
                                  selected[q.id]!.contains(i),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (q.multiSelect) {
                                if (checked == true) {
                                  selected[q.id]!.add(i);
                                } else {
                                  selected[q.id]!.remove(i);
                                }
                              } else {
                                selected[q.id] = checked == true
                                    ? {i}
                                    : <int>{};
                              }
                            });
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('关闭（暂不回答）'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) {
      // 用户关闭 → 不返回任何回答（AskTool 解释为"不要替我做决定"）
      return const [];
    }

    return [
      for (final q in request.questions)
        agent.AskAnswer(
          questionId: q.id,
          selected: [
            for (final i in selected[q.id] ?? <int>{}) q.options[i].label,
          ],
        ),
    ];
  }
}

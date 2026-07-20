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
import 'package:evergreen_base/core/utils/python_env.dart';

import 'scraper_workflow.dart';
import 'scraper_tools.dart';
import 'scraper_skill_const.dart' show scraperSkillBody;
import 'scraper_exporter.dart';
import 'scraper_json_validator.dart';
import 'scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/config_register.dart';
import 'package:evergreen_base/core/config/register_config.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/services/ui_operation_log.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';

// ═══════ ScraperAIPanel ═══════

/// 爬虫 AI 面板——隔离 Agent + 专用工具 + 定制 Skill。
class ScraperAIPanel extends ConsumerStatefulWidget {
  final ScraperWorkflow workflow;
  final String moduleId;
  final String slotKey;
  final String workspaceDir;
  final String projectRoot;

  const ScraperAIPanel({
    super.key,
    required this.workflow,
    required this.moduleId,
    required this.slotKey,
    required this.workspaceDir,
    required this.projectRoot,
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

  /// DeepSeek Provider（用于 AI 字段推断，P1 B3）。
  agent.DeepSeekProvider? _provider;

  // ── 流式累积 ──
  final StringBuffer _pendingText = StringBuffer();
  final StringBuffer _pendingReasoning = StringBuffer();
  bool _isRunning = false;
  String _currentTool = '';

  bool _initialized = false;
  String _error = '';

  // ── 阶段 UI 占位 ──
  String _phaseBanner = '';

  // ── 插件生成命名 ──
  /// 用户指定的数据名称（如 `courses`）。
  /// 插件目录自动推导为 `data-{name}`，manifest name = name。
  String? _dataName;
  /// 最近一次生成的插件目录路径（供 _hotRegister 复用）。
  String? _pluginDir;
  /// 是否已完成首次命名（页面打开时强制填写一次，之后不再询问）。
  bool _named = false;

  // ── 多会话持久化 ──
  String get _sessionsPath => p.join(widget.workspaceDir, 'scraper_sessions.json');

  void _loadSessions() {
    try {
      final file = File(_sessionsPath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        _sessions = json
            .map((s) => _ScraperSession.fromJson(s as Map<String, dynamic>))
            .toList();
        _currentIdx = _sessions.isNotEmpty ? 0 : -1;
        debugPrint('[ScraperAIPanel] 📂 加载 ${_sessions.length} 个会话');
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
        _sessions[_currentIdx].agentSessionJson = _assembly!.controller.session.toJson();
      }
    } catch (_) {
      // Agent 可能正在初始化/销毁，安全忽略
    }
    // ② 写入文件
    try {
      final file = File(_sessionsPath);
      file.writeAsStringSync(jsonEncode(_sessions.map((s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('[ScraperAIPanel] ⚠ 保存会话失败: $e');
    }
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
      final session = _ScraperSession(name: name);
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
  void _restoreAgentSession(int idx) {
    if (_assembly == null) return;
    final target = _sessions[idx];
    try {
      if (target.agentSessionJson != null) {
        final restored = agent.Session.fromJson(target.agentSessionJson!);
        _assembly!.controller.setSession(restored);
        // 确保 system prompt 是当前最新版本（旧快照中的 prompt 可能过期）
        _assembly!.controller.setSystemPrompt(scraperSkillBody);
        debugPrint('[ScraperAIPanel] ♻ 恢复 Agent Session (${restored.messages.length} 条)');
      } else {
        _assembly!.controller.newSession();
        debugPrint('[ScraperAIPanel] 🆕 无历史快照，新建 Agent Session');
      }
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
    _loadSessions();
    _initAgent();
  }

  @override
  void dispose() {
    _saveSessions();
    _eventSub?.cancel();
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

      final provider = agent.DeepSeekProvider(
        dio: Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )),
        apiKey: apiKey,
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

      _assembly = AgentAssembly.fromConfig(
        moduleId: assemblyModuleId,
        config: agentConfig,
        sharedProvider: provider,
        globalSkillIndex: skillIdx,
        globalMemoryStore: memStore,
        seedTools: createScraperTools(
          workspaceDir: widget.workspaceDir,
          projectRoot: widget.projectRoot,
          resolvePython: () => resolvePythonExe(),
          getLogsSummary: () => widget.workflow.requestLogsSummary(),
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
        ),
      );

      // 设置系统提示（从 Skill 文件加载）
      _assembly!.controller.setSystemPrompt(scraperSkillBody);

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
      // 页面打开后自动弹出命名对话框（仅此一次）→ 创建/切换会话
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureNamed());
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
          setState(() => _currentTool = event.tool!.name);
        }
        break;

      case agent.EventKind.toolResult:
        setState(() => _currentTool = '');
        final tool = event.tool;
        if (tool != null) {
          final output = (tool.output ?? tool.error ?? '').trim();
          if (tool.isError) {
            _pendingText.writeln('\n⚠️ **${tool.name} 执行失败**\n');
            _pendingText.writeln('```\n${output.length > 500 ? '${output.substring(0, 500)}...' : output}\n```\n');
          } else if (tool.name == 'run_python_scraper') {
            // 根据退出码判断成功/失败（不再依赖特定字符串）
            final success = output.contains('✅ 爬虫执行成功') ||
                output.contains('✅ 命令执行成功') ||
                (!output.contains('❌') && !output.contains('Traceback') && output.isNotEmpty);
            if (success) {
              widget.workflow.markDone();
              _pendingText.writeln('\n🎉 **爬虫执行成功！**');
            } else if (output.contains('❌') || output.contains('Traceback')) {
              widget.workflow.setPythonOutput(output);
              if (widget.workflow.canDebug) {
                widget.workflow.startDebugging();
              }
            }
          } else if (tool.name == 'run_terminal_command') {
            final success = output.contains('✅ 命令执行成功') ||
                (!output.contains('❌') && !output.contains('Traceback') && output.isNotEmpty);
            if (success) {
              widget.workflow.markDone();
              _pendingText.writeln('\n🎉 **终端命令执行成功！**');
            } else if (output.contains('❌') || output.contains('Traceback')) {
              widget.workflow.setPythonOutput(output);
              if (widget.workflow.canDebug) {
                widget.workflow.startDebugging();
              }
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

    _inputCtrl.clear();
    setState(() {
      _messages.add(ChatMessage.user(text));
      _pendingText.clear();
      _pendingReasoning.clear();
    });
    _saveSessions();

    _assembly!.controller.send(text);
  }

  /// 触发分析流程。
  ///
  /// 分析日志：先强制选择会话，再发起 AI 分析。
  void triggerAnalyze() async {
    if (_assembly == null || _isRunning || !widget.workflow.hasLogs) return;

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
      _named = true;
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
    // .exe 编译后附加 manifest（script 自动切换为 scraper.exe）
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

  // ── 一次性命名 ──

  /// 页面打开时自动调用，弹出单字段命名对话框 → 创建或切换到对应会话。
  /// 仅当 `_named == false` 时生效，填完后永不再问。
  Future<void> _ensureNamed() async {
    if (_named || !mounted) return;
    final name = await _showNameDialog();
    if (name == null || !mounted) return;
    setState(() {
      _dataName = name;
      _named = true;
    });
    _switchOrCreateSession(name);
    debugPrint('[ScraperAIPanel] 🏷 首次命名: dataName=$_dataName');
  }

  /// 单字段命名对话框（仅数据名称）。
  ///
  /// 用户填写数据名称（如 `courses`），插件目录自动为 `data-{name}`，
  /// manifest name 与数据名称一致。
  ///
  /// 返回数据名称字符串，或 null（用户取消，不应发生因为 barrierDismissible: false）。
  Future<String?> _showNameDialog() async {
    final ctrl = TextEditingController(text: _dataName ?? '');

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🔧 命名数据源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请为本次爬虫数据命名。后续插件目录、manifest 均以此为基准自动生成。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '数据名称',
                  hintText: '例如: courses, zju_grades',
                  helperText: '→ 插件目录: plugins/data-{名称}/\n→ manifest name: {名称}',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) {
                  final name = v.trim();
                  if (name.isNotEmpty) Navigator.pop(ctx, name);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, name);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );

    ctrl.dispose();
    return result;
  }

  /// 分析前强制会话选择对话框。
  ///
  /// 列出所有已有会话（高亮当前），提供"创建新会话"入口。
  /// 返回选中会话的索引；null 表示用户取消。
  Future<int?> _showSessionPicker() async {
    final sessions = List<_ScraperSession>.from(_sessions);
    final currentIdx = _currentIdx;
    final newNameCtrl = TextEditingController();

    // 返回值：null=取消, int=已有会话索引, String=新会话名称
    Object? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('📋 选择分析会话'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请选择本次分析使用的数据会话', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('暂无会话，请在下方创建新会话', style: TextStyle(color: Colors.grey)),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(sessions.length, (i) {
                          final s = sessions[i];
                          final isCurrent = i == currentIdx;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isCurrent ? Icons.circle : Icons.circle_outlined,
                              size: isCurrent ? 16 : 18,
                              color: isCurrent ? theme.colorScheme.primary : null,
                            ),
                            title: Text(s.name,
                              style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text('${s.messages.length} 条消息 · ${_formatTime(s.createdAt)}'),
                            onTap: () {
                              result = i;
                              Navigator.pop(ctx);
                            },
                          );
                        }),
                      ),
                    ),
                  ),
                const Divider(height: 24),
                const Text('或创建新会话：', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newNameCtrl,
                        decoration: const InputDecoration(
                          hintText: '新数据名称（如 courses）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          final name = v.trim();
                          if (name.isNotEmpty) {
                            result = name;
                            Navigator.pop(ctx);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        final name = newNameCtrl.text.trim();
                        if (name.isNotEmpty) {
                          result = name;
                          Navigator.pop(ctx);
                        }
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    newNameCtrl.dispose();

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

  // ── ③ 生成插件（编译 .exe + 三件套 + 放入 plugins/）──

  /// 导出插件（编译 .exe + 三件套 + 放入 plugins/）并热注册、验证数据中心拉取。
  ///
  /// 返回**完整结果日志**（每步成功/失败详情）。日志既写入 UI 气泡（_messages），
  /// 也作为返回值——后者被 `export_and_register_scraper` 工具作为工具结果回灌给 AI，
  /// 让 `.exe 编译失败`、`lastError`、`拉取异常` 等平台期「检验失败」对 AI 可见（root cause B）。
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
      final pluginsDir = p.join(widget.projectRoot, '..', 'plugins');
      final pluginDir = p.join(pluginsDir, pluginDirName);
      // 存到状态，供 _hotRegister 复用
      _pluginDir = pluginDir;
      debugPrint('[ScraperAIPanel] 🏷 插件目录: $pluginDir (data=$dataName)');

      // Step 1: 注入 JSON 验证器 + 编译 .exe（PyInstaller）
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
      final validatedCode = injectValidatorIntoCode(baseCode);
      final exeResult = await exportAsExe(
        validatedCode,
        workspaceDir,
        () => resolvePythonExe(),
      );
      if (!exeResult.success) {
        say('❌ .exe 编译失败: ${exeResult.message}');
        if (mounted) setState(() => _isRunning = false);
        return buf.toString();
      }
      say('✅ .exe 编译完成（含 JSON 验证器）');

      // Step 2: 复制 .exe 到 data/ 目录
      final dataDir = Directory(p.join(workspaceDir, 'data'));
      dataDir.createSync(recursive: true);
      final exeSrc = File(p.join(workspaceDir, 'dist', 'scraper.exe'));
      final exeDst = File(p.join(dataDir.path, 'scraper.exe'));
      if (exeSrc.existsSync()) {
        exeSrc.copySync(exeDst.path);
        say('✅ scraper.exe → data/scraper.exe');
      }

      // Step 3: 生成 data/manifest.json（script: scraper.exe）
      final dataResult = await _facade.generateAsDataPlugin(
        schema: schema,
        pluginName: dataName,
        outputDir: workspaceDir,
        dataTypeName: dataName,
      );
      say('${dataResult.success ? "✅" : "❌"} data/manifest.json');

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

      // 自动执行注册 + 验证（其日志一并累积回传给 AI）
      buf.write(await _hotRegister());
    } catch (e) {
      say('❌ 插件生成失败: $e');
    }
    if (mounted) setState(() => _isRunning = false);
    _saveSessions();
    return buf.toString();
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
      final pluginsDir = p.join(widget.projectRoot, '..', 'plugins');
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
      '请分析失败原因（如 lastError、.exe 编译失败、orch.get 返回 null/拉取异常），'
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
      _named = false;
      _pluginDir = null;
    });
    widget.workflow.reset();
    // 下次 _ensureNamed 将自动创建新会话或切换回同名会话（旧记录保留）
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
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
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
      child: Row(
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
                          child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        ),
                      ],
                    ),
                  ),
              ],
              onSelected: _switchSession,
            ),
          if (_isRunning) ...[
            const SizedBox(width: 4),
            const SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ],
          const Spacer(),
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
            const SizedBox(width: 4),
            // 导出 .exe
            SizedBox(
              height: 24,
              child: TextButton.icon(
                onPressed: () => uiOp('ScraperAIPanel', '导出.exe', () => exportExe()),
                icon: const Icon(Icons.desktop_windows, size: 12),
                label: const Text('.exe', style: TextStyle(fontSize: 10)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
              ),
            ),
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
          // 分析日志按钮
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              onPressed:
                  (_assembly != null && !_isRunning && widget.workflow.hasLogs)
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
          // 发送
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
  final String name;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  /// Agent 内部 Session 的 JSON 快照（切换会话时保存/恢复 LLM 上下文）。
  Map<String, dynamic>? agentSessionJson;

  _ScraperSession({required this.name})
      : messages = [],
        createdAt = DateTime.now(),
        agentSessionJson = null;

  _ScraperSession._({
    required this.name,
    required this.messages,
    required this.createdAt,
    this.agentSessionJson,
  });

  factory _ScraperSession.fromJson(Map<String, dynamic> json) =>
      _ScraperSession._(
        name: json['name'] as String,
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
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        if (agentSessionJson != null) 'agentSession': agentSessionJson,
      };
}

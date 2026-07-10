/// 爬虫生成器 AI 交互面板。
///
/// 右侧面板下半部分——提供 AI 聊天输入/输出。
/// 使用 AgentAssembly 隔离模式，注册爬虫专用工具，注入 Skill 系统提示。
library scraper_ai_panel;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
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
import '../../shared/widgets/markdown_renderer.dart';

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
  final List<ChatMessage> _messages = [];

  AgentAssembly? _assembly;
  StreamSubscription<agent.AgentEvent>? _eventSub;

  // ── 流式累积 ──
  final StringBuffer _pendingText = StringBuffer();
  final StringBuffer _pendingReasoning = StringBuffer();
  bool _isRunning = false;
  String _currentTool = '';

  bool _initialized = false;
  String _error = '';

  // ── 阶段 UI 占位 ──
  String _phaseBanner = '';

  @override
  void initState() {
    super.initState();
    _initAgent();
  }

  @override
  void dispose() {
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
      setState(() {
        _initialized = true;
        // 初始欢迎消息
        _messages.add(ChatMessage.assistant(
          '👋 **爬虫脚本生成器已就绪**\n\n'
          '我可以通过以下步骤帮你生成 Python 爬虫：\n\n'
          '1. **浏览目标网站** — 在左侧 WebView 中登录并操作\n'
          '2. **保存凭证** — 我会引导你设置凭据（平台配置 或 环境变量）\n'
          '3. **分析请求日志** — 我会分析后台捕获的 HTTP 请求\n'
          '4. **生成并验证爬虫** — 自动生成代码、终端执行、排除错误直到成功\n\n'
          '🔐 **凭证双保险**：生成的脚本内置双策略降级机制（HTTP 配置 → 环境变量兜底），'
          '确保即使平台配置同步有延迟也能正常运行。\n\n'
          '请先浏览目标网站，然后点击"分析日志"。',
        ));
      });
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
            // 解析 Python 执行结果，更新 workflow
            if (output.contains('✅ 爬虫执行成功') || output.contains('✅ 命令执行成功')) {
              widget.workflow.markDone();
              _pendingText.writeln('\n🎉 **爬虫执行成功！**');
            } else if (output.contains('❌ 爬虫执行失败') || output.contains('❌ 命令执行失败')) {
              widget.workflow.setPythonOutput(output);
              if (widget.workflow.canDebug) {
                widget.workflow.startDebugging();
              }
            }
          } else if (tool.name == 'run_terminal_command') {
            // 终端命令结果已在终端中展示，此处更新 workflow 状态
            if (output.contains('✅ 命令执行成功')) {
              widget.workflow.markDone();
              _pendingText.writeln('\n🎉 **终端命令执行成功！**');
            } else if (output.contains('❌ 命令执行失败')) {
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
        break;

      default:
        break;
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

    _assembly!.controller.send(text);
  }

  /// 触发分析流程。
  void triggerAnalyze() {
    if (_assembly == null || _isRunning || !widget.workflow.hasLogs) return;

    widget.workflow.startAnalyzing();

    final logsSummary = widget.workflow.requestLogsSummary();
    const prompt = '''
请分析以下 HTTP 请求日志。严格按 Skill 规定的流程执行，禁止跳步：

1. 识别登录流程和目标数据 API
2. 使用 save_credential 将凭证写入平台配置（若不可用，告知用户设置环境变量备用）
3. 生成完整的 scraper.py，**必须逐字包含 Skill 中的锁定配置模板**，只替换 {CREDENTIAL_PLACEHOLDER}
4. 用 run_terminal_command 在终端执行 `python scraper.py`，观察输出并调试

重要规则：
- 🔒 **锁定模板不可修改**：_get_config() 代码逻辑必须原样保留，你只能填写占位符处的变量声明
- 📟 **执行用终端**：run_terminal_command，用户可在终端面板实时看到结果
- 🤫 **少问问题**：日志中已有答案的信息不要追问（目标 API、登录方式、字段等），默认 JSON 输出、默认全部字段
- 🚫 **禁止硬编码**：凭证必须通过 _get_config() 读取（模板已内置双策略降级：HTTP → 环境变量）

## 当前捕获的请求日志

''';

    setState(() {
      _isRunning = true;
      _messages.add(ChatMessage.assistant(
        '🔍 **开始分析请求日志**（${widget.workflow.logs.length} 条）…',
      ));
    });

    _assembly!.controller.send(prompt + logsSummary);
  }

  /// 导出爬虫（.py）。
  Future<void> exportPy() async {
    final result = await exportAsPython(
      widget.workflow.pythonCode,
      widget.workspaceDir,
    );
    if (mounted) {
      _messages.add(ChatMessage.assistant(
          result.success ? '✅ ${result.message}' : '❌ ${result.message}'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 导出爬虫（.exe）。
  Future<void> exportExe() async {
    setState(() => _isRunning = true);
    final result = await exportAsExe(
      widget.workflow.pythonCode,
      widget.workspaceDir,
      () => resolvePythonExe(),
    );
    if (mounted) {
      setState(() => _isRunning = false);
      _messages.add(ChatMessage.assistant(
          result.success ? '✅ ${result.message}' : '❌ ${result.message}'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── 重置 ──

  void resetAll() {
    setState(() {
      _messages.clear();
      _pendingText.clear();
      _pendingReasoning.clear();
      _messages.add(ChatMessage.assistant(
        '🔄 **已重置**\n请重新浏览目标网站开始新的爬虫生成流程。',
      ));
    });
    widget.workflow.reset();
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
          Text(
            'AI 工作区',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                onPressed: exportPy,
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
                onPressed: exportExe,
                icon: const Icon(Icons.desktop_windows, size: 12),
                label: const Text('.exe', style: TextStyle(fontSize: 10)),
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
}

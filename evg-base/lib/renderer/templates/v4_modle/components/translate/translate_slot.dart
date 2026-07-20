/// PDF 翻译 Slot — Dock 4 区布局（参考 scraper_generator_view.dart）。
///
/// | 区域 | 占位 | 类比 scraper |
/// |------|------|--------------|
/// | 左上 60% | PDF 预览（PDF.js/iframe） | ScraperWebView |
/// | 左下     | 翻译日志终端              | ScraperTerminal |
/// | 右上 35% | 翻译队列面板（active/waiting/completed） | RequestLogPanel |
/// | 右下 65% | AI 控制台（ScraperAIPanel 模式） | ScraperAIPanel |
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/config/config.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/page_event_bus.dart';
import 'package:evergreen_base/core/services/translate_queue.dart';
import 'package:evergreen_base/core/services/pdf_translate_service.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';

class _ChatMessage {
  final String role;
  final String content;
  _ChatMessage.user(this.content) : role = 'user';
  _ChatMessage.assistant(this.content) : role = 'assistant';
}

class TranslateSlot extends ConsumerStatefulWidget {
  final String slotKey;
  final ComponentDescriptor config;
  final String moduleId;
  final ModuleDescriptor moduleDescriptor;
  final PageEventBus? pageEventBus;

  const TranslateSlot({
    super.key,
    required this.slotKey,
    required this.config,
    required this.moduleId,
    required this.moduleDescriptor,
    this.pageEventBus,
  });

  @override
  ConsumerState<TranslateSlot> createState() => _TranslateSlotState();
}

class _TranslateSlotState extends ConsumerState<TranslateSlot> {
  // 配置
  String _langIn = 'en';
  String _langOut = 'zh';
  String _model = 'deepseek-chat';
  bool _deepThinking = false;

  // 队列
  TranslateQueue? _queue;
  StreamSubscription<QueueEvent>? _queueSub;
  List<JobState> _waiting = [];
  List<JobState> _active = [];
  List<JobState> _completed = [];

  // 终端日志
  final List<String> _terminalLogs = [];
  final ScrollController _termScroll = ScrollController();

  // AI
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  AgentAssembly? _assembly;
  StreamSubscription<agent.AgentEvent>? _eventSub;
  final StringBuffer _pendingText = StringBuffer();
  bool _isRunning = false;
  bool _initialized = false;
  String _error = '';

  // 当前阶段
  String _currentStage = 'idle';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAgent());
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _queue?.dispose();
    _eventSub?.cancel();
    _assembly?.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _termScroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() {
      _langIn = prefs.getString('translate_lang_in') ?? 'en';
      _langOut = prefs.getString('translate_lang_out') ?? 'zh';
      _model = prefs.getString('translate_model') ?? 'deepseek-chat';
    });
  }

  Future<void> _saveSetting(String key, String value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(key, value);
  }

  Future<void> _initAgent() async {
    if (_initialized) return;
    final assemblyId = '${widget.moduleId}/${widget.slotKey}/translate';

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
      if (apiKey.isEmpty) {
        setState(() { _error = '未配置 DeepSeek API Key'; _initialized = true; });
        return;
      }

      final provider = agent.DeepSeekProvider(dio: Dio(), apiKey: apiKey);
      final workspace = greenixWorkspaceDir('ai-assistant');
      final translateDir = p.join(workspace, 'translate');
      final bundledPython = p.join(greenixPythonDir, 'python.exe');

      final seedTools = <agent.Tool>[
        PythonRunnerTool(
          pythonExePath: File(bundledPython).existsSync() ? bundledPython : 'python',
          pythonWorkDir: greenixPythonDir,
          workspaceDir: workspace,
        ),
        ReadFileTool(workspaceDir: workspace),
        WriteFileTool(workspaceDir: workspace),
      ];

      _assembly = AgentAssembly.fromConfig(
        moduleId: assemblyId,
        config: const {'max_steps': 50, 'temperature': 0.3},
        sharedProvider: provider,
        globalSkillIndex: ref.read(skillIndexProvider),
        globalMemoryStore: ref.read(memoryStoreProvider),
        seedTools: seedTools,
      );

      _assembly!.controller.setSystemPrompt('''
你是 PDF 翻译控制台助手。左侧已嵌入 PDF 预览、终端日志、翻译队列。
- 翻译脚本: $translateDir/pdf_translate.py
- Python: $bundledPython
- API Key: $apiKey
用户点击"开始翻译"按钮后，队列已自动调度。你只负责解释结果、处理异常、提供翻译建议。''');

      _eventSub = _assembly!.eventSink.stream.listen(_onAgentEvent);
    } catch (e) {
      setState(() { _error = 'Agent 初始化失败: $e'; _initialized = true; });
      return;
    }

    setState(() {
      _initialized = true;
      _messages.add(_ChatMessage.assistant('👋 **PDF 翻译控制台**\n\n左侧已就绪。点击「开始翻译」按钮启动翻译。'));
    });
  }

  void _onAgentEvent(agent.AgentEvent event) {
    if (!mounted) return;
    if (event.kind == agent.EventKind.text && event.text != null) {
      _pendingText.write(event.text);
      _flushAssistantBubble();
    } else if (event.kind == agent.EventKind.turnDone) {
      setState(() => _isRunning = false);
      _flushAssistantBubble();
    } else if (event.kind == agent.EventKind.turnStarted) {
      setState(() { _isRunning = true; _pendingText.clear(); });
    }
  }

  void _flushAssistantBubble() {
    final text = _pendingText.toString();
    if (text.isEmpty) return;
    if (_messages.isNotEmpty && _messages.last.role == 'assistant' && _isRunning) {
      _messages.last = _ChatMessage.assistant(text);
    } else {
      _messages.add(_ChatMessage.assistant(text));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendMessage() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _assembly == null || _isRunning) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _pendingText.clear();
    });
    _assembly!.controller.send(text);
  }

  // ── 翻译控制 ──

  Future<void> _pickAndTranslate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
    await _startTranslate(paths);
  }

  Future<void> _startTranslate(List<String> paths) async {
    setState(() => _currentStage = 'preparing');
    _appendLog('[${DateTime.now().toIso8601String()}] 启动翻译 (${paths.length} 文件)');

    // 环境检查
    final translateDir = p.join(greenixWorkspaceDir('ai-assistant'), 'translate');
    final scriptPath = p.join(translateDir, 'pdf_translate.py');
    final bundledPython = p.join(greenixPythonDir, 'python.exe');
    final python = File(bundledPython).existsSync() ? bundledPython : await resolvePythonExe();
    if (python == null) {
      _appendLog('[ERROR] 未找到 Python');
      return;
    }
    _appendLog('[OK] Python: $python');

    // 依赖检查
    final depsCheck = await Process.run(python, ['-c',
      'import sys; sys.path.insert(0, r"$translateDir"); '
      'from pdf2zh_next.high_level import do_translate_async_stream; print("OK")'
    ], workingDirectory: translateDir);
    if (depsCheck.exitCode != 0) {
      _appendLog('[INFO] 缺少依赖，开始安装: babeldoc pymupdf openai tomlkit');
      setState(() => _currentStage = 'installing_deps');
      final install = await Process.run(python, ['-m', 'pip', 'install',
        'babeldoc', 'pymupdf', 'openai', 'tomlkit'
      ]).timeout(const Duration(seconds: 300));
      if (install.exitCode != 0) {
        _appendLog('[ERROR] 依赖安装失败: ${install.stderr}');
        return;
      }
      _appendLog('[OK] 依赖安装完成');
    }

    // 创建翻译队列
    final prefs = ref.read(sharedPreferencesProvider);
    final apiKey = getSetting(prefs, 'DEEPSEEK_API_KEY');
    if (apiKey.isEmpty) {
      _appendLog('[ERROR] 未配置 DEEPSEEK_API_KEY');
      return;
    }

    final service = PdfTranslateService(scriptPath: scriptPath);
    final queue = TranslateQueue(
      service: service,
      apiKey: apiKey,
      model: _model,
      thinking: _deepThinking ? 'enabled' : 'disabled',
      maxParallel: 3,
    );
    queue.setLanguages(_langIn, _langOut);

    _queueSub?.cancel();
    _queueSub = queue.eventStream.listen(_onQueueEvent);
    setState(() {
      _queue = queue;
      _waiting = []; _active = []; _completed = [];
      _currentStage = 'translating';
    });

    queue.enqueueAll(paths);
  }

  void _onQueueEvent(QueueEvent event) {
    if (!mounted) return;
    if (event is QueueSnapshotEvent) {
      setState(() {
        _waiting = event.waiting;
        _active = event.active;
        _completed = event.completed;
        for (final job in event.completed) {
          if (job.status == JobStatus.done) {
            _appendLog('[DONE] ${job.inputName} → ${job.result?.dualPdfPath ?? job.result?.monoPdfPath ?? ''}');
          } else {
            _appendLog('[ERROR] ${job.inputName}: ${job.errorMessage}');
          }
        }
        if (event.waiting.isEmpty && event.active.isEmpty) {
          _currentStage = 'completed';
        }
      });
    } else if (event is QueueJobProgressEvent) {
      _appendLog('[${event.jobId.substring(0, 8)}] p${event.current}/${event.total} ${event.message}');
    }
  }

  void _appendLog(String msg) {
    setState(() => _terminalLogs.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_termScroll.hasClients) {
        _termScroll.animateTo(_termScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  void _openPdf(String path) {
    try { Process.start('cmd', ['/c', 'start', '', path]); } catch (_) {}
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: LayoutBuilder(builder: (context, c) {
        final isNarrow = c.maxWidth < 600;
        if (isNarrow) {
          // 窄屏：单列堆叠
          return SingleChildScrollView(
            child: Column(children: [
              _buildPdfPreview(c),
              const Divider(height: 1),
              _buildTerminal(c),
              const Divider(height: 1),
              _buildQueuePanel(c),
              const Divider(height: 1),
              SizedBox(height: 400, child: _buildAiPanel(c)),
            ]),
          );
        }
        // Dock 布局：左侧 60% / 右侧 40%
        return Row(children: [
          SizedBox(width: c.maxWidth * 0.6, child: Column(children: [
            Expanded(child: _buildPdfPreview(c)),
            _buildTerminal(c),
          ])),
          Container(width: 1, color: Theme.of(context).dividerColor),
          Expanded(child: Column(children: [
            Expanded(flex: 35, child: _buildQueuePanel(c)),
            Container(height: 1, color: Theme.of(context).dividerColor),
            Expanded(flex: 65, child: _buildAiPanel(c)),
          ])),
        ]);
      })),
      _buildStatusBar(),
    ]);
  }

  // ── 左上：PDF 预览 ──
  Widget _buildPdfPreview(BoxConstraints c) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.black26,
          child: Row(children: [
            const Icon(Icons.picture_as_pdf, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            const Text('PDF 预览', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.folder_open, size: 16, color: Colors.white70),
              tooltip: '选择 PDF 文件',
              onPressed: _pickAndTranslate,
            ),
          ]),
        ),
        Expanded(child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.picture_as_pdf, size: 48, color: Colors.white24),
            const SizedBox(height: 8),
            const Text('点击右上角文件夹图标选择 PDF', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            const Text('（或直接发送到 AI 控制台）', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        )),
      ]),
    );
  }

  // ── 左下：翻译日志终端 ──
  Widget _buildTerminal(BoxConstraints c) {
    return Container(
      height: 180,
      color: const Color(0xFF0A0A0A),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.black26,
          child: Row(children: [
            const Icon(Icons.terminal, size: 14, color: Colors.greenAccent),
            const SizedBox(width: 6),
            const Text('翻译日志终端', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            const Spacer(),
            Text('${_terminalLogs.length} 行', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
        ),
        Expanded(child: ListView.builder(
          controller: _termScroll,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: _terminalLogs.length,
          itemBuilder: (context, i) => Text(
            _terminalLogs[i],
            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
          ),
        )),
      ]),
    );
  }

  // ── 右上：翻译队列 ──
  Widget _buildQueuePanel(BoxConstraints c) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(children: [
            const Icon(Icons.queue, size: 14),
            const SizedBox(width: 6),
            const Text('翻译队列', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_active.isNotEmpty || _waiting.isNotEmpty)
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 6),
            Text('${_completed.length} 完成', style: const TextStyle(fontSize: 10)),
          ]),
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.all(4),
          children: [
            if (_active.isNotEmpty) _buildSection('🟢 进行中 (${_active.length})', _active, true),
            if (_waiting.isNotEmpty) _buildSection('⏳ 排队 (${_waiting.length})', _waiting, false),
            if (_completed.isNotEmpty) _buildSection('✅ 已完成 (${_completed.length})', _completed, false),
            if (_active.isEmpty && _waiting.isEmpty && _completed.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('暂无任务', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
          ],
        )),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            const Icon(Icons.translate, size: 12),
            const SizedBox(width: 4),
            const Text('翻译', style: TextStyle(fontSize: 11)),
            const Spacer(),
            DropdownButton<String>(
              value: _langIn, isDense: true, underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('EN', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'zh', child: Text('ZH', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'ja', child: Text('JA', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) { if (v != null) { setState(() => _langIn = v); _saveSetting('translate_lang_in', v); } },
            ),
            const Icon(Icons.arrow_forward, size: 12),
            DropdownButton<String>(
              value: _langOut, isDense: true, underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('ZH', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'en', child: Text('EN', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) { if (v != null) { setState(() => _langOut = v); _saveSetting('translate_lang_out', v); } },
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 18),
              tooltip: '开始翻译',
              onPressed: _pickAndTranslate,
              color: Theme.of(context).colorScheme.primary,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSection(String title, List<JobState> jobs, bool isActive) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(title, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      ...jobs.map((job) {
        if (isActive && job.totalPages > 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${job.inputName} p${job.currentPage}/${job.totalPages}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              LinearProgressIndicator(value: job.progress, minHeight: 3),
            ]),
          );
        }
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            job.status == JobStatus.done ? Icons.check_circle : job.status == JobStatus.error ? Icons.error : Icons.hourglass_empty,
            size: 14, color: job.status == JobStatus.error ? Colors.red : Colors.green,
          ),
          title: Text(job.inputName, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
          subtitle: job.result != null ? Text('${job.result!.totalSeconds.toStringAsFixed(1)}s · ${job.result!.totalTokens} tok', style: const TextStyle(fontSize: 9)) : null,
          trailing: job.result != null ? Row(mainAxisSize: MainAxisSize.min, children: [
            if (job.result!.dualPdfPath != null) IconButton(icon: const Icon(Icons.download, size: 14), onPressed: () => _openPdf(job.result!.dualPdfPath!)),
            if (job.result!.monoPdfPath != null) IconButton(icon: const Icon(Icons.file_download, size: 14), onPressed: () => _openPdf(job.result!.monoPdfPath!)),
          ]) : null,
        );
      }),
    ]);
  }

  // ── 右下：AI 控制台 ──
  Widget _buildAiPanel(BoxConstraints c) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error, style: const TextStyle(color: Colors.red, fontSize: 12)),
      ));
    }
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            const Icon(Icons.psychology, size: 14),
            const SizedBox(width: 6),
            const Text('AI 控制台', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_isRunning) SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          ]),
        ),
        Expanded(child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: _messages.length,
          itemBuilder: (context, i) {
            final msg = _messages[i];
            final isUser = msg.role == 'user';
            return Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
                decoration: BoxDecoration(
                  color: isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: MarkdownRenderer(text: msg.content, fontScale: 0.85, useCard: false),
              ),
            );
          },
        )),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _inputCtrl, minLines: 1, maxLines: 2,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onSubmitted: (_) => _sendMessage(),
            )),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _isRunning ? null : _sendMessage,
              icon: Icon(_isRunning ? Icons.hourglass_top : Icons.send, size: 18),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── 状态栏 ──
  Widget _buildStatusBar() {
    final totalSeconds = _completed.fold<double>(0, (s, j) => s + (j.result?.totalSeconds ?? 0));
    final totalTokens = _completed.fold<int>(0, (s, j) => s + (j.result?.totalTokens ?? 0));
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: _currentStage == 'translating' ? Colors.blue : _currentStage == 'completed' ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('阶段: $_currentStage', style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 16),
        Text('活跃: ${_active.length}', style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Text('排队: ${_waiting.length}', style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 12),
        Text('完成: ${_completed.length}', style: const TextStyle(fontSize: 11)),
        const Spacer(),
        if (totalSeconds > 0) Text('耗时: ${totalSeconds.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11)),
        if (totalTokens > 0) ...[const SizedBox(width: 12), Text('Token: $totalTokens', style: const TextStyle(fontSize: 11))],
      ]),
    );
  }
}

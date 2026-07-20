/// 技术规划编辑器 —— 主入口视图。
///
/// 三栏布局：Markdown 编辑器 | 实时预览 | AI 四模式面板。
/// 使用 ConsumerStatefulWidget 访问全局 Agent Riverpod 提供者。
///
/// AI 四模式：
/// - 补写（Complete）：AI 调研后续写缺失实现细节 → 幽灵文本
/// - 分析（Analyze）：AI 调研后输出只读风险分析报告 → 面板展示
/// - 改写（Revise）：AI 调研后输出完整改写稿 → diff 对比
/// - 一键润色（Polish）：AI 调研后全量重写为可执行方案 → 替换全文
///
/// Phase 2 集成：
/// - 幽灵文本补全浮层（Tab 采纳）
/// - 文档版本追溯（DocTraceService）
/// - 一键导出（DocExportService + AppBar 导出按钮）
/// - 自动保存（DocAutoSaveService，防抖 + 定时 + 退出保存）
/// - 仓库路径配置（RepoConfigService + RepoConfigPanel）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart' show ControllerState;

import 'models/tech_document.dart';
import 'models/tech_version.dart';
import 'models/trace_record.dart';
import 'view/md_editor.dart';
import 'view/md_preview_panel.dart';
import 'view/diff_review_bar.dart';
import 'view/ghost_text_overlay.dart';
import 'view/repo_config_panel.dart';
import 'ai/ai_assist_panel.dart';
import 'ai/ai_tech_skill.dart';
import 'services/doc_trace_service.dart';
import 'services/doc_export_service.dart';
import 'services/doc_autosave_service.dart';
import 'services/repo_config_service.dart';

/// 技术规划协同编辑器主视图。
///
/// 三栏布局 + Diff 对比栏（按需弹出）。
/// 通过 Riverpod ConsumerStatefulWidget 访问全局 Agent。
class TechPlannerView extends ConsumerStatefulWidget {
  /// 初始文档内容。
  final String initialContent;

  /// 文档标题。
  final String title;

  /// 是否显示 AI 面板（默认 true）。
  final bool showAiPanel;

  /// 目标代码仓库路径（Phase 2）。
  ///
  /// AI 在调研/补全代码前，会读取此路径下所有文件作为参考，
  /// 确保建议与现有代码库一致。
  final String? targetRepoPath;

  /// 模块 ID（Phase 2，用于自动保存和配置持久化）。
  ///
  /// 数据存储于 `.greenix/workspaces/<moduleId>/tech-plans/`。
  final String? moduleId;

  const TechPlannerView({
    super.key,
    this.initialContent = '',
    this.title = '未命名技术规划',
    this.showAiPanel = true,
    this.targetRepoPath,
    this.moduleId,
  });

  @override
  ConsumerState<TechPlannerView> createState() => _TechPlannerViewState();
}

class _TechPlannerViewState extends ConsumerState<TechPlannerView> {
  late TechDocument _doc;
  late DocTraceService _traceService;

  /// 自动保存服务（Phase 2）。
  DocAutoSaveService? _autosaveService;

  /// 仓库配置服务（Phase 2）。
  RepoConfigService? _repoConfigService;

  /// 当前已校验的仓库路径。
  String? _effectiveRepoPath;

  bool _aiPanelVisible = true;
  bool _isAnalyzing = false;
  String? _analysisError;
  TechAnalysisReport? _analysisReport;

  /// 当前 AI 工作模式。
  AiMode _aiMode = AiMode.analyze;

  /// 模式完成后的提示文本（补写/改写/润色完成时显示在面板中）。
  String? _completionResultText;

  /// AI 实时思考流文本（加载中时逐字显示）。
  String _streamingText = '';

  String? _diffOriginal;
  String? _diffProposed;

  /// 幽灵文本状态（Phase 2）。
  GhostTextState _ghostState = GhostTextState.empty;

  /// 当前活跃的追溯记录。
  TraceRecord? _currentTrace;

  /// 上一次内容快照（用于版本间 diff）。
  String _previousContent = '';

  StringBuffer? _pendingResponse;
  StreamSubscription<agent.AgentEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    final docId = 'tech-plan-${DateTime.now().millisecondsSinceEpoch}';
    _doc = TechDocument(
      id: docId,
      title: widget.title,
      content: widget.initialContent,
    );
    _previousContent = widget.initialContent;

    // ── Phase 2：初始化追溯服务 + 记录初始版本 ──
    _traceService = DocTraceService(documentId: docId);
    if (widget.initialContent.isNotEmpty) {
      _traceService.recordVersion(
        fullContent: widget.initialContent,
        changeType: VersionChangeType.initial,
        description: '初始文档',
      );
    }

    // ── Phase 2：初始化自动保存 + 仓库配置 ──
    _effectiveRepoPath = widget.targetRepoPath;
    if (widget.moduleId != null) {
      _autosaveService = DocAutoSaveService(
        moduleId: widget.moduleId!,
        documentId: docId,
      );
      _repoConfigService = RepoConfigService(moduleId: widget.moduleId!);

      // 自动保存：启动定时器
      _autosaveService!.start();

      // 从磁盘加载已保存的数据（若存在）
      _loadSavedData();
    }

    _aiPanelVisible = widget.showAiPanel;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _autosaveService?.dispose();
    super.dispose();
  }

  // ═══════ 数据加载 + 仓库配置（Phase 2） ═══════

  /// 从磁盘加载已保存的文档数据和仓库配置。
  Future<void> _loadSavedData() async {
    // 加载已保存文档
    final savedDoc = await _autosaveService?.loadSaved();
    if (savedDoc != null && mounted) {
      setState(() {
        _doc = savedDoc;
        _previousContent = savedDoc.content;
        // 若有保存的标题则使用
        if (savedDoc.title.isNotEmpty && savedDoc.title != '未命名技术规划') {
          // 保持初始标题
        }
      });
    }

    // 加载已保存的追溯记录
    final savedTraces = await _autosaveService?.loadTraceExport();
    if (savedTraces != null && savedTraces.isNotEmpty) {
      // 可在此恢复 _traceService 的状态（目前仅记录日志）
    }

    // 加载仓库配置
    final repoConfig = await _repoConfigService?.loadConfig();
    if (repoConfig != null &&
        repoConfig.hasValidConfig &&
        _effectiveRepoPath == null) {
      _effectiveRepoPath = repoConfig.localPath;
    }
  }

  /// 仓库配置变更回调（由 [RepoConfigPanel] 触发）。
  void _onRepoConfigChanged(RepoConfig config) {
    if (config.hasValidConfig) {
      setState(() => _effectiveRepoPath = config.localPath);
    } else if (config.validationStatus == RepoValidationStatus.unknown) {
      // 清空配置
      setState(() => _effectiveRepoPath = null);
    }
  }

  // ═══════ 内容变更 ═══════

  void _onContentChanged(String newContent) {
    setState(() {
      _doc.content = newContent;
      _doc.updatedAt = DateTime.now();
    });

    // 取消幽灵补全（手动编辑后消失）
    if (_ghostState.hasCompletion) {
      setState(() => _ghostState = GhostTextState.empty);
    }

    // ── Phase 2：触发自动保存（防抖） ──
    _autosaveService?.onContentChanged(
      newContent,
      traceExport: _traceService.exportJson(),
    );
  }

  // ═══════ Ghost Text（Phase 2） ═══════

  /// 设置幽灵文本补全建议。
  void _setGhostCompletion(String completionText) {
    setState(() {
      _ghostState = GhostTextState(completionText: completionText);
    });
  }

  /// Tab 采纳幽灵文本。
  void _onGhostAccept() {
    if (!_ghostState.hasCompletion) return;

    // 记录采纳追溯
    _traceService.recordTrace(
      triggerType: TraceTriggerType.ghostTabAdopt,
      contentSnapshot: _doc.content,
    );

    setState(() => _ghostState = GhostTextState.empty);
  }

  /// 继续输入 → 幽灵文本消失。
  void _onGhostDismiss() {
    if (!_ghostState.hasCompletion) return;
    setState(() => _ghostState = GhostTextState.empty);
  }

  // ═══════ AI 四模式 ═══════

  /// AI 模式切换 + 触发。
  void _onModeComplete() {
    _aiMode = AiMode.complete;
    _triggerAiAction();
  }

  void _onModeAnalyze() {
    _aiMode = AiMode.analyze;
    _triggerAiAction();
  }

  void _onModeRevise() {
    _aiMode = AiMode.revise;
    _triggerAiAction();
  }

  void _onModePolish() {
    _aiMode = AiMode.polish;
    _triggerAiAction();
  }

  /// 编辑器工具栏 @ai 触发 — 走分析模式。
  void _onEditorAiTrigger(String userQuery) {
    _aiMode = AiMode.analyze;
    _triggerAiAction(userQuery: userQuery);
  }

  /// 统一的 AI 请求发送。
  ///
  /// 根据 [_aiMode] 选择不同的 prompt，监听事件流，由 [_onAgentEvent] 统一路由。
  Future<void> _triggerAiAction({String userQuery = ''}) async {
    final fullText = _doc.content;
    if (fullText.trim().isEmpty) {
      setState(() => _analysisError = '文档为空，请先书写技术规划内容');
      return;
    }

    // ── 记录 AI 交互追溯 ──
    final triggerType = switch (_aiMode) {
      AiMode.complete => TraceTriggerType.toolbarAnalyze,
      AiMode.analyze => userQuery.isNotEmpty
          ? TraceTriggerType.atAiManual
          : TraceTriggerType.toolbarAnalyze,
      AiMode.revise => TraceTriggerType.toolbarAnalyze,
      AiMode.polish => TraceTriggerType.toolbarAnalyze,
    };
    final trace = _traceService.recordTrace(
      triggerType: triggerType,
      contentSnapshot: fullText,
      userQuery: userQuery,
    );
    _currentTrace = trace;

    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
      _analysisReport = null;
      _completionResultText = null;
      _streamingText = '';
      _diffOriginal = null;
      _diffProposed = null;
    });

    try {
      final controller = ref.read(agentControllerProvider);
      if (controller == null) {
        _traceService.recordDecision(trace.id, TraceDecision.rejected);
        _currentTrace = null;
        setState(() {
          _isAnalyzing = false;
          _analysisError = 'Agent 控制器未初始化，请检查 API Key 配置';
        });
        return;
      }

      // 根据模式构造 prompt
      final repoPath = _effectiveRepoPath;
      final hasRepo = repoPath != null && repoPath.isNotEmpty;

      final prompt = switch (_aiMode) {
        AiMode.complete => hasRepo
            ? aiCompletePromptWithRepo(fullText, repoPath!)
            : aiCompletePrompt(fullText),
        AiMode.analyze => hasRepo
            ? techAnalysisSkillBodyWithRepo(fullText, repoPath!)
            : techAnalysisSkillBody(fullText),
        AiMode.revise => hasRepo
            ? aiRevisePromptWithRepo(fullText, repoPath!)
            : aiRevisePrompt(fullText),
        AiMode.polish => hasRepo
            ? aiPolishPromptWithRepo(fullText, repoPath!)
            : aiPolishPrompt(fullText),
      };

      final queryText = userQuery.isNotEmpty
          ? '\n\n---\n\n用户指令：$userQuery'
          : '';

      _pendingResponse = StringBuffer();

      // 监听事件流
      _eventSub?.cancel();
      _eventSub = ref.read(agentEventStreamProvider)?.listen(_onAgentEvent);

      // 发送消息
      controller.send('$prompt$queryText');

    } catch (e) {
      if (_currentTrace != null) {
        _traceService.recordDecision(_currentTrace!.id, TraceDecision.rejected);
      }
      _currentTrace = null;

      setState(() {
        _isAnalyzing = false;
        _analysisError = '${_modeLabel(_aiMode)}失败: $e';
        _streamingText = '';
      });
    }
  }

  /// 模式感知的 Agent 事件处理器。
  void _onAgentEvent(agent.AgentEvent event) {
    if (!_isAnalyzing) return;

    if (event.kind == agent.EventKind.turnDone) {
      // 本轮完成——检查错误
      if (event.error != null) {
        _eventSub?.cancel();
        _eventSub = null;

        if (_currentTrace != null) {
          _traceService.recordDecision(
              _currentTrace!.id, TraceDecision.rejected);
        }
        _currentTrace = null;

        if (!mounted) return;
        setState(() {
          _isAnalyzing = false;
          _analysisError = event.error;
          _streamingText = '';
          _pendingResponse = null;
        });
        return;
      }

      // 成功——按模式路由响应
      final fullResponse = _pendingResponse?.toString() ?? '';
      _eventSub?.cancel();
      _eventSub = null;

      if (_currentTrace != null) {
        _traceService.recordDecision(
            _currentTrace!.id, TraceDecision.viewed);
      }
      _currentTrace = null;

      if (!mounted) return;

      // 清除流式文本
      _streamingText = '';

      switch (_aiMode) {
        case AiMode.complete:
          _handleCompleteResponse(fullResponse);
        case AiMode.analyze:
          _handleAnalyzeResponse(fullResponse);
        case AiMode.revise:
          _handleReviseResponse(fullResponse);
        case AiMode.polish:
          _handlePolishResponse(fullResponse);
      }
    } else if (event.kind == agent.EventKind.text) {
      _pendingResponse?.write(event.text ?? '');
      // 实时推送流式文本到 UI（思考可视化）
      setState(() {
        _streamingText = _pendingResponse?.toString() ?? '';
      });
    }
  }

  // ── 各模式响应处理 ──

  /// 补写：将 AI 续写文本设为幽灵文本。
  void _handleCompleteResponse(String response) {
    if (response.trim().isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _analysisError = 'AI 未返回有效补写内容，请重试';
        _pendingResponse = null;
      });
      return;
    }

    setState(() {
      _isAnalyzing = false;
      _completionResultText = '补写完成，在编辑器中查看幽灵文本（Tab 键采纳）';
      _pendingResponse = null;
    });

    // 设置幽灵文本
    _setGhostCompletion(response);
  }

  /// 分析：解析 JSON 报告。
  void _handleAnalyzeResponse(String response) {
    final report = TechAnalysisReport.fromJsonString(response);

    setState(() {
      _isAnalyzing = false;
      if (report.isEmpty) {
        _analysisError = 'AI 未返回有效分析结果，请重试';
      } else {
        _analysisReport = report;
      }
      _pendingResponse = null;
    });
  }

  /// 改写：将 AI 输出设为 diff 对比。
  void _handleReviseResponse(String response) {
    if (response.trim().isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _analysisError = 'AI 未返回有效改写内容，请重试';
        _pendingResponse = null;
      });
      return;
    }

    // 记录 diff 提案追溯
    final previousContent = _doc.content;
    _previousContent = previousContent;

    // 查找最近的 trace 记录 diff 结果
    final recentTraces = _traceService.traceRecords
        .where((t) => t.triggerType == TraceTriggerType.toolbarAnalyze)
        .toList();
    if (recentTraces.isNotEmpty) {
      final lastTrace = recentTraces.last;
      _traceService.recordDiffResult(lastTrace.id, allKept: false);
    }

    setState(() {
      _isAnalyzing = false;
      _diffOriginal = previousContent;
      _diffProposed = response;
      _aiPanelVisible = false; // 收起面板，展示 diff
      _pendingResponse = null;
    });
  }

  /// 一键润色：将 AI 输出设为 diff 对比（用户决定是否保留）。
  void _handlePolishResponse(String response) {
    if (response.trim().isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _analysisError = 'AI 未返回有效润色内容，请重试';
        _pendingResponse = null;
      });
      return;
    }

    // 记录 diff 提案追溯
    final previousContent = _doc.content;
    _previousContent = previousContent;

    final recentTraces = _traceService.traceRecords
        .where((t) => t.triggerType == TraceTriggerType.toolbarAnalyze)
        .toList();
    if (recentTraces.isNotEmpty) {
      final lastTrace = recentTraces.last;
      _traceService.recordDiffResult(lastTrace.id, allKept: false);
    }

    setState(() {
      _isAnalyzing = false;
      _diffOriginal = previousContent;
      _diffProposed = response;
      _aiPanelVisible = false; // 收起面板，展示 diff
      _pendingResponse = null;
    });
  }

  // ── Diff 对比 ──

  /// Diff 改写采纳回调。
  void _onDiffApplied(String mergedText) {
    // ── 记录版本 + diff 结果 ──
    final allKept = mergedText == _diffProposed && mergedText != _diffOriginal;

    final recentTraces = _traceService.traceRecords
        .where((t) => t.triggerType == TraceTriggerType.toolbarAnalyze ||
            t.triggerType == TraceTriggerType.atAiManual)
        .toList();
    if (recentTraces.isNotEmpty) {
      final lastTrace = recentTraces.last;
      _traceService.recordDiffResult(lastTrace.id, allKept: allKept);
      _traceService.recordDecision(
        lastTrace.id,
        allKept ? TraceDecision.accepted : TraceDecision.partial,
      );
    }

    // ── 记录 AI 改写版本 ──
    _traceService.recordVersion(
      fullContent: mergedText,
      previousContent: _doc.content,
      changeType: VersionChangeType.aiRevision,
      description: 'AI 改写采纳',
    );

    _previousContent = mergedText;

    setState(() {
      _doc.content = mergedText;
      _doc.updatedAt = DateTime.now();
      _diffOriginal = null;
      _diffProposed = null;
      _aiPanelVisible = true; // 恢复 AI 面板

      // 修改/改写完成后清除旧报告
      _analysisReport = null;
    });

    // ── diff 采纳后立即写入 JSON，确保硬盘与内存一致 ──
    _autosaveService?.onContentChanged(
      mergedText,
      traceExport: _traceService.exportJson(),
    );
  }

  // ═══════ 构建 ═══════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _buildAppBar(theme, colorScheme),
      body: Column(
        children: [
          // ── Phase 2：仓库路径配置栏（仅非 diff 模式） ──
          if (_diffOriginal == null && widget.moduleId != null)
            _buildRepoConfigBar(theme),

          // ── 主体三栏 + Diff ──
          Expanded(
            child: _diffOriginal != null && _diffProposed != null
                ? _buildDiffMode(theme, colorScheme)
                : _buildEditorMode(theme, colorScheme),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, ColorScheme colorScheme) {
    return AppBar(
      title: Text(_doc.title),
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      actions: [
        // ── Phase 2：导出按钮 ──
        if (_diffOriginal == null)
          PopupMenuButton<ExportFormat>(
            tooltip: '导出文档',
            icon: Icon(Icons.file_download_outlined,
                color: colorScheme.onSurfaceVariant),
            onSelected: _onExportSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ExportFormat.markdown,
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('Markdown'),
                  subtitle: Text('纯文本 .md'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: ExportFormat.html,
                child: ListTile(
                  leading: Icon(Icons.code_outlined),
                  title: Text('HTML'),
                  subtitle: Text('含样式 .html'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: ExportFormat.pdf,
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF'),
                  subtitle: Text('打印用 .pdf'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),

        // AI 面板开关
        if (_diffOriginal == null)
          IconButton(
            onPressed: () =>
                setState(() => _aiPanelVisible = !_aiPanelVisible),
            icon: Icon(
              _aiPanelVisible
                  ? Icons.psychology
                  : Icons.psychology_outlined,
              color: _aiPanelVisible
                  ? colorScheme.tertiary
                  : colorScheme.onSurfaceVariant,
            ),
            tooltip: _aiPanelVisible ? '隐藏 AI 面板' : '显示 AI 面板',
          ),

        const SizedBox(width: 8),
      ],
    );
  }

  /// 导出格式选择回调。
  Future<void> _onExportSelected(ExportFormat format) async {
    final exportService = DocExportService(
      document: _doc,
      traceService: _traceService,
    );

    // 构建默认文件名
    final sanitizedTitle = _doc.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final defaultDir = '${_doc.id}';
    final basePath = '$defaultDir/${sanitizedTitle}_$timestamp';

    try {
      // 简单输出到 temp 目录供演示
      final result = await exportService.exportToFile(format, basePath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '已导出 ${result.defaultExtension.toUpperCase()}（${result.byteSize} bytes）'),
          action: SnackBarAction(
            label: '确定',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Widget _buildEditorMode(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左：编辑器（含幽灵文本浮层）
        Expanded(
          flex: 2,
          child: MdEditor(
            initialContent: _doc.content,
            onChanged: _onContentChanged,
            onAiTriggered: _onEditorAiTrigger,
            ghostState: _ghostState,
            onGhostAccept: _onGhostAccept,
            onGhostDismiss: _onGhostDismiss,
          ),
        ),

        // 中：预览
        Expanded(
          flex: 2,
          child: MdPreviewPanel(
            content: _doc.content,
            title: '实时预览',
          ),
        ),

        // 右：AI 面板（四模式）
        if (_aiPanelVisible)
          AiAssistPanel(
            currentMode: _aiMode,
            report: _analysisReport,
            isLoading: _isAnalyzing,
            errorText: _analysisError,
            resultText: _completionResultText,
            streamingText: _streamingText,
            onComplete: _onModeComplete,
            onAnalyze: _onModeAnalyze,
            onRevise: _onModeRevise,
            onPolish: _onModePolish,
            onClose: () => setState(() => _aiPanelVisible = false),
            width: 360,
          ),
      ],
    );
  }

  Widget _buildDiffMode(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        // ── Diff 对比栏 ──
        Expanded(
          child: DiffReviewBar(
            original: _diffOriginal!,
            proposed: _diffProposed!,
            onApply: _onDiffApplied,
          ),
        ),
      ],
    );
  }

  /// Phase 2：仓库路径配置栏（可折叠）。
  Widget _buildRepoConfigBar(ThemeData theme) {
    return RepoConfigPanel(
      moduleId: widget.moduleId!,
      onConfigChanged: _onRepoConfigChanged,
    );
  }

  /// 模式中文标签（用于错误消息）。
  String _modeLabel(AiMode mode) => switch (mode) {
    AiMode.complete => '补写',
    AiMode.analyze => '分析',
    AiMode.revise => '改写',
    AiMode.polish => '一键润色',
  };
}

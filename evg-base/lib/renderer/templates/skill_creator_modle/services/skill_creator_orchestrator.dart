/// Skill 创作多 agent 编排器——流水线状态机 + 交涉协议 + 断点续做。
///
/// 流程（规划 agent 主导）：
///   asking(需求澄清) → planning(按来源拆任务) → collecting(深寻 agents 并行)
///   → accepting(验收/交涉 pass|revise|redo) → integrating(整合报告)
///   → creating(skill 创造) → finalizing(终验) → exporting(落 plugins/<id>/skill/)
///
/// 交涉协议：验收不通过时，规划 agent 对子 agent 打 revise/redo + 指令，
/// 重新派发；同一任务最多 [maxAttempts] 次，之后按「将就」通过并记录警告。
///
/// 断点续做：每步落盘会话（agentSession + uiMessages + 工作流快照），
/// 重启后 [resume] 从当前阶段继续；已完成（pass）的任务跳过、材料复用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/services/ocr_pipeline.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/paper_reading_modle/tools/pymupdf_tool.dart';

import '../models/skill_creator_models.dart';
import 'skill_creator_agents.dart';
import 'skill_creator_panel_manager.dart';

/// 同一任务最大执行次数（超过后「将就」通过）。
const int kMaxAttempts = 3;

/// 多 agent 编排器（ChangeNotifier，供 UI 监听阶段/进度）。
class SkillCreatorOrchestrator extends ChangeNotifier {
  final SkillCreatorPanelManager panelManager;
  final String panelId;
  final String instanceId;

  final String apiKey;
  final String baseUrl;
  final String model;
  final SkillIndex globalSkillIndex;
  final FileMemoryStore globalMemoryStore;
  final String? pythonPath;
  final String? ocrApiKey;

  /// 工作流状态（可序列化，断点续做）。
  SkillCreatorWorkflow _workflow;
  SkillCreatorWorkflow get workflow => _workflow;

  /// 规划 agent 会话历史（一会话一固定历史）。
  List<Map<String, dynamic>> _agentSession = [];
  List<Map<String, dynamic>> get agentSession => _agentSession;

  /// UI 消息（AI 面板展示）。
  List<Map<String, dynamic>> _uiMessages = [];
  List<Map<String, dynamic>> get uiMessages => _uiMessages;

  bool _busy = false;
  bool _cancelRequested = false;
  bool get busy => _busy;

  /// 当前正在执行的子 agent（任务 id → 状态文本），UI 展示。
  final Map<String, String> _agentStatus = {};
  Map<String, String> get agentStatus => Map.unmodifiable(_agentStatus);

  SkillCreatorOrchestrator({
    required this.panelManager,
    required this.panelId,
    required this.instanceId,
    required this.apiKey,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.model = 'deepseek-v4-flash',
    required this.globalSkillIndex,
    required this.globalMemoryStore,
    this.pythonPath,
    this.ocrApiKey,
    SkillCreatorWorkflow? initialWorkflow,
    List<Map<String, dynamic>>? initialSession,
    List<Map<String, dynamic>>? initialUi,
  }) : _workflow = initialWorkflow ?? SkillCreatorWorkflow() {
    if (initialSession != null) _agentSession = initialSession;
    if (initialUi != null) _uiMessages = initialUi;
  }

  /// 材料目录（全文/报告/skill 草稿落盘）。
  String get _workspaceDir => skillCreatorRootDir();
  String get _materialsDir => p.join(_workspaceDir, 'materials');

  agent.Provider get _provider =>
      buildDeepSeekProvider(apiKey: apiKey, baseUrl: baseUrl, model: model);

  OcrPipeline get _ocr => OcrPipeline(Dio(), null, ocrApiKey);

  // ═══════ 生命周期 ═══════

  /// 启动流水线（需求已确认）。
  Future<void> start(String requirement) async {
    if (_busy) return;
    _workflow.requirement = requirement.trim();
    _workflow.phase = SkillCreatorPhase.planning;
    _uiMessages.add({'role': 'user', 'text': '🎯 需求：$requirement'});
    _appendAgent('user', '用户需求：$requirement');
    _appendEvent('info', '开始多 agent 流水线');
    _saveSession();
    await runPipeline();
  }

  /// 断点续做：从当前阶段继续（已完成任务跳过、材料复用）。
  Future<void> resume() async {
    if (_busy) return;
    if (_workflow.phase == SkillCreatorPhase.idle ||
        _workflow.phase == SkillCreatorPhase.done) {
      return;
    }
    // error 状态：恢复到失败前「下一个待执行」阶段（resumePhase），
    // 否则 runPipeline 的 while 会因 phase==error 直接跳过、什么都不重跑。
    if (_workflow.phase == SkillCreatorPhase.error) {
      final rp = _workflow.resumePhase;
      _workflow.phase = (rp == null ||
              rp == SkillCreatorPhase.idle ||
              rp == SkillCreatorPhase.done)
          ? SkillCreatorPhase.planning
          : rp;
    }
    _appendEvent('info', '断点续做：从 ${_workflow.phase.name} 阶段继续');
    _saveSession();
    await runPipeline();
  }

  /// 重置工作流（清空任务/材料/产出，保留面板）。
  void reset() {
    _workflow = SkillCreatorWorkflow();
    _uiMessages = [];
    _agentSession = [];
    _agentStatus.clear();
    panelManager.resetSession(panelId, instanceId);
    notifyListeners();
  }

  // ═══════ 流水线驱动 ═══════

  /// 从当前阶段开始跑完剩余流程。
  Future<void> runPipeline() async {
    if (_busy) return;
    final endpoint = Uri.tryParse(baseUrl);
    if (apiKey.trim().isEmpty || baseUrl.trim().isEmpty || endpoint == null || endpoint.host.isEmpty || endpoint.userInfo.isNotEmpty || !{'http', 'https'}.contains(endpoint.scheme.toLowerCase())) {
      _workflow.phase = SkillCreatorPhase.error;
      _appendEvent('error', '需要接入 DeepSeek/OpenAI-compatible 接口后才能运行深度搜索（请检查 API Key 和 Base URL）。');
      _saveSession();
      notifyListeners();
      return;
    }
    _busy = true;
    _cancelRequested = false;
    notifyListeners();
    try {
      var guard = 0;
      while (_workflow.phase != SkillCreatorPhase.done &&
          _workflow.phase != SkillCreatorPhase.error &&
             guard < 10) {
        // 记录断点：当前阶段即「下一个待执行」阶段，供异常后 resume 恢复。
        _workflow.resumePhase = _workflow.phase;
        if (_cancelRequested) {
          _appendEvent('warn', '流水线已由用户停止，可从当前阶段续做。');
          break;
        }
        guard++;
        switch (_workflow.phase) {
          case SkillCreatorPhase.planning:
            await _plan();
            continue;
          case SkillCreatorPhase.collecting:
            await _collect();
            continue;
          case SkillCreatorPhase.accepting:
            await _acceptAndNegotiate();
            continue;
          case SkillCreatorPhase.integrating:
            await _integrate();
            continue;
          case SkillCreatorPhase.creating:
            await _createSkill();
            continue;
          case SkillCreatorPhase.finalizing:
            await _finalize();
            continue;
          case SkillCreatorPhase.exporting:
            await _export();
            continue;
          case SkillCreatorPhase.idle:
          case SkillCreatorPhase.asking:
          case SkillCreatorPhase.done:
          case SkillCreatorPhase.error:
            return;
        }
      }
    } catch (e) {
      debugPrint('[SkillCreator] ⚠ 流水线错误: $e');
      _workflow.phase = SkillCreatorPhase.error;
      _appendEvent('error', '流水线错误：$e（可重试）');
      _saveSession();
    } finally {
      _busy = false;
      _agentStatus.clear();
      notifyListeners();
    }
  }

  /// 请求在当前 Tool/任务完成后停止后续阶段。
  void cancelPipeline() {
    if (!_busy) return;
    _cancelRequested = true;
    _appendEvent('warn', '已请求停止流水线，正在等待当前任务收尾...');
    notifyListeners();
  }

  /// 只重试单个失败的深寻任务，保留其他任务和已入库材料。
  Future<void> retryTask(String taskId) async {
    if (_busy) return;
    final task = _workflow.task(taskId);
    if (task == null || task.status != TaskStatus.failed) return;
    task.status = TaskStatus.pending;
    task.verdict = TaskVerdict.none;
    task.feedback = '';
    _workflow.phase = SkillCreatorPhase.collecting;
    _appendEvent('info', '手动重试深寻任务：${task.query}', agentId: task.id);
    _saveSession();
    await runPipeline();
  }

  /// 批量重试所有失败任务，已完成任务和材料保持不变。
  Future<void> retryFailedTasks() async {
    if (_busy) return;
    final failed = _workflow.tasks.where((t) => t.status == TaskStatus.failed).toList();
    if (failed.isEmpty) return;
    for (final task in failed) {
      task.status = TaskStatus.pending;
      task.verdict = TaskVerdict.none;
      task.feedback = '';
    }
    _workflow.phase = SkillCreatorPhase.collecting;
    _appendEvent('info', '批量重试 ${failed.length} 个失败深寻任务');
    _saveSession();
    await runPipeline();
  }

  Future<void> retryMaterialOcr(String materialId) async {
    final material = _workflow.material(materialId);
    if (material == null || material.localPath == null || _busy) return;
    material.processingError = null;
    material.readability = 'pending';
    _appendEvent('info', '手动重试 OCR：${material.title}');
    await _processMaterial(material);
    _saveSession();
    notifyListeners();
  }

  // ═══════ 阶段实现 ═══════

  /// ① 规划：按来源拆分任务。
  Future<void> _plan() async {
    _appendEvent('info', '规划 agent：按来源拆分采集任务...');
    final plans = await planTasks(
      provider: _provider,
      requirement: _workflow.requirement,
    );
    _workflow.tasks = plans.take(10).map((m) {
      final source = SearchSource.values.firstWhere(
          (s) => s.name == m['source'],
          orElse: () => SearchSource.web);
      return SearchTask(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}_${_workflow.tasks.length + plans.indexOf(m)}',
        source: source,
        query: (((m['query'] as String?) ?? '').trim().length > 4096)
            ? ((m['query'] as String?) ?? '').trim().substring(0, 4096)
            : ((m['query'] as String?) ?? '').trim(),
      );
    }).toList();

    _appendEvent('info',
        '规划完成：${_workflow.tasks.length} 个深寻任务（${_workflow.tasks.map((t) => searchSourceLabel(t.source)).join(' / ')}）');
    for (final t in _workflow.tasks) {
      _appendEvent('info', '  · [${searchSourceLabel(t.source)}] ${t.query}');
    }
    _workflow.phase = SkillCreatorPhase.collecting;
  }

  /// ② 采集：深寻 agents 并行执行未完成任务。
  Future<void> _collect() async {
    final pending = _workflow.tasks
        .where((t) => !(t.status == TaskStatus.done &&
            t.verdict == TaskVerdict.pass))
        .toList();
    if (pending.isEmpty) {
      _workflow.phase = SkillCreatorPhase.accepting;
      return;
    }

    _appendEvent('info', '深寻 agents 开始并行采集（${pending.length} 个任务）...');
    _workflow.phase = SkillCreatorPhase.collecting;

    final runner = DeepSearchRunner(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      globalSkillIndex: globalSkillIndex,
      globalMemoryStore: globalMemoryStore,
      workspaceRoot: _workspaceDir,
      pythonPath: pythonPath,
      ocrApiKey: ocrApiKey,
    );
    // C 阶段：采集前记录 OCR 能力，扫描版材料失败时用户能看到真实原因。
    try {
      final readiness = await OcrPipeline(Dio(), null, ocrApiKey).checkReadiness();
      _appendEvent('info', 'OCR 就绪：${readiness.summarize()}');
    } catch (e) {
      _appendEvent('warn', 'OCR 就绪检查失败：$e');
    }

    // 并行执行（共享 Provider，各任务独立 AgentAssembly）
    await Future.wait(pending.map((task) async {
      _agentStatus[task.id] = 'running';
      notifyListeners();
      task.status = TaskStatus.running;
      task.attempts++;
      _saveSession();

      final result = await runner.run(
        task: task,
        feedback: task.feedback,
        onEvent: (e) {
          if (e.kind == agent.EventKind.notice && e.text != null) {
            _agentStatus[task.id] = e.text!;
            notifyListeners();
          }
        },
      );

      if (result.error != null) {
        task.status = TaskStatus.failed;
        _agentStatus[task.id] = 'failed';
        _appendEvent('error', '深寻[${searchSourceLabel(task.source)}]失败：${result.error}',
            agentId: task.id);
      } else {
        task.status = TaskStatus.done;
        task.resultSummary = result.summary;
        _agentStatus.remove(task.id);
        _appendEvent('info',
            '深寻[${searchSourceLabel(task.source)}]完成：${result.materials.length} 份材料',
            agentId: task.id);

        // 材料入库 + 全文提取（PDF → 文本，扫描版降级 OCR）
        for (final rm in result.materials) {
          if (_workflow.materials.length >= 1000) {
            _appendEvent('warn', '材料总量已达 1000 条上限，跳过后续材料', agentId: task.id);
            break;
          }
          final m = MaterialItem(
            id: 'mat_${DateTime.now().millisecondsSinceEpoch}_${_workflow.materials.length}',
            source: task.source,
            title: rm['title']?.toString() ?? '未命名',
            url: rm['url']?.toString() ?? '',
            type: rm['type']?.toString() ?? 'article',
            localPath: rm['localPath'] as String?,
            authors: rm['authors'] as String?,
            year: rm['year'] as String?,
            summary: rm['summary']?.toString() ?? '',
          );
          _workflow.materials.add(m);
          task.materialIds.add(m.id);
          await _processMaterial(m);
        }
        _appendEvent('info',
            '材料[${searchSourceLabel(task.source)}]入库：${result.materials.length} 份（可读 ${_workflow.materials.where((m) => m.readability == 'ok' || m.readability == 'ocr').length} 份）',
            agentId: task.id);
      }
      notifyListeners();
    }));

    _workflow.phase = SkillCreatorPhase.accepting;
    _appendEvent('info', '全部深寻任务结束，进入验收阶段');
  }

  /// ③ 验收 + 交涉：规划 agent 逐个裁决，revise/redo 重新派发。
  Future<void> _acceptAndNegotiate() async {
    _workflow.phase = SkillCreatorPhase.accepting;

    var rounds = 0;
    while (rounds < kMaxAttempts + 2) {
      rounds++;
      final unpassed = _workflow.tasks
          .where((t) => t.verdict != TaskVerdict.pass)
          .toList();
      if (unpassed.isEmpty) break;

      for (final task in unpassed) {
        final decision = await acceptTask(
          provider: _provider,
          requirement: _workflow.requirement,
          task: task,
          resultSummary: task.resultSummary,
          materialCount: task.materialIds.length,
        );
        final verdict = switch (decision['verdict']?.toString()) {
          'revise' => TaskVerdict.revise,
          'redo' => TaskVerdict.redo,
          _ => TaskVerdict.pass,
        };
        final feedback = decision['feedback']?.toString() ?? '';

        if (verdict == TaskVerdict.pass) {
          task.verdict = TaskVerdict.pass;
          task.feedback = feedback;
          _appendEvent('info', '验收通过：[${searchSourceLabel(task.source)}] ${task.query}',
              agentId: task.id);
          continue;
        }

        // revise / redo → 交涉（返工）
        task.attempts++;
        if (task.attempts >= kMaxAttempts) {
          task.verdict = TaskVerdict.pass;
          task.feedback = '已达最大执行次数，按「将就」通过。${verdict.name} 原因：$feedback';
          _appendEvent('warn',
              '[${searchSourceLabel(task.source)}] 已达 ${kMaxAttempts} 次上限，将就通过（${verdict.name}: $feedback）',
              agentId: task.id);
          continue;
        }

        task.status = TaskStatus.pending;
        task.verdict = TaskVerdict.none;
        task.feedback = feedback;
        _appendEvent('negotiation',
            '规划 agent → 深寻[${searchSourceLabel(task.source)}]：${verdict.name == TaskVerdict.redo ? '返工' : '修订'}（第 ${task.attempts} 次）原因：$feedback',
            agentId: task.id);
      }

      // 有任务需重新采集 → 回到 collecting
      if (_workflow.tasks.any((t) => t.status == TaskStatus.pending)) {
        _workflow.phase = SkillCreatorPhase.collecting;
        _appendEvent('info', '有任务需返工/修订，重新派发深寻 agents...');
        await _collect();
        _workflow.phase = SkillCreatorPhase.accepting;
        continue;
      }
    }

    // 全数通过 → 进入整合
    _appendEvent('info', '验收完成：${_workflow.tasks.length} 个任务全部通过');
    _workflow.phase = SkillCreatorPhase.integrating;
  }

  /// ④ 整合：整合 agent 依据材料撰写报告。
  Future<void> _integrate() async {
    _workflow.phase = SkillCreatorPhase.integrating;
    _appendEvent('info', '整合 agent 开始撰写报告（${_workflow.materials.length} 份材料）...');

    final readable = _workflow.materials
        .where((m) => m.readability == 'ok' || m.readability == 'ocr')
        .toList();
    final report = await writeReport(
      provider: _provider,
      requirement: _workflow.requirement,
      materials: readable,
    );

    final reportPath = p.join(_workspaceDir, 'report.md');
    File(reportPath).writeAsStringSync(report);
    _workflow.reportPath = reportPath;
    _appendEvent('info', '整合报告完成（${report.length} 字）→ $reportPath');

    _workflow.phase = SkillCreatorPhase.creating;
  }

  /// ⑤ skill 创造：基于报告组织排布，生成可落盘格式。
  Future<void> _createSkill() async {
    _workflow.phase = SkillCreatorPhase.creating;
    _appendEvent('info', 'skill 创造 agent 组织排布中...');

    final report = _workflow.reportPath != null &&
            File(_workflow.reportPath!).existsSync()
        ? File(_workflow.reportPath!).readAsStringSync()
        : '';
    if (report.isEmpty) throw StateError('整合报告缺失，无法创造 skill');

    final raw = await singleRound(
      provider: _provider,
      systemPrompt: _skillCreationSystemPrompt,
      userPrompt: '用户需求：${_workflow.requirement}\n\n'
          '整合报告（素材底稿）：\n$report\n\n'
          '请据此生成最终 Skill（只输出完整 Markdown）。',
      timeout: const Duration(minutes: 15),
    );

    final data = agent.SkillRewriter.parseOutput(raw, fallbackRunAs: 'inline');
    if (data == null) {
      throw StateError('skill 创造结果格式不正确（缺 frontmatter 或正文），请重试');
    }

    final draftPath = p.join(_workspaceDir, 'draft_skill.md');
    File(draftPath).writeAsStringSync(_skillMarkdown(data));
    _workflow.draftSkillPath = draftPath;
    _workflow.exportPath = greenixSkillPluginPath(data.name);
    _appendEvent('info', 'skill 草稿完成：${data.name} → $draftPath');

    _workflow.phase = SkillCreatorPhase.finalizing;
  }

  /// ⑥ 终验：规划 agent 验收最终 skill，通过则导出。
  Future<void> _finalize() async {
    _workflow.phase = SkillCreatorPhase.finalizing;
    _appendEvent('info', '规划 agent 终验最终 skill...');

    final draft = _workflow.draftSkillPath != null &&
            File(_workflow.draftSkillPath!).existsSync()
        ? File(_workflow.draftSkillPath!).readAsStringSync()
        : '';
    if (draft.isEmpty) throw StateError('skill 草稿缺失，无法终验');

    final decision = await finalAccept(
      provider: _provider,
      requirement: _workflow.requirement,
      draftSkillMarkdown: draft,
    );
    final verdict = decision['verdict']?.toString() ?? 'pass';
    final feedback = decision['feedback']?.toString() ?? '';

    if (verdict == 'pass') {
      _appendEvent('info', '终验通过。$feedback');
      _workflow.phase = SkillCreatorPhase.exporting;
      return;
    }

    // 未通过：再创造一轮（上限保护）
    _workflow.round++;
    if (_workflow.round >= kMaxAttempts) {
      _appendEvent('warn', '终验未通过已达上限，按「将就」导出。原因：$feedback');
      _workflow.phase = SkillCreatorPhase.exporting;
      return;
    }
    _appendEvent('negotiation',
        '规划 agent → skill 创造 agent：${verdict == 'redo' ? '返工' : '修订'}（第 ${_workflow.round} 次）原因：$feedback');
    _workflow.phase = SkillCreatorPhase.creating;
  }

  /// ⑦ 导出：落盘 `plugins/<id>/skill/<id>.md`（Skill 即插件，统一路径）。
  Future<void> _export() async {
    _workflow.phase = SkillCreatorPhase.exporting;
    _appendEvent('info', '导出 skill 到 plugins/<id>/skill/ ...');

    final draft = _workflow.draftSkillPath != null &&
            File(_workflow.draftSkillPath!).existsSync()
        ? File(_workflow.draftSkillPath!).readAsStringSync()
        : '';
    if (draft.isEmpty) throw StateError('skill 草稿缺失，无法导出');

    final data = agent.SkillRewriter.parseOutput(draft, fallbackRunAs: 'inline');
    if (data == null) throw StateError('skill 草稿格式不正确，无法导出');

    final exportPath = greenixSkillPluginPath(data.name);
    final file = File(exportPath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    file.writeAsStringSync(_skillMarkdown(data));
    _workflow.exportPath = exportPath;
    _workflow.phase = SkillCreatorPhase.done;
    _appendEvent('info', '✅ 导出完成：$exportPath（可被 run_skill 热加载）');
  }

  // ═══════ 内部 ═══════

  /// 材料全文提取（PDF → 文本；扫描版降级 OCR）。
  Future<void> _processMaterial(MaterialItem m) async {
    // 重试前清除旧文本引用，避免失败后继续消费上一次的过期结果。
    if (m.textPath != null) {
      try { File(m.textPath!).deleteSync(); } catch (_) {}
      m.textPath = null;
    }
    m.processingError = null;
    final localPath = m.localPath;
    if (localPath == null || !File(localPath).existsSync()) {
      m.readability = 'skipped';
      m.processingError = '本地文件不存在';
      return;
    }
    if (p.extension(localPath).toLowerCase() != '.pdf') {
      m.readability = 'ok'; // 非 PDF（网页快照等）不提取全文
      return;
    }
    Directory(_materialsDir).createSync(recursive: true);
    final textPath = p.join(_materialsDir, '${m.id}.txt');
    try {
      final text =
          await PymupdfTool.extractText(localPath, pythonPath: pythonPath);
      if (text.trim().isEmpty) throw StateError('PDF 没有文本层');
      if (text.length > 20 * 1024 * 1024) {
        m.processingError = '提取文本超过 20MiB 上限';
        m.readability = 'unreadable';
        return;
      }
      File(textPath).writeAsStringSync(text);
      m.textPath = textPath;
      m.readability = 'ok';
    } catch (e) {
      // 扫描版 → OCR 降级
      try {
        m.ocrAttempts++;
        _appendEvent('info', '材料进入 OCR：${m.title}');
        final ocrText = await _ocr.recognizeFile(localPath);
        if (ocrText != null && ocrText.isNotEmpty) {
          if (ocrText.length > 20 * 1024 * 1024) {
            m.readability = 'unreadable';
            m.processingError = 'OCR 文本超过 20MiB 上限';
            return;
          }
          File(textPath).writeAsStringSync(ocrText);
          m.textPath = textPath;
          m.readability = 'ocr';
        } else {
          m.readability = 'unreadable';
          m.processingError = 'OCR 未识别到有效文本';
        }
      } catch (ocrError) {
        m.readability = 'unreadable';
        m.processingError = '文本提取失败：$e；OCR 失败：$ocrError';
      }
    }
  }

  /// 组装完整 skill Markdown（frontmatter + body，对齐落盘格式）。
  String _skillMarkdown(agent.SkillRewriteData data) {
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('name: ${data.name}')
      ..writeln('description: ${data.description}')
      ..writeln('run_as: ${data.runAs}')
      ..writeln('---')
      ..writeln()
      ..writeln(data.body.trim());
    return buf.toString();
  }

  void _appendEvent(String level, String message, {String? agentId}) {
    _workflow.log(level, message, agentId: agentId);
    _uiMessages.add({
      'role': level == 'error' ? 'error' : 'ai',
      'text': message,
      'agentId': agentId,
    });
    notifyListeners();
  }

  void _appendAgent(String role, String content) {
    _agentSession.add({'role': role, 'content': content});
  }

  void _saveSession() {
    panelManager.saveSession(
      panelId,
      instanceId,
      agentSession: _agentSession,
      uiMessages: _uiMessages,
      workflow: _workflow,
    );
  }

  /// skill 创造 agent 系统提示词。
  static const String _skillCreationSystemPrompt = '''
你是多 agent Skill 创作流水线中的「Skill 创造 Agent」。请把「整合报告」组织排布成一条**可直接落盘使用的 Skill**。

Skill 是带 YAML frontmatter 的 Markdown 文件，格式（字段必须完整）：
---
name: skill-name
description: 一行描述（显示在技能列表中）
run_as: inline
---
# 技能标题

## 适用场景
...

## 执行步骤
1. ...
2. ...

## 注意事项
...

## 示例
...

硬性要求：
1. name：从用户需求提炼语义，kebab-case（小写、连字符），不得与需求无关；
2. description：一行，概括技能用途；
3. run_as：一律 inline；
4. 正文：把报告中的经验/方法/要点转化为**可执行的技能指令**——适用场景、分步步骤、约束注意、示例；忠于报告内容，不得虚构报告之外的能力；
5. 只输出完整 Skill Markdown（frontmatter + 正文），不要解释、不要代码块包裹。
''';
}

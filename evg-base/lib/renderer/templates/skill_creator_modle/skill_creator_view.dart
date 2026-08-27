/// Skill 创作中心主视图——多 agent 流水线的用户界面。
///
/// 布局（宽屏三栏）：
/// - 左栏：面板列表（一面板一实例，新建/切换/删除）；
/// - 主区：需求输入 → 阶段指示 → 深寻任务卡片 → 材料清单 → 事件/交涉日志 → 导出；
/// - 右栏：显式 AI 面板 + 历史记录 + 子 agent 实时状态。
///
/// 断点续做：进入面板时若工作流处于未完成阶段，显示「续做」入口，
/// 从当前阶段继续（已完成任务跳过、材料复用）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/config/settings.dart' show getSetting, setSetting;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';

import 'models/skill_creator_models.dart';
import 'services/skill_creator_orchestrator.dart';
import 'services/skill_creator_panel_manager.dart';

/// Skill 创作中心。
class SkillCreatorView extends ConsumerStatefulWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;

  const SkillCreatorView({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  ConsumerState<SkillCreatorView> createState() => _SkillCreatorViewState();
}

class _SkillCreatorViewState extends ConsumerState<SkillCreatorView> {
  late SkillCreatorPanelManager _panelMgr;
  List<SkillCreatorPanelMeta> _panels = [];
  String? _currentPanelId;
  SkillCreatorOrchestrator? _orchestrator;

  String _apiKey = '';
  String _model = '';
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    _panelMgr = SkillCreatorPanelManager();
    _readSettings();
    _loadPanels();
  }

  @override
  void dispose() {
    _orchestrator?.removeListener(_onOrchestrator);
    super.dispose();
  }

  String _readSetting(String key) {
    try {
      return getSetting(ref.read(sharedPreferencesProvider), key);
    } catch (_) {
      return '';
    }
  }

  void _readSettings() {
    _apiKey = _readSetting('DEEPSEEK_API_KEY');
    _model = _readSetting('DEEPSEEK_MODEL').isNotEmpty
        ? _readSetting('DEEPSEEK_MODEL')
        : 'deepseek-v4-flash';
    _baseUrl = _readSetting('DEEPSEEK_BASE_URL').isNotEmpty
        ? _readSetting('DEEPSEEK_BASE_URL')
        : 'https://api.deepseek.com/v1';
  }

  void _loadPanels() {
    final panels = _panelMgr.listPanels();
    setState(() => _panels = panels);
    if (panels.isEmpty) {
      final data = _panelMgr.createPanel(name: '我的 Skill 创作');
      _loadPanel(data.meta.id);
    } else {
      _loadPanel(panels.first.id);
    }
  }

  void _newPanel() {
    final data = _panelMgr.createPanel(name: '未命名面板');
    _loadPanel(data.meta.id);
  }

  Future<void> _loadPanel(String panelId) async {
    _orchestrator?.removeListener(_onOrchestrator);

    final data = _panelMgr.loadPanel(panelId);
    final instance = _panelMgr.ensureInstance(panelId);
    final session =
        _panelMgr.restoreSession(panelId, instance.id);

    final orch = SkillCreatorOrchestrator(
      panelManager: _panelMgr,
      panelId: panelId,
      instanceId: instance.id,
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      model: _model,
      globalSkillIndex: ref.read(skillIndexProvider),
      globalMemoryStore: ref.read(memoryStoreProvider),
      pythonPath: null,
      initialWorkflow: session?.workflow ?? data?.workflow,
      initialSession: session?.agentSession,
      initialUi: session?.uiMessages,
    );
    orch.addListener(_onOrchestrator);

    setState(() {
      _currentPanelId = panelId;
      _orchestrator = orch;
      _panels = _panelMgr.listPanels();
    });
  }

  void _onOrchestrator() {
    if (mounted) setState(() {});
  }

  /// 未配置 API Key 时弹窗引导填写并保存（对齐主题创作 AI 引导）。
  Future<String?> _promptApiKey() async {
    final ctrl = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🤖 Skill 创作需要 API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('未配置 DEEPSEEK_API_KEY，可直接在此填写：',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'DEEPSEEK_API_KEY',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('保存并使用'),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty) return null;
    await setSetting(
        ref.read(sharedPreferencesProvider), 'DEEPSEEK_API_KEY', input);
    _readSettings();
    return input;
  }

  /// 开始流水线（无 Key 先引导填写）。
  Future<void> _startPipeline(String requirement) async {
    var key = _apiKey;
    if (key.isEmpty) {
      final prompted = await _promptApiKey();
      if (prompted == null || prompted.isEmpty) return;
      key = prompted;
      _apiKey = key;
    }
    _orchestrator?.start(requirement);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orch = _orchestrator;
    final wf = orch?.workflow;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧩 Skill 创作（多 Agent）'),
        actions: [
          if (wf != null && wf.phase != SkillCreatorPhase.idle)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '续做',
              onPressed: orch!.busy ? null : () => orch!.resume(),
            ),
          if (orch?.busy == true)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止流水线',
              onPressed: () => orch!.cancelPipeline(),
            ),
          if (orch != null && orch.workflow.tasks.any((t) => t.status == TaskStatus.failed))
            IconButton(
              icon: const Icon(Icons.replay_circle_filled_outlined),
              tooltip: '重试全部失败任务',
              onPressed: orch.busy ? null : () => orch.retryFailedTasks(),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建面板',
            onPressed: _newPanel,
          ),
        ],
      ),
      body: orch == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // 窄屏（< 920）固定三栏总宽会超出可用空间 → 改为整体横向滚动，
                // 避免右侧 AI 面板被推出屏幕造成 RenderFlex 横向溢出。
                const kMinTotal = 200 + 400 + 320; // 左栏 + 中间最小宽 + 右栏
                final main = _WorkflowPanel(
                    orchestrator: orch, onStart: _startPipeline);
                final panelList = _PanelList(
                  panels: _panels,
                  currentId: _currentPanelId,
                  onSelect: _loadPanel,
                  onNew: _newPanel,
                );
                final aiPanel = _AiPanel(orchestrator: orch);

                if (constraints.maxWidth >= kMinTotal) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 200, child: panelList),
                      Expanded(child: main),
                      SizedBox(width: 320, child: aiPanel),
                    ],
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: kMinTotal.toDouble(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 200, child: panelList),
                        SizedBox(width: 400, child: main),
                        SizedBox(width: 320, child: aiPanel),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════ 左栏：面板列表 ═══════

class _PanelList extends StatelessWidget {
  final List<SkillCreatorPanelMeta> panels;
  final String? currentId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  const _PanelList({
    required this.panels,
    required this.currentId,
    required this.onSelect,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text('面板',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: '新建面板',
                  onPressed: onNew,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final panel in panels)
                  ListTile(
                    dense: true,
                    selected: panel.id == currentId,
                    title: Text(panel.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      panel.id == currentId ? '当前' : '',
                      style: theme.textTheme.labelSmall,
                    ),
                    onTap: () => onSelect(panel.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════ 主区：工作流面板 ═══════

class _WorkflowPanel extends StatelessWidget {
  final SkillCreatorOrchestrator orchestrator;
  final ValueChanged<String> onStart;

  const _WorkflowPanel({required this.orchestrator, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final wf = orchestrator.workflow;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhaseHeader(phase: wf.phase, busy: orchestrator.busy),
        const SizedBox(height: 12),
        _WorkflowTree(workflow: wf, agentStatus: orchestrator.agentStatus),
        const SizedBox(height: 12),
        _RequirementCard(
          orchestrator: orchestrator,
          onStart: onStart,
        ),
        if (wf.tasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TasksSection(orchestrator: orchestrator),
        ],
        if (wf.materials.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MaterialsSection(materials: wf.materials, orchestrator: orchestrator),
        ],
        const SizedBox(height: 12),
        _EventsSection(events: wf.events),
        if (wf.phase == SkillCreatorPhase.done && wf.exportPath != null) ...[
          const SizedBox(height: 12),
          _ExportCard(path: wf.exportPath!),
        ],
      ],
    );
  }
}

/// 动态工作流树：把阶段、深寻任务和最近事件放在同一条可读路径上。
class _WorkflowTree extends StatelessWidget {
  final SkillCreatorWorkflow workflow;
  final Map<String, String> agentStatus;
  const _WorkflowTree({required this.workflow, required this.agentStatus});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failedCount = workflow.tasks.where((t) => t.status == TaskStatus.failed).length;
    final runningCount = workflow.tasks.where((t) => t.status == TaskStatus.running).length;
    final doneCount = workflow.tasks.where((t) => t.status == TaskStatus.done).length;
    final progress = workflow.tasks.isEmpty ? 0.0 : doneCount / workflow.tasks.length;
    final nodes = <Widget>[
      _treeNode(scheme, Icons.account_tree, 'Skill 创作流水线', '${workflow.phase.name} · 完成 $doneCount/${workflow.tasks.length} · 运行 $runningCount${failedCount > 0 ? ' · 失败 $failedCount' : ''}', false),
      _treeNode(scheme, Icons.route, '规划', workflow.tasks.isEmpty ? '等待任务' : '${workflow.tasks.length} 个任务', workflow.phase.index > SkillCreatorPhase.planning.index),
      for (final task in workflow.tasks)
        _treeNode(
          scheme,
          Icons.search,
          task.query,
          _taskStatus(task.id, task),
          task.status == TaskStatus.done,
        ),
      for (final agentId in _agentIds())
        _treeNode(scheme, Icons.smart_toy, 'Agent ${agentId.length > 16 ? agentId.substring(0, 16) : agentId}', _latestAgentEvent(agentId) ?? '已记录', false),
      _treeNode(scheme, Icons.fact_check, '证据整合', '${workflow.materials.length} 份材料', workflow.phase.index > SkillCreatorPhase.integrating.index),
      _treeNode(scheme, Icons.auto_awesome, 'Skill 导出', workflow.exportPath == null ? '等待' : '已完成', workflow.exportPath != null),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('动态工作流', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 6),
          ...nodes,
        ]),
      ),
    );
  }

  String? _latestAgentEvent(String agentId) {
    for (final event in workflow.events.reversed) {
      if (event.agentId == agentId) return event.message;
    }
    return null;
  }

  String _taskStatus(String taskId, SearchTask task) {
    final live = agentStatus[taskId];
    if (live != null && live.isNotEmpty) return live;
    final event = workflow.events.reversed.firstWhere(
      (e) => e.agentId == taskId,
      orElse: () => WorkflowEvent(at: DateTime.fromMillisecondsSinceEpoch(0), level: '', phase: '', message: ''),
    );
    if (event.message.isNotEmpty) return '${event.message} · ${task.materialIds.length} 份材料';
    return '${task.status.name} · ${task.materialIds.length} 份材料';
  }

  List<String> _agentIds() {
    final ids = <String>{};
    for (final event in workflow.events) {
      if (event.agentId != null && event.agentId!.isNotEmpty) ids.add(event.agentId!);
    }
    return ids.toList();
  }

  Widget _treeNode(ColorScheme scheme, IconData icon, String title, String status, bool done) {
    final failed = status == 'failed' || status.contains('失败');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(done ? Icons.check_circle : failed ? Icons.error : icon, size: 16, color: done ? scheme.primary : failed ? scheme.error : scheme.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: failed ? scheme.error : scheme.outline),
          ),
        ),
      ]),
    );
  }
}

// ═══════ 阶段指示 ═══════

class _PhaseHeader extends StatelessWidget {
  final SkillCreatorPhase phase;
  final bool busy;

  const _PhaseHeader({required this.phase, required this.busy});

  static const _phases = [
    (SkillCreatorPhase.planning, '规划'),
    (SkillCreatorPhase.collecting, '深寻'),
    (SkillCreatorPhase.accepting, '验收'),
    (SkillCreatorPhase.integrating, '整合'),
    (SkillCreatorPhase.creating, '创造'),
    (SkillCreatorPhase.finalizing, '终验'),
    (SkillCreatorPhase.exporting, '导出'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = phase;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _phases.length; i++)
                    _PhaseChip(
                      label: '${i + 1}.${_phases[i].$2}',
                      active: current == _phases[i].$1,
                      done: _phaseIndex(current) > i,
                      error: current == SkillCreatorPhase.error,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _phaseIndex(SkillCreatorPhase phase) {
    for (var i = 0; i < _phases.length; i++) {
      if (phase == _phases[i].$1) return i;
    }
    return -1;
  }
}

class _PhaseChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  final bool error;

  const _PhaseChip({
    required this.label,
    required this.active,
    required this.done,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error
        ? scheme.error
        : active
            ? scheme.primary
            : done
                ? scheme.tertiary
                : scheme.outlineVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active || error ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═══════ 需求卡片 ═══════

class _RequirementCard extends StatefulWidget {
  final SkillCreatorOrchestrator orchestrator;
  final ValueChanged<String> onStart;

  const _RequirementCard({
    required this.orchestrator,
    required this.onStart,
  });

  @override
  State<_RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends State<_RequirementCard> {
  final _reqCtrl = TextEditingController();

  @override
  void dispose() {
    _reqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wf = widget.orchestrator.workflow;
    final idle = wf.phase == SkillCreatorPhase.idle;
    final busy = widget.orchestrator.busy;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🎯 需求',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (idle) ...[
              TextField(
                controller: _reqCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '你想创作一个什么 Skill？',
                  hintText: '例如：帮我创建一个「学术论文速读」Skill，能搜索并下载相关论文、提取要点、总结方法论…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          final req = _reqCtrl.text.trim();
                          if (req.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入需求描述')),
                            );
                            return;
                          }
                          widget.onStart(req);
                        },
                  icon: const Icon(Icons.rocket_launch, size: 18),
                  label: const Text('开始多 Agent 流水线'),
                ),
              ),
            ] else ...[
              Text(wf.requirement,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (wf.phase == SkillCreatorPhase.error)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => widget.orchestrator.resume(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                  if (wf.phase == SkillCreatorPhase.done)
                    Text('✅ 已完成：${wf.exportPath ?? ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.tertiary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════ 深寻任务卡片 ═══════

class _TasksSection extends StatelessWidget {
  final SkillCreatorOrchestrator orchestrator;

  const _TasksSection({required this.orchestrator});

  @override
  Widget build(BuildContext context) {
    final wf = orchestrator.workflow;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🧭 深寻任务（${wf.tasks.length}）',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final task in wf.tasks) _TaskCard(task: task, orch: orchestrator),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final SearchTask task;
  final SkillCreatorOrchestrator orch;

  const _TaskCard({required this.task, required this.orch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = switch (task.status) {
      TaskStatus.pending => '待执行',
      TaskStatus.running => '采集中...',
      TaskStatus.done => '完成',
      TaskStatus.failed => '失败',
    };
    final verdictText = switch (task.verdict) {
      TaskVerdict.none => '',
      TaskVerdict.pass => '✅ 通过',
      TaskVerdict.revise => '✏️ 修订',
      TaskVerdict.redo => '🔁 返工',
    };
    final agentLive = orch.agentStatus[task.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (task.source) {
                  SearchSource.arxiv => Icons.science,
                  SearchSource.web => Icons.public,
                  SearchSource.books => Icons.menu_book,
                },
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${searchSourceLabel(task.source)} · ${task.query}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(
                '$statusText $verdictText',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: task.status == TaskStatus.running
                      ? theme.colorScheme.primary
                      : task.status == TaskStatus.failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (agentLive != null && agentLive.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(agentLive,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
          if (task.attempts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('执行次数：${task.attempts}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (task.feedback.isNotEmpty && task.verdict == TaskVerdict.pass)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('评语：${task.feedback}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.tertiary)),
            ),
          if (task.status == TaskStatus.failed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: orch.busy ? null : () => orch.retryTask(task.id),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('重试此任务'),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════ 材料清单 ═══════

class _MaterialsSection extends StatelessWidget {
  final List<MaterialItem> materials;
  final SkillCreatorOrchestrator orchestrator;

  const _MaterialsSection({required this.materials, required this.orchestrator});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📚 采集材料（${materials.length}）',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final m in materials)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m.readability == 'unreadable'
                          ? Icons.warning_amber
                          : Icons.description,
                      size: 14,
                      color: m.readability == 'unreadable'
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m.title}（${searchSourceLabel(m.source)}）',
                              style: theme.textTheme.bodySmall),
                          Text(
                            '${m.url}${m.readability == 'unreadable' ? ' · ⚠ 不可读' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (m.processingError != null)
                            Text(m.processingError!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
                          if (m.readability == 'unreadable')
                            TextButton(onPressed: orchestrator.busy ? null : () => orchestrator.retryMaterialOcr(m.id), child: const Text('重试 OCR')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════ 事件/交涉日志 ═══════

class _EventsSection extends StatefulWidget {
  final List<WorkflowEvent> events;

  const _EventsSection({required this.events});

  @override
  State<_EventsSection> createState() => _EventsSectionState();
}

class _EventsSectionState extends State<_EventsSection> {
  String _filter = 'all';
  String _agentFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.events.where((e) => (_filter == 'all' || e.level == _filter) && (_agentFilter == 'all' || e.agentId == _agentFilter)).toList();
    final agents = widget.events.map((e) => e.agentId).whereType<String>().where((e) => e.isNotEmpty).toSet().toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📋 流水线日志（${widget.events.length}）',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 4, children: [
              for (final f in const [('all', '全部'), ('info', '信息'), ('warn', '警告'), ('error', '错误'), ('negotiation', '协商')])
                ChoiceChip(label: Text(f.$2, style: const TextStyle(fontSize: 10)), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
            ]),
            if (agents.isNotEmpty) ...[
              const SizedBox(height: 4),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                ChoiceChip(label: const Text('全部 Agent', style: TextStyle(fontSize: 10)), selected: _agentFilter == 'all', onSelected: (_) => setState(() => _agentFilter = 'all')),
                for (final id in agents) Padding(padding: const EdgeInsets.only(left: 4), child: ChoiceChip(label: Text(id.length > 12 ? id.substring(0, 12) : id, style: const TextStyle(fontSize: 10)), selected: _agentFilter == id, onSelected: (_) => setState(() => _agentFilter = id))),
              ])),
            ],
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Text('暂无事件',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            for (final e in visible.reversed.take(30))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (e.level) {
                        'error' => Icons.error_outline,
                        'warn' => Icons.warning_amber,
                        'negotiation' => Icons.swap_horiz,
                        _ => Icons.info_outline,
                      },
                      size: 13,
                      color: e.level == 'error'
                          ? theme.colorScheme.error
                          : e.level == 'warn'
                              ? Colors.orange
                              : e.level == 'negotiation'
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Row(children: [
                        if (e.agentId != null) ...[
                          Chip(label: Text(e.agentId!.length > 10 ? e.agentId!.substring(0, 10) : e.agentId!, style: const TextStyle(fontSize: 9)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                          const SizedBox(width: 4),
                        ],
                        Expanded(child: Text(e.message, style: theme.textTheme.labelSmall)),
                        Text('${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                      ]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════ 导出卡片 ═══════

class _ExportCard extends StatelessWidget {
  final String path;

  const _ExportCard({required this.path});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.tertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('已导出：$path\n可在技能管理页查看，可被 run_skill 热加载',
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════ 右栏：AI 面板 + 历史 ═══════

class _AiPanel extends StatelessWidget {
  final SkillCreatorOrchestrator orchestrator;

  const _AiPanel({required this.orchestrator});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msgs = orchestrator.uiMessages;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('🤖 AI 面板 · 历史记录',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (context, i) {
                final m = msgs[i];
                final role = m['role']?.toString() ?? 'ai';
                final text = m['text']?.toString() ?? '';
                final isUser = role == 'user';
                final isError = role == 'error';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isError
                          ? theme.colorScheme.errorContainer
                          : isUser
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      text,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isError
                            ? theme.colorScheme.onErrorContainer
                            : null,
                      ),
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 30,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

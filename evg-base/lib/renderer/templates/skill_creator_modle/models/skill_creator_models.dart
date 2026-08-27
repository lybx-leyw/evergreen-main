/// Skill 创作面板数据模型——多 agent 流水线的共享状态载体。
///
/// 覆盖：面板/实例元数据、流程阶段、按来源拆分任务、采集材料、
/// 验收交涉记录、最终 skill 导出。全部可 JSON 序列化，
/// 支撑「一会话一固定历史 + 断点续做」持久化。
library;

import 'dart:convert';

// ═══════ 枚举 ═══════

/// 流水线阶段（UI 流程可视化 + 断点续做恢复用）。
enum SkillCreatorPhase {
  idle, // 空面板/待开始
  asking, // 规划 agent 询问用户需求
  planning, // 规划任务清单（按来源拆分）
  collecting, // 深寻 agents 并行采集
  accepting, // 采集结果验收/交涉
  integrating, // 整合 agent 撰写报告
  creating, // skill 创造 agent 组织排布
  finalizing, // 规划 agent 终验
  exporting, // 导出落盘
  done, // 完成
  error, // 错误（可重试）
}

/// 深寻采集来源（按来源拆分 → 多平台权威信息；来源重复 = 最值得参考）。
enum SearchSource {
  arxiv, // arXiv 论文
  web, // 通用网络/学术搜索
  books, // 书籍/长文（如 O'Reilly、GitBook 等）
}

/// 采集来源标签。
String searchSourceLabel(SearchSource s) => switch (s) {
      SearchSource.arxiv => 'arXiv 论文',
      SearchSource.web => '通用网络',
      SearchSource.books => '书籍/长文',
    };

/// 任务执行状态。
enum TaskStatus { pending, running, done, failed }

/// 验收交涉结论（规划 agent 对子 agent 产出的裁决）。
enum TaskVerdict {
  none, // 未验收
  pass, // 通过
  revise, // 修订（子 agent 按反馈微调）
  redo, // 返工（子 agent 重跑）
}

/// 材料类型。
enum MaterialType { paper, book, article, other }

// ═══════ 模型 ═══════

/// 采集任务（按来源拆分；一个深寻 agent 负责一个任务）。
class SearchTask {
  final String id;

  /// 采集来源（决定深寻 agent 的工具装配与检索策略）。
  final SearchSource source;

  /// 检索主题/查询串（规划 agent 生成）。
  final String query;

  TaskStatus status;
  TaskVerdict verdict;

  /// 规划 agent 的交涉意见（revise/redo 时携带原因与指令）。
  String feedback;

  /// 子 agent 返回的结果摘要（markdown）。
  String resultSummary;

  /// 命中的材料 id（指向工作流 materials 列表）。
  List<String> materialIds;

  /// 已执行的尝试次数（redo 累加；用于防死循环与展示）。
  int attempts;

  SearchTask({
    required this.id,
    required this.source,
    required this.query,
    this.status = TaskStatus.pending,
    this.verdict = TaskVerdict.none,
    this.feedback = '',
    this.resultSummary = '',
    List<String>? materialIds,
    this.attempts = 0,
  }) : materialIds = materialIds ?? [];

  factory SearchTask.fromJson(Map<String, dynamic> json) => SearchTask(
        id: json['id']?.toString() ?? '',
        source: SearchSource.values.firstWhere(
            (s) => s.name == json['source'],
            orElse: () => SearchSource.web),
        query: json['query']?.toString() ?? '',
        status: TaskStatus.values.firstWhere(
            (s) => s.name == json['status'],
            orElse: () => TaskStatus.pending),
        verdict: TaskVerdict.values.firstWhere(
            (v) => v.name == json['verdict'],
            orElse: () => TaskVerdict.none),
        feedback: json['feedback']?.toString() ?? '',
        resultSummary: json['resultSummary']?.toString() ?? '',
        materialIds: (json['materialIds'] as List?)?.whereType<String>().toList() ?? [],
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'query': query,
        'status': status.name,
        'verdict': verdict.name,
        'feedback': feedback,
        'resultSummary': resultSummary,
        'materialIds': materialIds,
        'attempts': attempts,
      };
}

/// 采集到的材料（论文/书籍/文章）。
class MaterialItem {
  final String id;

  /// 来源标签（与任务一致）。
  final SearchSource source;

  final String title;
  final String url;

  /// paper / book / article。
  final String type;

  /// 下载的本地文件路径（PDF 等），null = 未下载。
  String? localPath;

  /// 提取文本的落盘路径（`materials/<id>.txt`），避免会话文件过大。
  String? textPath;

  /// 元数据。
  String? authors;
  String? year;

  /// 采集摘要（深寻 agent 生成）。
  String summary;

  /// 可读性状态：ok（文本可用）/ unreadable（扫描版且 OCR 失败）/ skipped。
  String readability;
  String? processingError;

  MaterialItem({
    required this.id,
    required this.source,
    required this.title,
    required this.url,
    required this.type,
    this.localPath,
    this.textPath,
    this.authors,
    this.year,
    this.summary = '',
    this.readability = 'ok',
    this.processingError,
  });

  factory MaterialItem.fromJson(Map<String, dynamic> json) => MaterialItem(
        id: json['id'] as String? ?? '',
        source: SearchSource.values.firstWhere(
            (s) => s.name == json['source'],
            orElse: () => SearchSource.web),
        title: json['title']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        type: json['type']?.toString() ?? 'article',
        localPath: json['localPath']?.toString(),
        textPath: json['textPath']?.toString(),
        authors: json['authors']?.toString(),
        year: json['year']?.toString(),
        summary: json['summary']?.toString() ?? '',
        readability: json['readability']?.toString() ?? 'ok',
        processingError: json['processingError']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'title': title,
        'url': url,
        'type': type,
        if (localPath != null) 'localPath': localPath,
        if (textPath != null) 'textPath': textPath,
        if (authors != null) 'authors': authors,
        if (year != null) 'year': year,
        'summary': summary,
        'readability': readability,
        if (processingError != null) 'processingError': processingError,
      };
}

/// 流水线事件（流程日志 + 交涉记录；UI 历史 + 断点续做展示）。
class WorkflowEvent {
  final DateTime at;

  /// info / warn / error / negotiation。
  final String level;
  final String phase;

  /// 事件消息。
  final String message;

  /// 相关子 agent（规划 agent 自身为 null）。
  final String? agentId;

  WorkflowEvent({
    required this.at,
    required this.level,
    required this.phase,
    required this.message,
    this.agentId,
  });

  factory WorkflowEvent.fromJson(Map<String, dynamic> json) => WorkflowEvent(
        at: json['at'] != null
            ? (DateTime.tryParse(json['at'] as String) ?? DateTime.now())
            : DateTime.now(),
        level: json['level']?.toString() ?? 'info',
        phase: json['phase']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        agentId: json['agentId']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'level': level,
        'phase': phase,
        'message': message,
        if (agentId != null) 'agentId': agentId,
      };
}

/// 多 agent 流水线工作流状态（整体可序列化，随会话持久化）。
class SkillCreatorWorkflow {
  /// 当前阶段。
  SkillCreatorPhase phase;

  /// 断点续做阶段：流水线异常中断前「下一个待执行」的阶段。
  /// 失败时 [phase] 会被置为 [SkillCreatorPhase.error]，但此字段保留
  /// 真实的续做起点，供 [resume] 从 error 恢复（可序列化，跨会话续做）。
  SkillCreatorPhase? resumePhase;

  /// 用户需求（规划 agent ask 澄清后的定稿）。
  String requirement;

  /// 编排轮次（断点续做：重启后从当前阶段继续）。
  int round;

  /// 按来源拆分的采集任务。
  List<SearchTask> tasks;

  /// 全部采集材料（任务间共享）。
  List<MaterialItem> materials;

  /// 整合报告落盘路径（整合 agent 产出）。
  String? reportPath;

  /// 最终 skill 草稿落盘路径（skill 创造 agent 产出）。
  String? draftSkillPath;

  /// 导出路径（`plugins/<id>/skill/<id>.md`，Skill 即插件统一路径）。
  String? exportPath;

  /// 流程事件（日志 + 交涉记录）。
  List<WorkflowEvent> events;

  SkillCreatorWorkflow({
    this.phase = SkillCreatorPhase.idle,
    this.resumePhase,
    this.requirement = '',
    this.round = 0,
    List<SearchTask>? tasks,
    List<MaterialItem>? materials,
    this.reportPath,
    this.draftSkillPath,
    this.exportPath,
    List<WorkflowEvent>? events,
  })  : tasks = tasks ?? [],
        materials = materials ?? [],
        events = events ?? [];

  factory SkillCreatorWorkflow.fromJson(Map<String, dynamic> json) =>
      SkillCreatorWorkflow(
        phase: SkillCreatorPhase.values.firstWhere(
            (p) => p.name == json['phase'],
            orElse: () => SkillCreatorPhase.idle),
        resumePhase: json['resumePhase'] != null
            ? SkillCreatorPhase.values.firstWhere(
                (p) => p.name == json['resumePhase'],
                orElse: () => SkillCreatorPhase.idle)
            : null,
        requirement: json['requirement'] as String? ?? '',
        round: (json['round'] as num?)?.toInt() ?? 0,
        tasks: (json['tasks'] as List? ?? const [])
            .whereType<Map>()
            .map((t) => SearchTask.fromJson(Map<String, dynamic>.from(t)))
            .take(10).toList(),
        materials: (json['materials'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => MaterialItem.fromJson(Map<String, dynamic>.from(m)))
            .take(1000).toList(),
        reportPath: json['reportPath'] as String?,
        draftSkillPath: json['draftSkillPath'] as String?,
        exportPath: json['exportPath'] as String?,
        events: (json['events'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => WorkflowEvent.fromJson(Map<String, dynamic>.from(e)))
            .take(1000).toList(),
      );

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        if (resumePhase != null) 'resumePhase': resumePhase!.name,
        'requirement': requirement,
        'round': round,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'materials': materials.map((m) => m.toJson()).toList(),
        if (reportPath != null) 'reportPath': reportPath,
        if (draftSkillPath != null) 'draftSkillPath': draftSkillPath,
        if (exportPath != null) 'exportPath': exportPath,
        'events': events.map((e) => e.toJson()).toList(),
      };

  /// 追加事件（返回自身便于链式）。
  SkillCreatorWorkflow log(
    String level,
    String message, {
    String? agentId,
  }) {
    events.add(WorkflowEvent(
      at: DateTime.now(),
      level: level,
      phase: phase.name,
      message: message,
      agentId: agentId,
    ));
    if (events.length > 1000) {
      events.removeRange(0, events.length - 1000);
    }
    return this;
  }

  /// 查找任务。
  SearchTask? task(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 查找材料。
  MaterialItem? material(String id) {
    for (final m in materials) {
      if (m.id == id) return m;
    }
    return null;
  }
}

// ═══════ 面板 / 实例 ═══════

/// 面板元数据（固定 ID 不可变；实例 1:1 绑定）。
class SkillCreatorPanelMeta {
  /// 面板唯一 ID（`skill_panel_xxx`，固定不可变）。
  final String id;
  String name;

  /// 绑定的实例 ID（面板 ↔ 实例 1:1；null = 尚未分配，首次加载自动创建）。
  String? instanceId;

  final DateTime createdAt;
  DateTime updatedAt;

  SkillCreatorPanelMeta({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.instanceId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory SkillCreatorPanelMeta.fromJson(Map<String, dynamic> json) =>
      SkillCreatorPanelMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名面板',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        instanceId: json['instanceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (instanceId != null) 'instanceId': instanceId,
      };
}

/// 实例元数据（固定 ID == 面板 ID 派生，重命名不改 id）。
class SkillCreatorInstanceMeta {
  /// 实例 ID（固定不可变；== 面板 ID，杜绝分叉）。
  final String id;
  String name;
  final String panelId;
  final DateTime createdAt;
  DateTime updatedAt;

  SkillCreatorInstanceMeta({
    required this.id,
    required this.name,
    required this.panelId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory SkillCreatorInstanceMeta.fromJson(Map<String, dynamic> json) =>
      SkillCreatorInstanceMeta(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名实例',
        panelId: json['panelId'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'panelId': panelId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// 面板完整数据（meta + 工作流状态）。
class SkillCreatorPanelData {
  final SkillCreatorPanelMeta meta;
  final SkillCreatorWorkflow workflow;

  const SkillCreatorPanelData({required this.meta, required this.workflow});
}

/// 会话文件内容（一会话一固定历史：规划 agent 消息 + UI 消息 + 工作流快照）。
class SkillCreatorSession {
  /// 规划 agent 会话历史（system/user/assistant 消息）。
  List<Map<String, dynamic>> agentSession;

  /// UI 消息列表（AI 面板展示）。
  List<Map<String, dynamic>> uiMessages;

  /// 工作流快照（断点续做恢复）。
  SkillCreatorWorkflow workflow;

  SkillCreatorSession({
    List<Map<String, dynamic>>? agentSession,
    List<Map<String, dynamic>>? uiMessages,
    required this.workflow,
  })  : agentSession = agentSession ?? [],
        uiMessages = uiMessages ?? [];

  factory SkillCreatorSession.fromJson(Map<String, dynamic> json) =>
      SkillCreatorSession(
        agentSession: (json['agentSession'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        uiMessages: (json['uiMessages'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        workflow: SkillCreatorWorkflow.fromJson(
            (json['workflow'] as Map?)?.cast<String, dynamic>() ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'agentSession': agentSession,
        'uiMessages': uiMessages,
        'workflow': workflow.toJson(),
      };
}

// ═══════ 工具 ═══════

/// 生成唯一面板 ID。
String newSkillPanelId() =>
    'skill_panel_${DateTime.now().millisecondsSinceEpoch}_${_random4()}';

String _random4() => (DateTime.now().microsecondsSinceEpoch % 10000)
    .toString()
    .padLeft(4, '0');

/// 从 JSON 安全解码（会话文件容错）。
Map<String, dynamic> decodeJsonMap(String raw) {
  try {
    final v = jsonDecode(raw);
    if (v is Map<String, dynamic>) return v;
    return <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

/// Skill 创作多 agent 装配——深寻 agents + 规划/整合/验收单轮 LLM 助手。
///
/// - [DeepSearchRunner]：按来源（arXiv/通用/书籍）为每个采集任务创建一个
///   隔离 AgentAssembly（独立工具白名单 + 独立会话/工作区），驱动其
///   工具循环（web_search / web_fetch / download_file / pdf_extract_text /
///   ocr_file），回收结构化结果；
/// - 规划/验收/整合等单轮 LLM 调用：直连 DeepSeek（与主题创作 AI 同款），
///   无会话、无断点，失败可重试。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/tools/file_info.dart';
import 'package:evergreen_base/core/agent/tools/head_tail.dart';
import 'package:evergreen_base/core/agent/tools/python_runner_tool.dart';
import 'package:evergreen_base/core/agent/tools/read_file.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';
import 'package:evergreen_base/core/agent/tools/research_search.dart';
import 'package:evergreen_base/core/agent/tools/write_file.dart';
import 'package:evergreen_base/core/services/ocr_pipeline.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import '../models/skill_creator_models.dart';
import 'skill_creator_tools.dart';

// ═══════ LLM 配置 ═══════

/// 直连 DeepSeek 的 Provider 工厂（与主题创作 AI 同款）。
agent.DeepSeekProvider buildDeepSeekProvider({
  required String apiKey,
  String baseUrl = 'https://api.deepseek.com/v1',
  String model = 'deepseek-v4-flash',
}) {
  return agent.DeepSeekProvider(
    dio: Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    )),
    apiKey: apiKey,
    model: model,
  );
}

/// 单轮 LLM 调用（无会话），返回完整文本；失败抛异常（调用方可重试）。
Future<String> singleRound({
  required agent.Provider provider,
  required String systemPrompt,
  required String userPrompt,
  Duration timeout = const Duration(minutes: 10),
}) async {
  final buf = StringBuffer();
  final stream = provider.chat(messages: [
    agent.Message.system(systemPrompt),
    agent.Message.user(userPrompt),
  ]);
  await for (final event in stream) {
    if (event.kind == agent.ProviderEventKind.content && event.text != null) {
      buf.write(event.text!);
    } else if (event.kind == agent.ProviderEventKind.error) {
      throw StateError('LLM 调用失败: ${event.error ?? "未知错误"}');
    }
  }
  final text = buf.toString().trim();
  if (text.isEmpty) throw StateError('LLM 未返回内容，请重试');
  return text;
}

/// 从回复中提取 JSON（去代码块包裹），失败返回 null。
Map<String, dynamic>? extractJsonObject(String text) {
  var t = text.trim();
  final m = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final v = jsonDecode(t.substring(start, end + 1));
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  return null;
}

// ═══════ 深寻 agent 结果 ═══════

/// 深寻 agent 单次执行结果。
class DeepSearchResult {
  final String summary;
  final List<Map<String, dynamic>> materials;

  /// 原始 assistant 文本（调试/展示）。
  final String rawText;

  final String? error;

  const DeepSearchResult({
    this.summary = '',
    this.materials = const [],
    this.rawText = '',
    this.error,
  });

  bool get isSuccess => error == null;
}

// ═══════ DeepSearchRunner ═══════

/// 深寻 agent 运行器——每个采集任务一个隔离 Agent。
class DeepSearchRunner {
  final String apiKey;
  final String baseUrl;
  final String model;
  final SkillIndex globalSkillIndex;
  final FileMemoryStore globalMemoryStore;
  final String workspaceRoot;
  final String? pythonPath;
  final String? ocrApiKey;

  DeepSearchRunner({
    required this.apiKey,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.model = 'deepseek-v4-flash',
    required this.globalSkillIndex,
    required this.globalMemoryStore,
    required this.workspaceRoot,
    this.pythonPath,
    this.ocrApiKey,
  });

  /// 运行一个深寻任务。
  ///
  /// [task] 任务定义；[feedback] 交涉反馈（首次为空，revise/redo 时携带）；
  /// [onEvent] 事件回调（UI 展示子 agent 进度，可选）。
  Future<DeepSearchResult> run({
    required SearchTask task,
    String feedback = '',
    void Function(agent.AgentEvent event)? onEvent,
    Duration timeout = const Duration(minutes: 20),
  }) async {
    final taskId = task.id;
    final agentWs = p.join(workspaceRoot, 'agents', taskId);
    Directory(agentWs).createSync(recursive: true);

    // ── 自定义种子工具（工作区绑定到本任务目录） ──
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ));
    final ocrPipeline = OcrPipeline(dio, null, ocrApiKey);
    final seedTools = <agent.Tool>[
      WebSearchTool(dio),
      WebFetchTool(dio),
      ArxivSearchTool(dio),
      GithubSearchTool(dio),
      CrossrefSearchTool(dio),
      ReadFileTool(workspaceDir: agentWs),
      WriteFileTool(workspaceDir: agentWs),
      FileInfoTool(workspaceDir: agentWs),
      ReadHeadTool(workspaceDir: agentWs),
      ReadTailTool(workspaceDir: agentWs),
      DownloadFileTool(dio, workspaceDir: agentWs),
      PdfExtractTool(pythonPath: pythonPath),
      OcrFileTool(ocrPipeline),
      CheckOcrReadyTool(ocrPipeline),
    ];

    // 注册嵌入式 Python runner（若存在），供 agent 执行辅助脚本
    final bundledPython = Platform.isWindows
        ? p.join(greenixPythonDir, 'python.exe')
        : p.join(greenixPythonDir, 'bin', 'python3');
    if (File(bundledPython).existsSync()) {
      seedTools.add(PythonRunnerTool(
        pythonExePath: bundledPython,
        pythonWorkDir: greenixPythonDir,
        workspaceDir: agentWs,
      ));
    }

    final provider = buildDeepSeekProvider(
        apiKey: apiKey, baseUrl: baseUrl, model: model);

    final assembly = AgentAssembly.fromConfig(
      moduleId: 'skill_creator_agent_$taskId',
      config: {
        'preset': 'research-full',
        'system_prompt': _systemPrompt(task.source),
        'tools': {
          'mode': 'specific',
          'allowed': seedTools.map((t) => t.name).toList(),
        },
      },
      sharedProvider: provider,
      globalSkillIndex: globalSkillIndex,
      globalMemoryStore: globalMemoryStore,
      seedTools: seedTools,
    );

    final controller = assembly.controller;
    final sink = assembly.eventSink;

    final done = Completer<String?>();
    late StreamSubscription<agent.AgentEvent> sub;
    sub = sink.stream.listen((e) {
      onEvent?.call(e);
      if (e.kind == agent.EventKind.turnDone) {
        String? last;
        for (final m in assembly.session.messages.reversed) {
          if (m.role == agent.Role.assistant && m.content.isNotEmpty) {
            last = m.content;
            break;
          }
        }
        if (!done.isCompleted) done.complete(last);
        sub.cancel();
      }
    });

    final userPrompt = _userPrompt(task, feedback);
    controller.send(userPrompt);

    String? raw;
    try {
      raw = await done.future.timeout(timeout);
    } catch (e) {
      controller.cancel();
      sub.cancel();
      return DeepSearchResult(
        error: '深寻超时（${timeout.inMinutes}min）或中断: $e',
        rawText: raw ?? '',
      );
    } finally {
      controller.dispose();
      sub.cancel();
    }

    if (raw == null || raw.trim().isEmpty) {
      return const DeepSearchResult(error: '深寻 agent 未返回任何内容，请重试');
    }

    return _parseResult(raw, agentWs: agentWs);
  }

  /// 解析深寻 agent 结果（最后一段 JSON）。
  DeepSearchResult _parseResult(String raw, {required String agentWs}) {
    if (raw.length > 2 * 1024 * 1024) {
      return const DeepSearchResult(error: '深寻结果超过 2MiB 上限');
    }
    final json = extractJsonObject(raw);
    if (json == null) {
      return DeepSearchResult(
        error: '深寻结果格式不正确（缺 JSON 结果块）',
        rawText: raw,
      );
    }

    final summary = (json['summary'] as String? ?? '').trim();
    final rawMaterials = (json['materials'] as List?) ?? [];
    final materials = <Map<String, dynamic>>[];
    final seen = <String>{};
    var index = 0;
    for (final rm in rawMaterials) {
      if (rm is! Map) continue;
      final m = rm.map((k, v) => MapEntry(k.toString(), v));
      final localPath = m['localPath']?.toString() ?? '';
      final url = m['url']?.toString() ?? '';
      final title = m['title']?.toString() ?? '未命名';
      final fingerprint = _evidenceFingerprint(url, title);
      if (!seen.add(fingerprint)) continue;
      final hasSource = url.startsWith('http://') || url.startsWith('https://');
      final candidatePath = localPath.isNotEmpty ? p.normalize(p.join(agentWs, localPath)) : null;
      final rootPrefix = agentWs.endsWith(Platform.pathSeparator) ? agentWs : '$agentWs${Platform.pathSeparator}';
      final safeLocalPath = candidatePath != null && (candidatePath == agentWs || candidatePath.startsWith(rootPrefix)) ? candidatePath : null;
      materials.add({
        'citationId': 'ev_${++index}',
        'title': m['title']?.toString() ?? '未命名',
        'url': url,
        'type': m['type']?.toString() ?? 'article',
        'localPath': safeLocalPath,
        'authors': m['authors']?.toString(),
        'year': m['year']?.toString(),
        'summary': m['summary']?.toString() ?? '',
        'pageRefs': (m['pageRefs'] is List) ? m['pageRefs'] : const [],
        'sourceExcerpt': m['sourceExcerpt']?.toString() ?? '',
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'confidence': hasSource ? _confidenceFor(m) : 0.15,
        'sourceStatus': hasSource ? 'verified_url' : 'missing_url',
        'fingerprint': fingerprint,
      });
    }

    if (summary.isEmpty && materials.isEmpty) {
      return DeepSearchResult(
          error: '深寻结果为空（无摘要无材料）', rawText: raw);
    }
    return DeepSearchResult(
      summary: summary,
      materials: materials,
      rawText: raw,
    );
  }

  String _evidenceFingerprint(String url, String title) {
    final source = '${url.trim().toLowerCase()}|${title.trim().toLowerCase()}';
    var hash = 0x811c9dc5;
    for (final c in source.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  double _confidenceFor(Map<String, dynamic> material) {
    final url = material['url']?.toString() ?? '';
    final type = material['type']?.toString() ?? '';
    var score = 0.5;
    if (url.startsWith('https://')) score += 0.1;
    if (url.contains('arxiv.org') || url.contains('.gov') || url.contains('.edu')) score += 0.25;
    if (type == 'paper' || type == 'article') score += 0.05;
    return score.clamp(0.0, 1.0).toDouble();
  }

  // ── 提示词 ──

  String _systemPrompt(SearchSource source) {
    final strategy = switch (source) {
      SearchSource.arxiv => '''
你是 arXiv 论文深寻 Agent。任务：围绕用户需求检索 arXiv 及相关学术源的高质量论文。
策略：
1. 优先用 arxiv_search 和 crossref_search 检索论文/正式出版物元数据，再用 web_search 补充引用与相关页面；
2. 用 web_fetch 打开 arxiv 搜索页/论文页，解析标题/作者/年份/PDF 直链（arxiv.org/pdf/xxxx）；
3. 用 download_file 把 PDF 下载到工作区 materials/ 下（save_path 如 materials/paper1.pdf）；
4. 用 pdf_extract_text 提取 PDF 文本预览，判断相关性；扫描版失败可用 ocr_file；
5. 优先收录：近年、高被引、与主题直接相关；重复命中说明该经验值得参考。
''',
      SearchSource.web => '''
你是通用网络深寻 Agent。任务：围绕用户需求在互联网上检索权威信息（技术文章、官方文档、最佳实践、开源项目）。
策略：
1. 技术方案优先用 github_search 找真实仓库和实现，再用 web_search 补充官方文档；
2. 用 web_fetch 打开高价值页面（官方文档/知名博客/GitHub），提炼要点；
3. 发现 PDF/长文时用 download_file 下载到 materials/，再用 pdf_extract_text 读；
4. 优先收录：官方来源、知名机构、可验证的原文，避免营销软文与不可信转载。
''',
      SearchSource.books => '''
你是书籍/长文深寻 Agent。任务：围绕用户需求检索相关书籍、电子书、长篇教程（如 O'Reilly、GitBook、出版社官网、开放书库）。
策略：
1. 用 web_search 检索书名/主题 + pdf/epub/在线版；
2. 用 web_fetch 打开书页/目录页，找到可读章节或 PDF 直链；
3. 用 download_file 下载可获取的 PDF 到 materials/，pdf_extract_text 读内容；
4. 无法下载时记录书的元数据（书名/作者/出版社/简介）并给出访问链接；
5. 优先收录：权威出版、覆盖面广、与主题直接相关。
''',
    };
    return '''
你是多 agent Skill 创作流水线中的「深寻 Agent」。$strategy

硬性要求：
- 只采集与主题相关的资料，宁缺毋滥；
- 专业来源必须优先使用对应专用 Tool，web_search 只用于补充发现；
- 每个下载的文件都必须记录到结果 JSON 的 materials 中（localPath 为工作区相对路径）；
- 结束时**只输出**一个 JSON 对象（不要解释、不要 markdown 包裹），格式：
{"summary": "<本轮采集成果综述（200 字内）>", "materials": [{"title": "...", "url": "...", "type": "paper|book|article", "localPath": "materials/xxx.pdf", "authors": "...", "year": "...", "summary": "<该材料要点>", "pageRefs": [1,2], "sourceExcerpt": "<原文短摘录>"}]}
''';
  }

  String _userPrompt(SearchTask task, String feedback) {
    final fb = feedback.trim().isEmpty
        ? '（首次执行）'
        : '\n【规划 Agent 的交涉反馈】$feedback\n请据此修订或返工后重新采集。';
    return '''
主题需求：${task.query}
来源：${searchSourceLabel(task.source)}
执行轮次：第 ${task.attempts + 1} 次
$fb

请开始采集，结束后按系统提示输出 JSON 结果。
''';
  }
}

// ═══════ 规划/整合/验收单轮助手 ═══════

/// 规划 agent：根据需求生成按来源拆分的任务清单。
///
/// 返回 `[{"source": "arxiv|web|books", "query": "..."}]`。
Future<List<Map<String, dynamic>>> planTasks({
  required agent.Provider provider,
  required String requirement,
}) async {
  const system = '''
你是多 agent Skill 创作流水线的「规划 Agent」。根据用户需求，把采集工作按来源拆分成多个并行深寻任务。
来源类型：arxiv（学术论文）、web（通用网络）、books（书籍/长文）。
要求：
- 每个任务给出该来源下的具体检索主题（query），尽量具体可检索；
- 来源数量按需求复杂度 1-3 个，不必全部使用；
- 只输出 JSON 数组，不要解释、不要 markdown 包裹。
''';
  final raw = await singleRound(
    provider: provider,
    systemPrompt: system,
    userPrompt: '用户需求：$requirement\n\n请输出任务清单 JSON 数组。',
  );
  var t = raw.trim();
  final m = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(t);
  if (m != null) t = m.group(1)!.trim();
  final start = t.indexOf('[');
  final end = t.lastIndexOf(']');
  if (start < 0 || end <= start) {
    throw StateError('规划结果格式不正确（缺 JSON 数组）: $raw');
  }
  try {
    final list = jsonDecode(t.substring(start, end + 1));
    if (list is! List) throw const FormatException('not a list');
    return list.whereType<Map>().map((e) {
      final mm = e.map((k, v) => MapEntry(k.toString(), v));
      return {
        'source': (mm['source']?.toString() ?? 'web').toLowerCase(),
        'query': mm['query']?.toString() ?? '',
      };
    }).where((m) => (m['query'] as String).isNotEmpty).toList();
  } catch (e) {
    throw StateError('规划结果解析失败: $e\n$raw');
  }
}

/// 规划 agent：验收单个深寻任务的结果（pass / revise / redo + 反馈）。
///
/// 返回 `{"verdict": "pass|revise|redo", "feedback": "..."}`。
Future<Map<String, dynamic>> acceptTask({
  required agent.Provider provider,
  required String requirement,
  required SearchTask task,
  required String resultSummary,
  required int materialCount,
}) async {
  const system = '''
你是多 agent Skill 创作流水线的「规划 Agent」，负责验收深寻 Agent 的采集结果。
裁决标准：
- pass：结果满足用户需求（材料相关、数量合理、来源可信）；
- revise：方向对但不足（材料太少/太泛/缺关键维度）→ 给出具体修订指令；
- redo：方向错误或结果不可用 → 给出返工指令（说明该往哪个方向重找）。
提示词原则：尽量满足用户需求；只有在确实无法满足时才允许降低标准。
只输出 JSON：{"verdict": "pass|revise|redo", "feedback": "<给深寻 Agent 的指令或通过评语>"}，不要解释。
''';
  final user = '''
用户需求：$requirement

深寻任务（来源：${searchSourceLabel(task.source)}）：
主题：${task.query}
采集摘要：$resultSummary
命中材料数：$materialCount

请裁决。
''';
  final raw = await singleRound(
      provider: provider, systemPrompt: system, userPrompt: user);
  final json = extractJsonObject(raw);
  if (json == null) {
    throw StateError('验收结果格式不正确: $raw');
  }
  return {
    'verdict': json['verdict']?.toString() ?? 'pass',
    'feedback': json['feedback']?.toString() ?? '',
  };
}

/// 整合 agent：把所有验收通过的材料整理成报告（字数不限、格式不要求）。
Future<String> writeReport({
  required agent.Provider provider,
  required String requirement,
  required List<MaterialItem> materials,
}) async {
  const system = '''
你是多 agent Skill 创作流水线的「整合 Agent」。基于深寻采集到的全部材料，撰写一份信息详实的整合报告。
要求：
- 字数不限、格式不要求（可用 markdown 自由组织）；
- 内容忠于材料：提炼各材料的关键经验/方法/要点，标明来源；
- 覆盖用户需求的所有维度；重复出现的经验要指出其共识价值；
- 报告将作为「Skill 创造 Agent」的素材底稿，请保证信息完整、结构清晰。
''';
  final buf = StringBuffer()
    ..writeln('用户需求：$requirement\n')
    ..writeln('## 材料清单（${materials.length} 项）\n');
  for (var i = 0; i < materials.length; i++) {
    final m = materials[i];
    buf.writeln('### [$i] ${m.title}（${searchSourceLabel(m.source)} / ${m.type}）');
    if (m.authors != null && m.authors!.isNotEmpty) {
      buf.writeln('作者：${m.authors}；年份：${m.year ?? "未知"}');
    }
    buf.writeln('来源：${m.url}');
    if (m.summary.isNotEmpty) buf.writeln('摘要：${m.summary}');
    final text = m.textPath != null && File(m.textPath!).existsSync()
        ? File(m.textPath!).readAsStringSync()
        : '';
    if (text.isNotEmpty) {
      buf.writeln('--- 内容摘录（前 4000 字）---');
      buf.writeln(text.length > 4000 ? text.substring(0, 4000) : text);
    }
    buf.writeln();
  }
  buf.writeln('请基于以上材料撰写整合报告（可自行补充结构，但不得虚构材料中没有的信息）。');
  return singleRound(
    provider: provider,
    systemPrompt: system,
    userPrompt: buf.toString(),
    timeout: const Duration(minutes: 15),
  );
}

/// 规划 agent：终验最终 skill（pass / revise / redo + 反馈）。
Future<Map<String, dynamic>> finalAccept({
  required agent.Provider provider,
  required String requirement,
  required String draftSkillMarkdown,
}) async {
  const system = '''
你是多 agent Skill 创作流水线的「规划 Agent」，负责终验「Skill 创造 Agent」产出的最终 Skill。
检查项：
1. 是否完整覆盖用户需求；
2. 名称是否保持需求语义且为 kebab-case；
3. 正文是否结构清晰、步骤可执行、无虚构能力；
4. 是否可直接落盘为可用 Skill。
裁决：pass（通过，可导出） / revise（小修，给出具体修改点） / redo（重做，说明原因）。
只输出 JSON：{"verdict": "pass|revise|redo", "feedback": "..."}，不要解释。
''';
  final raw = await singleRound(
    provider: provider,
    systemPrompt: system,
    userPrompt: '用户需求：$requirement\n\n最终 Skill Markdown：\n$draftSkillMarkdown\n\n请终验。',
  );
  final json = extractJsonObject(raw);
  if (json == null) {
    throw StateError('终验结果格式不正确: $raw');
  }
  return {
    'verdict': json['verdict']?.toString() ?? 'pass',
    'feedback': json['feedback']?.toString() ?? '',
  };
}

/// Palace 意识事件模型。
///
/// 每一个认知碎片（灵感、教训、决策、反思、连接、节点）都是一个
/// [ConsciousnessEvent] 实例，序列化为 YAML frontmatter + Markdown body 的
/// 独立文件，存储在 `.greenix/palace/events/{YYYY}/{MM}/{id}.md`。
library;

import 'package:uuid/uuid.dart';

import 'context_snapshot.dart';

/// 认知事件的类型。
enum EventType {
  thought,       // 灵光乍现——用户主动捕捉的碎片想法
  lesson,        // 教训——从成功/失败中提炼的原则
  decision,      // 决策记录——选项→选择→理由
  reflection,    // 反思——日记/复盘中的自我观察
  connection,    // 连接——两个实体/想法之间的关联
  milestone,     // 节点——生活中的重大事件标记
}

/// 事件来源——触发此事件的功能模块。
enum SourceTool {
  agent,          // AI 助手对话
  manual,         // 用户手动输入（捕捉浮窗）
  tutor,          // AI 笔记
  todo,           // 待办
  scores,         // 成绩
  courses,        // 课程
  classroom,      // 智云课堂
  wordpecker,     // 背词
  external,       // 外部来源
}

/// 一条认知事件——Palace 的基本存储单元。
class ConsciousnessEvent {
  /// UUID v4 唯一标识。
  final String id;

  /// 事件类型。
  final EventType type;

  /// 触发来源。
  final SourceTool source;

  /// 捕捉时间。
  final DateTime capturedAt;

  /// 用户原始输入文本。
  final String rawContent;

  /// AI 自动生成的摘要（异步补全，可为空）。
  final String? aiSummary;

  /// 关联的标签 slug 列表（如 `["deep-work", "focus"]`）。
  final List<String> tagIds;

  /// 情境快照（捕捉时的应用状态）。
  final ContextSnapshot? context;

  /// 关联的其他事件 ID。
  final List<String> linkedEventIds;

  /// 关联的教训 ID（如果此事件已被提炼为结构化教训）。
  final String? lessonId;

  /// 情绪效价（-1.0 负面 ~ 1.0 正面），用户手动选择。
  final double? emotionalValence;

  /// 用户是否已确认/修订过此事件。
  final bool isVerified;

  const ConsciousnessEvent({
    required this.id,
    required this.type,
    required this.source,
    required this.capturedAt,
    required this.rawContent,
    this.aiSummary,
    this.tagIds = const [],
    this.context,
    this.linkedEventIds = const [],
    this.lessonId,
    this.emotionalValence,
    this.isVerified = false,
  });

  static final _uuid = const Uuid();

  /// 创建新事件（自动生成 UUID + 时间戳）。
  factory ConsciousnessEvent.create({
    required EventType type,
    required SourceTool source,
    required String rawContent,
    String? aiSummary,
    List<String> tagIds = const [],
    ContextSnapshot? context,
    List<String> linkedEventIds = const [],
    String? lessonId,
    double? emotionalValence,
    bool isVerified = false,
    DateTime? capturedAt,
  }) {
    return ConsciousnessEvent(
      id: _uuid.v4(),
      type: type,
      source: source,
      capturedAt: capturedAt ?? DateTime.now(),
      rawContent: rawContent,
      aiSummary: aiSummary,
      tagIds: tagIds,
      context: context,
      linkedEventIds: linkedEventIds,
      lessonId: lessonId,
      emotionalValence: emotionalValence,
      isVerified: isVerified,
    );
  }

  /// 返回此事件的标题（rawContent 的前 60 字）。
  String get title {
    final t = rawContent.replaceAll('\n', ' ').trim();
    return t.length > 60 ? '${t.substring(0, 60)}...' : t;
  }

  /// 复制并覆盖指定字段（不可变风格的更新）。
  ConsciousnessEvent copyWith({
    EventType? type,
    SourceTool? source,
    DateTime? capturedAt,
    String? rawContent,
    String? aiSummary,
    List<String>? tagIds,
    ContextSnapshot? context,
    List<String>? linkedEventIds,
    String? lessonId,
    double? emotionalValence,
    bool? isVerified,
  }) {
    return ConsciousnessEvent(
      id: id,
      type: type ?? this.type,
      source: source ?? this.source,
      capturedAt: capturedAt ?? this.capturedAt,
      rawContent: rawContent ?? this.rawContent,
      aiSummary: aiSummary ?? this.aiSummary,
      tagIds: tagIds ?? this.tagIds,
      context: context ?? this.context,
      linkedEventIds: linkedEventIds ?? this.linkedEventIds,
      lessonId: lessonId ?? this.lessonId,
      emotionalValence: emotionalValence ?? this.emotionalValence,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  // ── 序列化：完整文件内容 ──────────────────────────────────

  /// 生成完整的文件内容（YAML frontmatter + Markdown body）。
  String toFileContent() {
    final buf = StringBuffer();
    // 写入手动构造的 YAML，避免引入 yaml 依赖
    buf.writeln('---');
    buf.writeln('id: $id');
    buf.writeln('event_type: ${type.name}');
    buf.writeln('source: ${source.name}');
    buf.writeln('captured_at: ${capturedAt.toIso8601String()}');
    if (aiSummary != null && aiSummary!.isNotEmpty) {
      buf.writeln('ai_summary: ${_escapeYaml(aiSummary!)}');
    }
    if (tagIds.isNotEmpty) {
      buf.writeln('tags:');
      for (final t in tagIds) {
        buf.writeln('  - $t');
      }
    }
    if (context != null) {
      buf.writeln('context:');
      buf.writeln('  active_feature: ${context!.activeFeature ?? '~'}');
      buf.writeln('  active_task: ${_escapeYaml(context!.activeTask ?? '')}');
      if (context!.recentActions.isNotEmpty) {
        buf.writeln('  recent_actions:');
        for (final a in context!.recentActions) {
          buf.writeln('    - ${_escapeYaml(a)}');
        }
      }
      if (context!.triggerSource != null) {
        buf.writeln('  trigger_source: ${_escapeYaml(context!.triggerSource!)}');
      }
    }
    if (linkedEventIds.isNotEmpty) {
      buf.writeln('linked_events:');
      for (final lid in linkedEventIds) {
        buf.writeln('  - $lid');
      }
    }
    buf.writeln('lesson_id: ${lessonId ?? '~'}');
    buf.writeln('emotional_valence: ${emotionalValence?.toString() ?? '~'}');
    buf.writeln('is_verified: $isVerified');
    buf.writeln('---');
    buf.writeln();
    buf.write(rawContent);
    return buf.toString();
  }

  /// 从文件内容解析事件。
  factory ConsciousnessEvent.fromFileContent(String content) {
    final yamlMatch = RegExp(r'^---\n([\s\S]*?)\n---\n([\s\S]*)').firstMatch(content);
    if (yamlMatch == null) {
      throw const FormatException('无效的 Palace 事件文件：缺少 YAML frontmatter');
    }

    final yamlBody = yamlMatch.group(1)!;
    final markdownBody = (yamlMatch.group(2) ?? '').trim();

    final map = _parseYamlSimple(yamlBody);

    return ConsciousnessEvent(
      id: map['id'] ?? const Uuid().v4(),
      type: _parseEnum(EventType.values, map['event_type']) ?? EventType.thought,
      source: _parseEnum(SourceTool.values, map['source']) ?? SourceTool.manual,
      capturedAt: DateTime.tryParse(map['captured_at'] ?? '') ?? DateTime.now(),
      rawContent: markdownBody,
      aiSummary: _optional(map['ai_summary']),
      tagIds: _parseList(map, 'tags'),
      context: ContextSnapshot.fromYaml(
        _parseContextMap(yamlBody),
      ),
      linkedEventIds: _parseList(map, 'linked_events'),
      lessonId: _optional(map['lesson_id']),
      emotionalValence: double.tryParse(map['emotional_valence'] ?? ''),
      isVerified: map['is_verified'] == 'true',
    );
  }

  @override
  String toString() =>
      'ConsciousnessEvent($id, ${type.name}, "${title}")';
}

// ── 内部辅助 ────────────────────────────────────────────────

/// 极简 YAML 解析——仅处理顶层的 `key: value`、`key:` + 缩进列表。
/// 不支持嵌套 map、引用、多行字符串。Palace 的 frontmatter 足够简单。
Map<String, String> _parseYamlSimple(String yaml) {
  final result = <String, String>{};
  String? currentListKey;
  final listValues = <String>[];

  for (final line in yaml.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    // 列表项：  - value
    if (trimmed.startsWith('- ')) {
      final value = trimmed.substring(2);
      if (currentListKey != null) {
        listValues.add(value);
      }
      continue;
    }

    // 遇到新 key → 先保存之前的列表
    if (currentListKey != null && listValues.isNotEmpty) {
      result[currentListKey] = listValues.join('\n');
      listValues.clear();
      currentListKey = null;
    }

    // 嵌套 key（如 context 下的 active_feature: ...）
    if (line.startsWith('  ') && trimmed.contains(':')) {
      // 跳过，context 由 _parseContextMap 单独处理
      continue;
    }

    // 顶层 key: value
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0) {
      final key = trimmed.substring(0, colonIdx).trim();
      final value = trimmed.substring(colonIdx + 1).trim();
      if (value.isEmpty || value == '~') {
        // 可能是列表头
        currentListKey = key;
      } else {
        result[key] = value.replaceAll(RegExp(r'^"|"$'), '');
      }
    }
  }

  // 保存最后一个列表
  if (currentListKey != null && listValues.isNotEmpty) {
    result[currentListKey] = listValues.join('\n');
  }

  return result;
}

/// 解析嵌套在 frontmatter 中的 context map。
Map<String, dynamic> _parseContextMap(String yaml) {
  final result = <String, dynamic>{};
  final actions = <String>[];
  bool inContext = false;
  bool inActions = false;

  for (final line in yaml.split('\n')) {
    final trimmed = line.trim();
    final isIndented = line.startsWith(' ') || line.startsWith('\t');

    if (trimmed == 'context:') {
      inContext = true;
      continue;
    }
    if (inContext && !isIndented && trimmed.isNotEmpty) {
      inContext = false;
      inActions = false;
    }
    if (!inContext) continue;

    if (trimmed.contains(':') && trimmed.substring(trimmed.indexOf(':') + 1).trim().isEmpty &&
        !trimmed.startsWith('-')) {
      if (trimmed.contains('recent_actions')) {
        inActions = true;
        continue;
      }
    }
    if (inActions && trimmed.startsWith('- ')) {
      actions.add(trimmed.substring(2));
      continue;
    }
    if (inActions && !trimmed.startsWith('- ') && trimmed.contains(':')) {
      inActions = false;
      if (actions.isNotEmpty) result['recent_actions'] = List<String>.from(actions);
    }

    final colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0 && !trimmed.startsWith('- ')) {
      final key = trimmed.substring(0, colonIdx).trim();
      final value = trimmed.substring(colonIdx + 1).trim();
      if (value.isNotEmpty && value != '~') {
        result[key] = value.replaceAll(RegExp(r'^"|"$'), '');
      }
    }
  }
  if (inActions && actions.isNotEmpty) result['recent_actions'] = List<String>.from(actions);
  return result;
}

/// 解析换行分隔的列表。
List<String> _parseList(Map<String, String> map, String key) {
  final raw = map[key];
  if (raw == null || raw.isEmpty) return [];
  return raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// 从可选值字符串中提取非空值。
String? _optional(String? value) {
  if (value == null || value.isEmpty || value == '~') return null;
  return value;
}

/// 按名称解析枚举值。
T? _parseEnum<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  try {
    return values.firstWhere((v) => v.name == name);
  } catch (_) {
    return null;
  }
}

/// YAML 值转义——引号包裹含特殊字符的字符串。
String _escapeYaml(String value) {
  if (value.contains(':') || value.contains('#') || value.contains('\n') || value.isEmpty) {
    return '"${value.replaceAll('"', '\\"')}"';
  }
  return value;
}

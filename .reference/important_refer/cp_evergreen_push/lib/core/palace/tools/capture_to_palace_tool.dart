/// Palace Agent 工具 —— `capture_to_palace`。
///
/// 用户在 Agent 对话中可以用自然语言指挥 AI 将关键洞察写入 Palace 意识库。
/// AI 调用此工具时，会提取用户的核心想法并以结构化格式存储。
///
/// 例如：
///   用户："帮我把刚才讨论的深度工作原则记到宫殿里"
///   → AI 调用 capture_to_palace({ event_type: "lesson", content: "...", tags: [...] })
library;

import '../../agent/tool.dart';
import '../capture/quick_capture_service.dart';
import '../models/consciousness_event.dart';

/// Agent 工具：将认知碎片写入 Palace 意识库。
class CaptureToPalaceTool extends Tool {
  final QuickCaptureService _captureService;

  CaptureToPalaceTool(this._captureService);

  @override
  String get name => 'capture_to_palace';

  @override
  String get description =>
      '将当前对话中的关键洞察、反思、决定写入 Palace 意识库。'
      '当用户说"记住这个""记到宫殿""把这个想法存下来"等意图时调用此工具。'
      '自动从对话中提取核心内容，以结构化格式存储。';

  @override
  bool get readOnly => false;

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'event_type': {
            'type': 'string',
            'enum': EventType.values.map((e) => e.name).toList(),
            'description': '认知事件类型：'
                'thought=灵光乍现/碎片想法，'
                'lesson=教训/原则，'
                'decision=决策记录，'
                'reflection=反思/复盘，'
                'connection=两个想法间的关联，'
                'milestone=重大节点',
          },
          'content': {
            'type': 'string',
            'description':
                '要存储的核心内容。尽可能保留用户的原始表述，可以稍作结构化但不要改变原意。',
          },
          'tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '2-5 个标签，用简短中文或 kebab-case 英文。如 ["深度工作", "习惯", "效率"]',
          },
          'emotional_valence': {
            'type': 'number',
            'description':
                '可选情绪效价。-1.0=非常负面，0.0=中性，1.0=非常正面。不确定则不填。',
          },
        },
        'required': ['event_type', 'content'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final typeStr = args['event_type'] as String? ?? 'thought';
    final type = EventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => EventType.thought,
    );
    final content = args['content'] as String? ?? '';
    if (content.isEmpty) {
      return '[capture_to_palace] 错误：content 不能为空';
    }

    final rawTags = args['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String && t.isNotEmpty) tags.add(t);
      }
    }

    final double? emotionalValence;
    final rawValence = args['emotional_valence'];
    if (rawValence is num) {
      emotionalValence = rawValence.toDouble().clamp(-1.0, 1.0);
    } else {
      emotionalValence = null;
    }

    try {
      final result = await _captureService.capture(
        rawContent: content,
        type: type,
        source: SourceTool.agent,
        emotionalValence: emotionalValence,
        tags: tags,
        onProgress: (_) {}, // Agent 工具调用不需要加载文案
      );

      final buf = StringBuffer();
      buf.writeln('✅ 已存入 Palace 意识库。');
      buf.writeln('- 事件 ID：${result.event.id}');
      buf.writeln('- 类型：${type.name}');
      if (result.event.aiSummary != null && result.event.aiSummary!.isNotEmpty) {
        buf.writeln('- 摘要：${result.event.aiSummary}');
      }
      if (result.lesson != null) {
        buf.writeln('- 教训：${result.lesson!.corePrinciple}');
        buf.writeln('  追问：');
        for (final q in result.followUpQuestions) {
          buf.writeln('    • $q');
        }
      }
      return buf.toString();
    } catch (e) {
      return '[capture_to_palace] 写入失败: $e';
    }
  }
}

/// Palace 教训提取器 —— 从事件内容中提取结构化教训。
///
/// 使用 DeepSeekProvider 分析事件的 rawContent + aiSummary，
/// 输出 [StructuredLesson] 草稿（version=0，待用户确认）。
library;

import '../../agent/message.dart';
import '../../agent/provider.dart' show Provider, ProviderEventKind;
import '../models/consciousness_event.dart';
import '../models/structured_lesson.dart';

/// AI 驱动的教训提取器。
class LessonExtractor {
  final Provider _llm;

  LessonExtractor(this._llm);

  static const _systemPrompt = '''
你是一个认知提炼专家。用户捕捉了一条想法/反思/决策，你需要从中提取一条**可操作的教训原则**。

## 输出格式
请用以下 JSON 格式输出：
```json
{
  "core_principle": "一句话核心原则（不超过 50 字）",
  "elaboration": "详细阐述——为什么这条原则成立，有什么支撑证据（不超过 300 字）"
}
```

## 规则
1. 如果事件的 rawContent 本身已经足够精炼，直接提炼核心原则，不要改写原意。
2. 如果事件内容模糊、不足以提炼教训，core_principle 用空字符串 ""，elaboration 说明原因。
3. 原则对个人有意义即可，不需要普适性——这是个人知识库。
4. 用中文输出。
''';

  /// 从事件中提取结构化教训。
  /// 返回的 [StructuredLesson] 版本号为 0（草稿态）。
  Future<StructuredLesson> extract(ConsciousnessEvent event) async {
    final userPrompt = '''
## 事件类型
${event.type.name}

## 事件内容
${event.rawContent}

## AI 摘要
${event.aiSummary ?? '(无)'}

请提取教训。''';

    try {
      final rawJson = await _callLlm(_systemPrompt, userPrompt);
      final parsed = _parseLessonJson(rawJson);
      final principle = parsed['core_principle'] ?? '';
      final elaboration = parsed['elaboration'] ?? '';

      if (principle.isEmpty) {
        return StructuredLesson.draft(
          corePrinciple: event.title,
          elaboration: elaboration.isNotEmpty
              ? elaboration
              : 'AI 无法从当前内容中提取清晰教训——请手动编辑。',
          sourceEventIds: [event.id],
        );
      }

      return StructuredLesson.draft(
        corePrinciple: principle,
        elaboration: elaboration,
        sourceEventIds: [event.id],
      );
    } catch (_) {
      // LLM 失败 → 返回降级草稿
      return StructuredLesson.draft(
        corePrinciple: event.title,
        elaboration: '（AI 提取失败——请手动编辑此教训）',
        sourceEventIds: [event.id],
      );
    }
  }

  Future<String> _callLlm(String systemPrompt, String userPrompt) async {
    final buf = StringBuffer();
    await for (final event in _llm.chat(
      messages: [
        Message.system(systemPrompt),
        Message.user(userPrompt),
      ],
    )) {
      if (event.kind == ProviderEventKind.content && event.text != null) {
        buf.write(event.text);
      }
    }
    return buf.toString();
  }

  Map<String, String> _parseLessonJson(String raw) {
    // 提取 JSON 块
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (jsonMatch == null) return {};

    try {
      // 手动解析简单 JSON（避免 flutter/foundation 依赖）
      final json = jsonMatch.group(0)!;
      final coreMatch =
          RegExp(r'"core_principle"\s*:\s*"([^"]*)"').firstMatch(json);
      final elabMatch =
          RegExp(r'"elaboration"\s*:\s*"([^"]*)"', dotAll: true).firstMatch(json);
      return {
        if (coreMatch != null) 'core_principle': coreMatch.group(1)!,
        if (elabMatch != null)
          'elaboration': elabMatch.group(1)!.replaceAll('\\n', '\n'),
      };
    } catch (_) {
      return {};
    }
  }
}

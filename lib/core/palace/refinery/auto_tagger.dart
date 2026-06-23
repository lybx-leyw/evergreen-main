/// Palace 自动标签建议器。
///
/// 从事件的 rawContent 中提取 2-5 个标签建议。如果用户已手动打标签，
/// 则跳过 AI 建议（返回空列表）。
library;

import '../../agent/message.dart';
import '../../agent/provider.dart' show Provider, ProviderEventKind;

/// AI 驱动的标签建议器。
class AutoTagger {
  final Provider _llm;

  AutoTagger(this._llm);

  static const _systemPrompt = '''
你是一个认知标签专家。给定一段用户的想法/反思/决策，请建议 2-5 个简洁的标签。

## 规则
1. 标签应为 kebab-case 英文或简短中文（2-6 字）。
2. 标签应该描述内容的主题、领域、情绪或认知类型。
3. 如"深度工作"、"效率"、"习惯"、"反思-睡眠"、"决策-职业"。
4. 输出 JSON 格式：{"tags": ["标签1", "标签2", "标签3"]}
5. 只输出 JSON，不要其他文字。
''';

  /// 从文本内容建议标签。
  /// [existingTags] 如果非空，表示用户已手动打标签，跳过 AI 建议。
  Future<List<String>> suggest(
    String rawContent, {
    List<String> existingTags = const [],
  }) async {
    if (existingTags.isNotEmpty) return [];

    final userPrompt = rawContent.length > 500
        ? '${rawContent.substring(0, 500)}...'
        : rawContent;

    try {
      final rawJson = await _callLlm(userPrompt);
      return _parseTagJson(rawJson);
    } catch (_) {
      return []; // 标签建议失败不阻塞主流程
    }
  }

  Future<String> _callLlm(String userPrompt) async {
    final buf = StringBuffer();
    await for (final event in _llm.chat(
      messages: [
        Message.system(_systemPrompt),
        Message.user(userPrompt),
      ],
    )) {
      if (event.kind == ProviderEventKind.content && event.text != null) {
        buf.write(event.text);
      }
    }
    return buf.toString();
  }

  List<String> _parseTagJson(String raw) {
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (jsonMatch == null) return [];

    try {
      final json = jsonMatch.group(0)!;
      final tagsMatch =
          RegExp(r'"tags"\s*:\s*\[([\s\S]*?)\]').firstMatch(json);
      if (tagsMatch == null) return [];

      final listContent = tagsMatch.group(1)!;
      final tags = <String>[];
      final quotedMatches = RegExp(r'"([^"]*)"').allMatches(listContent);
      for (final m in quotedMatches) {
        final t = m.group(1)!.trim();
        if (t.isNotEmpty && t.length < 20) tags.add(t);
      }
      return tags.take(5).toList();
    } catch (_) {
      return [];
    }
  }
}

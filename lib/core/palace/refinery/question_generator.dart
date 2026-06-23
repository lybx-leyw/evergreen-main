/// Palace 追问生成器 —— 对每条新教训生成 3 个苏格拉底式追问。
///
/// 帮助用户深度反思教训的边界、反例和来源，推动从"模糊感觉"
/// 到"清晰原则"的认知升级。
library;

import '../../agent/message.dart';
import '../../agent/provider.dart' show Provider, ProviderEventKind;
import '../models/structured_lesson.dart';

/// AI 驱动的追问生成器。
class QuestionGenerator {
  final Provider _llm;

  QuestionGenerator(this._llm);

  static const _systemPrompt = '''
你是一个苏格拉底式导师。用户刚刚记录了一条个人教训，你需要通过提问帮助他们深度反思。

## 规则
1. 生成 3 个问题。每个问题不超过 30 字。
2. 问题应该引导用户思考：
   - 这条教训的边界在哪里？（什么情况下不适用？）
   - 有没有反例？
   - 它来自哪次具体经历？
   - 是否曾经违背过这条原则？发生了什么？
3. 用中文，语气温和但尖锐。
4. 用 JSON 格式输出：{"questions": ["问题1", "问题2", "问题3"]}
''';

  /// 对一条新教训生成 3 个追问。
  Future<List<String>> generate(StructuredLesson lesson) async {
    final userPrompt = '''
## 教训
**核心原则**：${lesson.corePrinciple}
**详细阐述**：${lesson.elaboration}
**版本**：v${lesson.version}${lesson.version == 0 ? '（草稿）' : ''}

请生成 3 个追问。''';

    try {
      final rawJson = await _callLlm(userPrompt);
      return _parseQuestions(rawJson);
    } catch (_) {
      return [
        '这条教训的边界在哪里——什么情况下不适用？',
        '你能想起一个违背了这条原则的经历吗？',
        '这条教训是来自一次深刻经历，还是多次重复后慢慢发现的？',
      ];
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

  List<String> _parseQuestions(String raw) {
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (jsonMatch == null) return [];

    try {
      final json = jsonMatch.group(0)!;
      final questionsMatch =
          RegExp(r'"questions"\s*:\s*\[([\s\S]*?)\]').firstMatch(json);
      if (questionsMatch == null) return [];

      final listContent = questionsMatch.group(1)!;
      final questions = <String>[];
      final quotedMatches = RegExp(r'"([^"]*)"').allMatches(listContent);
      for (final m in quotedMatches) {
        final q = m.group(1)!.trim();
        if (q.isNotEmpty) questions.add(q);
      }
      return questions.take(3).toList();
    } catch (_) {
      return [];
    }
  }
}

/// AI 驱动的 Skill 生成器——根据用户需求描述，调用 LLM 生成完整的 Skill Markdown。
///
/// # 用法
/// ```dart
/// final skill = await SkillGenerator.generate(
///   provider: deepSeekProvider,
///   requirements: '一个帮助整理桌面文件的助手',
/// );
/// // skill 包含 name / description / body，可预览后保存
/// ```
///
/// # 公开类
///
/// | 类 | 说明 |
/// |---|------|
/// | [SkillGenerator] | 静态 `generate()` 方法，返回生成的 Skill |
/// | [SkillGenerateResult] | 生成结果：成功 → Skill 对象，失败 → error |
library;

import '../agent.dart' as agent;
import 'skill.dart';

// ═══════ SkillGenerateResult ═══════

/// Skill 生成结果——成功时 [skill] 非 null，失败时 [error] 非 null。
class SkillGenerateResult {
  /// 成功时返回生成的 Skill（未保存到磁盘）。
  final Skill? skill;

  /// 失败时返回错误信息。
  final String? error;

  const SkillGenerateResult._({this.skill, this.error});

  bool get isSuccess => skill != null;
}

// ═══════ SkillGenerator ═══════

/// 根据用户需求自动生成 Skill 内容的后端逻辑。
///
/// 使用 LLM 将用户的自然语言需求转换为格式正确的 Skill Markdown
/// （含 YAML frontmatter + Markdown body）。不会自动保存到磁盘——
/// 调用方拿到 [Skill] 后自行决定是否写入文件。
class SkillGenerator {
  SkillGenerator._();

  /// 系统提示词——教 LLM 如何写出好的 Skill。
  static const _systemPrompt = '''
You are a Skill authoring assistant. Your task is to generate a high-quality Skill definition based on the user's requirements.

A Skill is a Markdown file with YAML frontmatter that teaches an AI agent how to perform a specific task. The format is:

```markdown
---
name: skill-name
description: One-line description shown in the skill list
run_as: inline
---
# Skill Title

## When to use this skill
...

## How to perform the task
1. Step one
2. Step two
...

## Important notes
...
```

## Rules for writing good Skills

1. **name**: Use lowercase kebab-case (e.g. `desktop-organizer`, `latex-helper`). Keep it short and descriptive.
2. **description**: One line (max 80 chars) that clearly states what the skill does. This is shown in the UI skill list.
3. **run_as**: Always use `inline` unless the skill needs its own subagent.
4. **body**: Write clear, actionable instructions. Include:
   - When this skill should be activated
   - Step-by-step procedure
   - What tools to use (if applicable)
   - Any constraints or rules to follow
   - Examples of good vs bad behavior

## Output format

Reply ONLY with the complete skill Markdown (frontmatter + body). Do not wrap it in code fences. Do not add any commentary before or after.
''';

  /// 生成 Skill 的用户提示词模板。
  static String _userPrompt(String requirements, String? name) {
    final nameHint = name != null && name.isNotEmpty
        ? 'The user wants the skill to be named "$name". '
        : '';
    return '${nameHint}Please create a skill for the following requirements:\n\n$requirements';
  }

  /// 根据用户需求生成一个 Skill。
  ///
  /// [provider] — LLM API 提供者（DeepSeekProvider 等）。
  /// [requirements] — 用户用自然语言描述的需求。
  /// [name] — 可选：用户指定的技能名称，为 null 时由 AI 自动命名。
  ///
  /// 返回 [SkillGenerateResult]。成功时 `.skill` 包含生成的 Skill 对象
  /// （尚未保存到磁盘）。失败时 `.error` 包含错误信息。
  static Future<SkillGenerateResult> generate({
    required agent.Provider provider,
    required String requirements,
    String? name,
  }) async {
    if (requirements.trim().isEmpty) {
      return const SkillGenerateResult._(error: '需求描述不能为空');
    }

    try {
      final messages = [
        agent.Message.system(_systemPrompt),
        agent.Message.user(_userPrompt(requirements.trim(), name)),
      ];

      // 收集 LLM 响应中的所有 content 文本
      final buffer = StringBuffer();
      final stream = provider.chat(messages: messages, tools: []);
      await for (final event in stream) {
        if (event.kind == agent.ProviderEventKind.content && event.text != null) {
          buffer.write(event.text!);
        } else if (event.kind == agent.ProviderEventKind.error) {
          return SkillGenerateResult._(
              error: 'LLM 调用失败: ${event.error ?? "未知错误"}');
        }
      }

      final raw = buffer.toString().trim();
      if (raw.isEmpty) {
        return const SkillGenerateResult._(error: 'AI 未生成任何内容，请重试');
      }

      // 去除可能的代码块包裹
      var cleaned = raw;
      if (cleaned.startsWith('```')) {
        final firstNewline = cleaned.indexOf('\n');
        if (firstNewline > 0) {
          cleaned = cleaned.substring(firstNewline + 1);
        }
        if (cleaned.endsWith('```')) {
          cleaned = cleaned.substring(0, cleaned.length - 3).trimRight();
        }
      }

      // 解析 frontmatter + body
      final parsed = _parseSkillMarkdown(cleaned);
      if (parsed == null) {
        return SkillGenerateResult._(
            error: 'AI 生成的格式不正确，请重试。'
                '内容预览:\n${cleaned.substring(0, cleaned.length.clamp(0, 200))}');
      }

      return SkillGenerateResult._(skill: parsed);
    } catch (e) {
      return SkillGenerateResult._(error: '生成失败: $e');
    }
  }

  /// 解析 Skill Markdown 文本，提取 frontmatter 和 body。
  ///
  /// 返回 [Skill] 对象，解析失败返回 null。
  static Skill? _parseSkillMarkdown(String text) {
    final fmMatch =
        RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)').firstMatch(text);

    if (fmMatch == null) {
      // 没有 frontmatter —— 尝试从首行提取名称
      final firstLine = text.split('\n').first.trim();
      final name = firstLine.replaceAll(RegExp(r'^#+\s*'), '')
          .replaceAll(RegExp(r'\s+'), '-')
          .toLowerCase();
      if (name.isEmpty) return null;
      return Skill(
        name: name,
        description: name,
        body: text,
        scope: SkillScope.custom,
        path: '',
      );
    }

    final fm = fmMatch.group(1)!;
    final body = fmMatch.group(2)?.trim() ?? '';

    String name = '';
    String description = '';
    String runAs = 'inline';
    final allowedTools = <String>[];

    for (final line in fm.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim().replaceAll(RegExp(r'^"|"$'), '');
      switch (key) {
        case 'name':
          name = value;
        case 'description':
          description = value;
        case 'run_as':
        case 'runAs':
          runAs = value;
      }
    }

    if (name.isEmpty) return null;
    if (description.isEmpty) description = name;

    return Skill(
      name: name,
      description: description,
      body: body,
      scope: SkillScope.custom,
      path: '',
      runAs: runAs == 'subagent' ? SkillRunAs.subagent : SkillRunAs.inline,
    );
  }
}

/// AI 改稿服务——对「新建技能」表单草稿做单轮润色/补全，结果回填表单。
///
/// # 用法
/// ```dart
/// final result = await SkillRewriter.rewrite(
///   provider: deepSeekProvider,
///   name: 'summarize-code',
///   description: '总结代码',
///   body: '', // 场景 1：未填正文 → AI 补全
///   runAs: 'inline',
/// );
/// if (result.data != null) {
///   // 回填表单：result.data!.name / .description / .body
/// } else {
///   // 展示 result.error，可重试，不回填
/// }
/// ```
///
/// # 设计
/// - 复用「直连 DeepSeek + 单轮提示词」模式（与主题创作 AI 同款），
///   不依赖 AgentAssembly、不写任何会话/主题文件；
/// - 双场景：只填名称+描述 → AI 补全细节；已写正文 → 不改变原意地优化；
/// - 硬约束：不改名称语义（仅规范化 kebab-case）、不无中生有大改、
///   run_as 保持用户选择、输出结构对齐现有 skill 落盘格式
///   （frontmatter：name / description / run_as + Markdown body）；
/// - [parseOutput] 为公开纯函数，便于轻量单测（不涉文件系统、不调 LLM）。
///
/// # 公开类
///
/// | 类 | 说明 |
/// |---|------|
/// | [SkillRewriteData] | 改稿结果：name / description / body / runAs |
/// | [SkillRewriteResult] | rewrite() 返回值：成功 → data，失败 → error |
/// | [SkillRewriter] | 静态 `rewrite()` + 纯函数 `parseOutput()` / `normalizeName()` |
library;

import '../agent.dart' as agent;

// ═══════ SkillRewriteData ═══════

/// 改稿结果数据——供表单回填（name / description / body），
/// runAs 与用户下拉选择保持一致。
class SkillRewriteData {
  /// 规范化后的技能名（kebab-case，保持用户原语义）。
  final String name;

  /// 润色后的一行描述。
  final String description;

  /// 补全/优化后的技能正文（纯 Markdown body，不含 frontmatter）。
  final String body;

  /// 执行方式：inline 或 subagent。
  final String runAs;

  const SkillRewriteData({
    required this.name,
    required this.description,
    required this.body,
    required this.runAs,
  });
}

// ═══════ SkillRewriteResult ═══════

/// 改稿结果——成功时 [data] 非 null，失败时 [error] 非 null。
///
/// 失败（网络/解析）时调用方应提示用户重试，且**不得回填脏数据**。
class SkillRewriteResult {
  /// 成功时返回可回填的数据（未写入任何文件）。
  final SkillRewriteData? data;

  /// 失败时返回错误信息。
  final String? error;

  const SkillRewriteResult._({this.data, this.error});

  bool get isSuccess => data != null;
}

// ═══════ SkillRewriter ═══════

/// AI 改稿后端逻辑——单轮生成 + 解析回填，独立于主题会话逻辑。
class SkillRewriter {
  SkillRewriter._();

  /// 系统提示词——职责 + 落盘格式 + 双场景规则 + 硬性约束。
  static const String _systemPrompt = '''
你是资深 Skill 作者与编辑。用户正在「新建技能」表单中填写一个 Skill，请你做一次「AI 改稿」：把用户填写的草稿加工成一条可直接落盘的 Skill。

Skill 是带 YAML frontmatter 的 Markdown 文件，落盘格式如下（字段必须完整）：

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

## 改稿规则

先判断用户处于哪种场景：

**场景 1：用户只填写了名称和描述（技能正文为空）**
- 润色 description，使其更准确、简洁、专业；
- 补全一份完整、可用的技能正文：适用场景、分步执行流程、约束与注意事项、正反示例；
- 目标：把"一句话"扩成"一条可用 skill"。

**场景 2：用户已填写技能正文**
- 在不改变用户原意的前提下优化：精简冗余、结构化分节（## 小节）、补充示例、统一术语与口径；
- 不要推翻重写，不要引入与用户意图不符的新能力。

## 硬性约束

1. **name**：保持用户名称的语义，仅做 kebab-case 规范化（小写、空格/下划线/驼峰转连字符），严禁另起名；
2. **不无中生有大改**：正文忠于用户输入，只做补全/优化，不虚构用户意图之外的能力；
3. **run_as 必须与用户给定值完全一致**（inline 或 subagent），不得更改；
4. **description 保持一行**，简洁明确；
5. 正文用清晰的 Markdown 小节（## 开头），步骤用有序列表；
6. 只输出上述完整 Skill Markdown（frontmatter + 正文），不要任何解释、评论，不要用代码块包裹。
''';

  /// 构建用户提示词——携带表单草稿，正文为空时注明场景 1。
  static String _userPrompt({
    required String name,
    required String description,
    required String body,
    required String runAs,
  }) {
    final trimmed = body.trim();
    final bodySection = trimmed.isEmpty
        ? '（未填写——请按场景 1 补全完整技能正文）'
        : '\n【正文开始】\n$trimmed\n【正文结束】';
    return '''
【用户填写的技能草稿】
- 名称: $name
- 描述: $description
- 运行方式(run_as): $runAs
- 技能正文: $bodySection

请按规则完成改稿，只输出完整 Skill Markdown。
''';
  }

  /// 根据表单草稿执行一次 AI 改稿。
  ///
  /// [provider] — LLM API 提供者（DeepSeekProvider 等）。
  /// [name] / [description] — 必填（表单校验已保证非空）。
  /// [body] — 技能正文，可为空（空 → 场景 1 补全；非空 → 场景 2 优化）。
  /// [runAs] — 用户在下拉中选择的运行方式（inline / subagent），
  /// 解析时以此为准，AI 无权更改。
  ///
  /// 返回 [SkillRewriteResult]。成功时 `.data` 包含可回填的
  /// name / description / body（不写入磁盘）。失败时 `.error` 可重试。
  static Future<SkillRewriteResult> rewrite({
    required agent.Provider provider,
    required String name,
    required String description,
    required String body,
    required String runAs,
  }) async {
    if (name.trim().isEmpty || description.trim().isEmpty) {
      return const SkillRewriteResult._(error: '请先填写技能名称和描述');
    }

    try {
      final messages = [
        agent.Message.system(_systemPrompt),
        agent.Message.user(_userPrompt(
          name: name.trim(),
          description: description.trim(),
          body: body,
          runAs: runAs,
        )),
      ];

      // 单轮流式生成——复用「直连 DeepSeek」模式，无会话/无断点续做。
      final buffer = StringBuffer();
      final stream = provider.chat(messages: messages, tools: const []);
      await for (final event in stream) {
        if (event.kind == agent.ProviderEventKind.content &&
            event.text != null) {
          buffer.write(event.text!);
        } else if (event.kind == agent.ProviderEventKind.error) {
          return SkillRewriteResult._(
              error: 'AI 调用失败: ${event.error ?? "未知错误"}');
        }
      }

      final raw = buffer.toString().trim();
      if (raw.isEmpty) {
        return const SkillRewriteResult._(error: 'AI 未返回任何内容，请重试');
      }

      final data = parseOutput(raw, fallbackRunAs: runAs, fallbackName: name);
      if (data == null) {
        final preview =
            raw.length > 200 ? raw.substring(0, 200) : raw;
        return SkillRewriteResult._(
            error: 'AI 返回格式不正确，请重试。内容预览:\n$preview');
      }

      return SkillRewriteResult._(data: data);
    } catch (e) {
      return SkillRewriteResult._(error: '改稿失败: $e');
    }
  }

  /// 解析 AI 输出的 Skill Markdown，提取回填数据（纯函数，可单测）。
  ///
  /// 要求输出为「frontmatter（name/description/run_as）+ Markdown body」，
  /// 与现有 skill 落盘格式一致；无 frontmatter / 缺关键字段 → 返回 null。
  ///
  /// [fallbackRunAs] — AI 未给出或给出非法 run_as 时回退的用户选择。
  /// [fallbackName] — AI 未给出 name 时回退的用户名称（再规范化）。
  static SkillRewriteData? parseOutput(
    String text, {
    String fallbackRunAs = 'inline',
    String fallbackName = '',
  }) {
    var cleaned = text.trim();

    // 去除可能的代码块包裹（```markdown ... ``` 等）。
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline > 0) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trimRight();
      }
    }

    final fmMatch =
        RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)').firstMatch(cleaned);
    if (fmMatch == null) return null;

    final fm = fmMatch.group(1)!;
    final body = fmMatch.group(2)?.trim() ?? '';

    var name = '';
    var description = '';
    var runAs = '';

    for (final line in fm.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      var value = line.substring(colon + 1).trim();
      // 去掉值两侧的引号（"value" / 'value'）。
      value = value.replaceAll(RegExp(r'^"|"$'), '').replaceAll(RegExp(r"^'|'$"), '');
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

    // 名称：AI 未给时回退用户输入，再做 kebab-case 规范化。
    if (name.isEmpty) name = fallbackName;
    name = normalizeName(name);
    if (name.isEmpty) return null;

    // 描述 / 正文缺失 → 格式不正确（可重试），不回填。
    if (description.isEmpty) return null;
    if (body.isEmpty) return null;

    // run_as：仅接受 inline / subagent；否则回退用户选择。
    final resolvedRunAs = (runAs == 'inline' || runAs == 'subagent')
        ? runAs
        : fallbackRunAs;

    return SkillRewriteData(
      name: name,
      description: description,
      body: body,
      runAs: resolvedRunAs,
    );
  }

  /// 名称规范化（纯函数，可单测）：小写 + 非字母数字转连字符 + 合并/去首尾。
  ///
  /// 只做形式规范化，不改变语义。中文等无法 kebab 化的输入原样保留
  /// （小写化），避免把用户名称改得面目全非。
  static String normalizeName(String name) {
    var s = name.trim().toLowerCase();
    final normalized = s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isNotEmpty) return normalized;
    // 全中文/纯符号输入：保留原样（小写化），保证 name 非空。
    return s;
  }
}

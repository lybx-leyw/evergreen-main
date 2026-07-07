/// OutputStyle 系统 — 可选择的输出风格/persona。
///
/// 对应 reasonix/internal/outputstyle/。
/// 通过注入不同的 persona/语调指令到 system prompt 中改变 Agent 的沟通方式。
library;

/// 一种可选择的输出风格。
class OutputStyle {
  /// 标识符（不区分大小写）。
  final String name;

  /// 一行描述。
  final String description;

  /// Body 文本——追加到 system prompt (keepCoding=true) 或替换整个 prompt (false)。
  final String body;

  /// true=追加到编程 system prompt；false=完全替换。
  final bool keepCoding;

  /// 是否为内置风格。
  final bool builtin;

  /// 文件路径（内置风格为空字符串）。
  final String path;

  const OutputStyle({
    required this.name,
    required this.description,
    required this.body,
    this.keepCoding = true,
    this.builtin = false,
    this.path = '',
  });
}

// ─── 内置风格 ─────────────────────────────────────────────

/// 内置输出风格——无需文件系统，始终可用。
class BuiltinStyles {
  /// 解释型：边工作边解释非显而易见的实现选择。
  static const explanatory = OutputStyle(
    name: 'explanatory',
    description: '解释非显而易见的实现选择',
    keepCoding: true,
    builtin: true,
    body: '沟通风神——解释型：在工作的同时，梳理出非显而易见图行选择背后的思考。'
        '在实质性更改之后，添加简短的"## 精讲"说明，覆盖关键权衡或被拒绝的替代方案。'
        '讲解 why，不只讲 what；保持简短。',
  );

  /// 学习型：协作方式，留下 TODO(human) 由用户完成。
  static const learning = OutputStyle(
    name: 'learning',
    description: '协作模式，留下 TODO(human) 由用户完成',
    keepCoding: true,
    builtin: true,
    body: '沟通风神——学习型：以协作方式工作，而非全包全揽。'
        '当出现有意义的设计决策时，停下来让用户做选择。'
        '对于最有教学价值的片段，编写周边代码但留下清晰的 `TODO(human)` 标记。',
  );

  /// 简洁型：精简回复，仅用代码和要点。
  static const concise = OutputStyle(
    name: 'concise',
    description: '精简回复：最少的散文，仅用代码和要点',
    keepCoding: true,
    builtin: true,
    body: '沟通风神——简洁型：回复保持精炼。无需开场白或结束语，不重复用户请求。'
        '优先使用代码和短要点而非段落；用最少的词句保持清晰。',
  );

  /// 教学型（新增）：苏格拉底追问式教学。
  static const socratic = OutputStyle(
    name: 'socratic',
    description: '苏格拉底追问式教学：不直接给答案，用提问引导学生',
    keepCoding: true,
    builtin: true,
    body: '沟通风格——苏格拉底式：你是一位循循善诱的导师。'
        '不直接给出答案，而是通过一系列提问引导学生自己得出结论。'
        '当学生的回答正确时给予肯定，当回答偏离时温和地纠正方向。'
        '使用中文，语气温和、耐心。'
        '每次只问一个问题，等待学生回答后再继续。',
  );

  /// 所有内置风格。
  static List<OutputStyle> get all => [explanatory, learning, concise, socratic];

  /// 按名称查找。
  static OutputStyle? byName(String name) {
    try {
      return all.firstWhere(
        (s) => s.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

// ─── 风格管理器 ─────────────────────────────────────────────

/// 输出风格管理器。
class StyleManager {
  OutputStyle? _current;

  /// 当前风格（null=不使用，使用默认 system prompt）。
  OutputStyle? get current => _current;

  /// 设置当前风格。
  void setStyle(OutputStyle? style) {
    _current = style;
  }

  /// 按名称设置风格。
  bool setByName(String name, {List<OutputStyle> extras = const []}) {
    // 先查内置
    final builtin = BuiltinStyles.byName(name);
    if (builtin != null) {
      _current = builtin;
      return true;
    }
    // 再查额外风格
    try {
      _current = extras.firstWhere(
        (s) => s.name.toLowerCase() == name.toLowerCase(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清除风格（回到默认）。
  void clear() => _current = null;

  /// 将当前风格注入到 system prompt 中。
  /// [basePrompt] 是原始的 system prompt。
  String applyTo(String basePrompt) {
    if (_current == null) return basePrompt;
    if (_current!.keepCoding) {
      return '$basePrompt\n\n${_current!.body}';
    }
    return _current!.body;
  }
}

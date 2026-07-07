/// Agent 工具：加载并运行一个 Skill。
///
/// Skill 是保存在 .greenix/skills/ 下的 Markdown 文件，
/// AI 在需要时载入并按其指引调整回应方式。
///
/// - inline: 返回 skill body，主 AI 阅读理解后按指引回应
/// - subagent: 启动隔离子 Agent，skill body 作为 system prompt，
///            子 Agent 独立运行后返回最终回复
///
/// 每次调用时从磁盘热加载——手动放入新 .md 文件无需重启即可生效。
library;

import '../../agent/tool.dart';
import '../../agent/provider.dart';
import '../../agent/tool.dart' show Registry;
import '../../agent/event.dart';
import '../../agent/agent/agent.dart';
import '../../agent/agent/session.dart';
import '../skill/skill.dart';

/// 运行 Skill 的工具。
class RunSkillTool extends Tool {
  final SkillLoader _loader;
  final SkillIndex _builtinIndex;
  final Provider _llm;
  final Registry _registry;

  RunSkillTool(this._loader, this._builtinIndex, this._llm, this._registry);

  @override
  String get name => 'run_skill';

  @override
  String get description =>
      '加载并运行一个指定的 Skill。'
      'inline 模式返回 skill body 供你阅读理解；'
      'subagent 模式启动隔离子 Agent，按 skill 指引独立运行后返回最终回复。'
      '参数 name 为 Skill 名称（如 "acceptance"）。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '要加载的 Skill 名称，如 acceptance',
          },
        },
        'required': ['name'],
      };

  SkillIndex _reloadIndex() {
    final idx = SkillIndex();
    idx.addAll(_loader.loadAll());
    BuiltinSkills.loadInto(idx);
    return idx;
  }

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final name = args['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      final idx = _reloadIndex();
      final available = idx.all().map((s) => s.name).join('、');
      return '请指定要加载的 Skill 名称。当前可用的 Skill：$available';
    }

    final idx = _reloadIndex();
    final skill = idx.get(name);
    if (skill == null) {
      final available = idx.all().map((s) => s.name).join('、');
      return '未找到名为 "$name" 的 Skill。当前可用的 Skill：$available';
    }

    if (skill.runAs == SkillRunAs.subagent) {
      return await _runSubagent(skill);
    }
    return _formatInline(skill);
  }

  /// Inline 模式：返回 skill body 供主 AI 阅读理解。
  String _formatInline(Skill skill) {
    final buf = StringBuffer();
    buf.writeln('## 已加载 Skill：${skill.name}');
    buf.writeln();
    buf.writeln('**描述**：${skill.description}');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln(skill.body);
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('**请严格按照以上 Skill 的指引调整你的回应方式。**');
    return buf.toString();
  }

  /// Subagent 模式：启动隔离子 Agent，skill body 作为 system prompt。
  Future<String> _runSubagent(Skill skill) async {
    try {
      // 子 Agent 的 session（空 session，只有本次请求）
      final session = Session();
      final sink = StreamEventSink();

      // 子 Agent：继承主 Agent 的工具注册表
      final agent = Agent(
        provider: _llm,
        registry: _registry,
        session: session,
        sink: sink,
        options: const AgentOptions(maxSteps: 50),
      );

      // 用 skill body 作为系统提示词，发起子 Agent 运行
      const input = '请按照加载的 Skill 指引，分析当前对话场景并给出你的回应。';

      final buf = StringBuffer();
      await for (final event in agent.run(
        input: input,
        systemPrompt: skill.body,
        memoryContext: '',
      )) {
        if (event.kind == EventKind.text && event.text != null) {
          buf.write(event.text);
        }
      }

      final output = buf.toString().trim();
      if (output.isEmpty) return '_(子 Agent 未产生有效回复)_';

      return '## 🧬 Subagent：${skill.name}\n\n$output';
    } catch (e) {
      return '[子 Agent 运行失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}

/// 列出所有可用 Skill 的工具。
class ListSkillsTool extends Tool {
  final SkillLoader _loader;
  final SkillIndex _builtinIndex;

  ListSkillsTool(this._loader, this._builtinIndex);

  @override
  String get name => 'list_skills';

  @override
  String get description =>
      '列出当前所有可用的 Skill。inline 模式返回指引供阅读，'
      'subagent 模式启动隔离子 Agent 独立运行。'
      '手动放入 .greenix/skills/ 目录的 .md 文件会自动被识别。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final idx = SkillIndex();
    idx.addAll(_loader.loadAll());
    BuiltinSkills.loadInto(idx);

    final skills = idx.all();
    if (skills.isEmpty) {
      return '当前没有可用的 Skill。将 .md 文件放入 .greenix/skills/ 目录即可添加。';
    }
    final buf = StringBuffer();
    buf.writeln('## 可用 Skill 列表 (热加载)\n');
    for (final s in skills) {
      final tag = s.runAs == SkillRunAs.subagent ? ' 🧬 subagent' : '';
      buf.writeln('- **${s.name}**$tag：${s.description}');
    }
    buf.writeln();
    buf.writeln('需要加载某个 Skill 时，使用 run_skill 工具并传入 Skill 名称。');
    return buf.toString();
  }

  @override
  bool get readOnly => true;
}

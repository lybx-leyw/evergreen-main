/// Agent 工具：写入全局记忆。
///
/// 按奥尔波特特质理论组织记忆写入：
///   - set_cardinal: 设置首要特质（一个形容词）
///   - add_central: 添加中心特质（一个或多个形容词）
///   - add_secondary: 添加次要特质（情境性偏好）
///   - remember: 添加关键事实（带时间锚定）
///   - forget: 删除匹配的记忆
library;

import '../../agent/tool.dart';
import '../memory/file_memory_store.dart';
import '../memory/memory.dart' show Memory, MemoryType;

/// 写入全局记忆的工具。
class WriteGlobalMemoryTool extends Tool {
  final FileMemoryStore _store;

  WriteGlobalMemoryTool(this._store);

  @override
  String get name => 'write_global_memory';

  @override
  String get description =>
      '将用户特质或关键事实写入跨会话持久化的全局记忆。按奥尔波特特质理论组织。'
      '适用于：用户明确要求"记住"、对话中自然了解到用户的长期特质/偏好/背景信息、'
      '需要更新或删除过时记忆。'
      '\n\n参数：'
      '- action: set_cardinal | add_central | add_secondary | set_requirement | remember | forget'
      '- trait: 特质形容词或偏好描述（set_cardinal/add_central/add_secondary 时必填）'
      '- fact: 关键事实（remember/forget 时必填），格式建议带时间锚定'
      '- priority: 仅关键事实可用 high/medium/low';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '操作类型：set_cardinal（首要特质）、add_central（中心特质）、add_secondary（次要特质）、set_requirement（用户需求）、remember（关键事实）、forget（删除）',
            'enum': ['set_cardinal', 'add_central', 'add_secondary', 'set_requirement', 'remember', 'forget'],
          },
          'trait': {
            'type': 'string',
            'description': '特质形容词（set_cardinal/add_central，如"完美主义者"）或偏好描述（add_secondary，如"写代码时偏好简洁风格"）',
          },
          'traits': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '多个特质形容词（仅 add_central 支持批量，如["勤奋","严谨","好奇"]）',
          },
          'fact': {
            'type': 'string',
            'description': '关键事实（remember/forget 时使用），格式建议"[2026年6月] 用户主修计算机科学"',
          },
          'priority': {
            'type': 'string',
            'description': '关键事实优先级：high=重要（默认）, medium=普通, low=次要',
            'enum': ['high', 'medium', 'low'],
          },
        },
        'required': ['action'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final action = args['action']?.toString() ?? 'remember';

    try {
      switch (action) {
        case 'set_cardinal':
          return await _setCardinal(args);
        case 'add_central':
          return await _addCentral(args);
        case 'add_secondary':
          return await _addSecondary(args);
        case 'set_requirement':
          return await _setRequirement(args);
        case 'remember':
          return await _remember(args);
        case 'forget':
          return await _forget(args);
        default:
          return '未知操作 "$action"。支持：set_cardinal, add_central, add_secondary, set_requirement, remember, forget。';
      }
    } catch (e) {
      return '[写入全局记忆失败: $e]';
    }
  }

  Future<String> _setCardinal(Map<String, dynamic> args) async {
    final trait = args['trait']?.toString().trim() ?? '';
    if (trait.isEmpty) return '请提供 trait（一个首要特质形容词）。';

    // 先删旧的 cardinal
    final all = await _store.all();
    for (final old in all.where((m) => m.priority == 'cardinal')) {
      await _store.delete(old.name);
    }

    final name = 'cardinal-${trait.hashCode.toRadixString(16)}';
    await _store.save(Memory(
      name: name, title: trait, description: '首要特质',
      type: MemoryType.user, body: trait, priority: 'cardinal',
    ));

    return '✅ 首要特质已设为：**$trait**\n_（旧的首要特质已覆盖）_';
  }

  Future<String> _addCentral(Map<String, dynamic> args) async {
    final traits = <String>[];
    if (args['traits'] is List) {
      traits.addAll((args['traits'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
    }
    final single = args['trait']?.toString().trim() ?? '';
    if (single.isNotEmpty) traits.add(single);
    if (traits.isEmpty) return '请提供 trait 或 traits（中心特质形容词）。';

    final buf = StringBuffer();
    buf.writeln('✅ 已添加中心特质：\n');
    for (final t in traits) {
      await _store.save(Memory(
        name: 'central-$t', title: t, description: '中心特质',
        type: MemoryType.user, body: t, priority: 'central',
      ));
      buf.writeln('- **$t**');
    }
    return buf.toString();
  }

  Future<String> _addSecondary(Map<String, dynamic> args) async {
    final trait = args['trait']?.toString().trim() ?? '';
    if (trait.isEmpty) return '请提供 trait（情境性偏好描述）。';

    await _store.save(Memory(
      name: 'secondary-${trait.hashCode.toRadixString(16)}',
      title: trait, description: '次要特质',
      type: MemoryType.user, body: trait, priority: 'secondary',
    ));

    return '✅ 已添加次要特质：_${trait}_';
  }

  Future<String> _setRequirement(Map<String, dynamic> args) async {
    final content = args['trait']?.toString().trim() ?? '';
    if (content.isEmpty) return '请提供 trait（用户需求描述，如"用中文回答""代码用 Rust"）。';

    await _store.save(Memory(
      name: 'requirement-${content.hashCode.toRadixString(16)}',
      title: content.length > 80 ? '${content.substring(0, 80)}...' : content,
      description: '用户需求',
      type: MemoryType.user, body: content, priority: 'requirement',
    ));

    return '✅ 已记录用户需求：$content\n_AI 将在后续对话中遵循此要求。_';
  }

  Future<String> _remember(Map<String, dynamic> args) async {
    final fact = args['fact']?.toString().trim() ?? '';
    if (fact.isEmpty) return '请提供 fact（关键事实，建议带时间锚定）。';

    final priority = args['priority']?.toString() ?? 'high';
    final title = fact.length > 80 ? '${fact.substring(0, 80)}...' : fact;

    await _store.save(Memory(
      name: 'fact-${fact.hashCode.toRadixString(16)}',
      title: title, description: '关键事实',
      type: MemoryType.user, body: fact, priority: priority,
    ));

    return '✅ 已记录关键事实：$title\n_（优先级：$priority）_';
  }

  Future<String> _forget(Map<String, dynamic> args) async {
    final fact = args['fact']?.toString().trim() ?? '';
    if (fact.isEmpty) return '请提供 fact（要删除的记忆关键词或内容）。';

    final matches = await _store.search(fact);
    if (matches.isEmpty) return '未找到与 "$fact" 匹配的记忆，无需删除。';

    var deleted = 0;
    final buf = StringBuffer();
    buf.writeln('✅ 已删除以下记忆：\n');
    for (final m in matches) {
      await _store.delete(m.name);
      buf.writeln('- ~~${m.title}~~');
      deleted++;
    }
    return buf.toString();
  }

  @override
  bool get readOnly => false;
}

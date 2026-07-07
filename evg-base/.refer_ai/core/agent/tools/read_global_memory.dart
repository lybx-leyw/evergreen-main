/// Agent 工具：读取全局记忆。
///
/// 按奥尔波特特质理论输出：首要特质 → 中心特质 → 次要特质 → 关键事实。
/// 新会话开始时自动调用，也可由模型在需要时主动调用。
library;

import '../../agent/tool.dart';
import '../memory/file_memory_store.dart';
import '../memory/memory.dart' show Memory;

/// 读取全局记忆的工具。
class ReadGlobalMemoryTool extends Tool {
  final FileMemoryStore _store;

  ReadGlobalMemoryTool(this._store);

  @override
  String get name => 'read_global_memory';

  @override
  String get description =>
      '读取跨会话持久化的全局记忆。按奥尔波特特质理论组织：'
      '首要特质（最核心的一个形容词）、'
      '中心特质（5-10个核心形容词）、'
      '次要特质（情境性偏好）、'
      '关键事实（客观信息，带时间锚定）。'
      '新对话开始时自动加载，也可传入 query 搜索特定内容。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词（可选）。不传返回全部，传入则按标题/内容搜索。',
          },
        },
        'required': [],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';

    try {
      final all = query.isEmpty
          ? await _store.all()
          : await _store.search(query);

      if (all.isEmpty) {
        return query.isEmpty
            ? '全局记忆为空（尚未记录用户特质或关键事实）。'
            : '未找到与 "$query" 匹配的全局记忆。';
      }

      // 分组
      final cardinals = all.where((m) => m.priority == 'cardinal').toList();
      final centrals = all.where((m) => m.priority == 'central').toList();
      final secondaries = all.where((m) => m.priority == 'secondary').toList();
      final requirements = all.where((m) => m.priority == 'requirement').toList();
      final keyFacts = all.where((m) =>
          !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority)
      ).toList();

      final buf = StringBuffer();
      buf.writeln('## 全局记忆\n');

      // 首要特质
      if (cardinals.isNotEmpty) {
        buf.writeln('### 首要特质 (Cardinal Trait)');
        buf.writeln('最能定义用户的一个支配性形容词：');
        for (final c in cardinals) {
          buf.writeln('- **${c.title}** — ${c.body}');
        }
        buf.writeln();
      }

      // 中心特质
      if (centrals.isNotEmpty) {
        buf.writeln('### 中心特质 (Central Traits)');
        buf.writeln('用户的核心特质形容词：');
        buf.writeln('- ${centrals.map((c) => '**${c.title}**').join('、')}');
        buf.writeln();
      }

      // 次要特质
      if (secondaries.isNotEmpty) {
        buf.writeln('### 次要特质 (Secondary Traits)');
        buf.writeln('在特定情境下显现的偏好/风格：');
        for (final s in secondaries) {
          buf.writeln('- ${s.title}');
        }
        buf.writeln();
      }

      // 用户需求
      if (requirements.isNotEmpty) {
        buf.writeln('### 用户需求 (User Requirements)');
        buf.writeln('用户希望 AI 做到的事项：');
        for (final r in requirements) {
          buf.writeln('- ${r.title}');
          if (r.body.isNotEmpty && r.body != r.title) {
            buf.writeln('  ${r.body}');
          }
        }
        buf.writeln();
      }

      // 关键事实
      if (keyFacts.isNotEmpty) {
        buf.writeln('### 关键事实 (Key Facts)');
        buf.writeln('客观不变的硬事实：');
        for (final f in keyFacts) {
          buf.writeln('- ${f.body.isNotEmpty ? f.body : f.title}');
        }
        buf.writeln();
      }

      buf.writeln('---');
      buf.writeln('_如果用户提供的新信息与上述矛盾，以新信息为准更新。_');
      return buf.toString().trim();
    } catch (e) {
      return '[读取全局记忆失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}

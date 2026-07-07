import 'dart:convert';
import '../message.dart';
import '../provider.dart';
import 'memory.dart' show Memory, MemoryStore, MemoryType;

/// 独立记忆 Agent——与对话 Agent 解耦。
///
/// 每轮对话后异步运行，使用独立的轻量 LLM 调用：
/// 1. 按奥尔波特特质理论分析对话，提取用户特质（形容词）和关键事实
/// 2. 检测与已有记忆的矛盾，自动更新/删除
/// 3. 写入 FileMemoryStore 持久化
///
/// 奥尔波特特质层级：
///   - 首要特质 (cardinal):  最能定义用户的一个支配性形容词
///   - 中心特质 (central):   5-10个核心特质形容词
///   - 次要特质 (secondary): 情境性偏好（特定场景下显现）
///   - 用户需求 (requirement): 用户明确表达的、希望 AI 做到的长期要求（如"用中文回答""代码用 Rust"）
///   - 关键事实 (key_fact):  客观不变的硬事实（年级、专业等，带时间锚定）
class MemoryAgent {
  final Provider _llm;
  final String _storeDir;

  MemoryAgent(this._llm, this._storeDir);

  static const _systemPrompt = '''
你是一个后台记忆管理系统。你的任务是分析对话片段，按**奥尔波特特质理论 (Allport's Trait Theory)** 提取用户信息。

## 奥尔波特特质层级

### 首要特质 (Cardinal Trait)
一个人最核心、最具支配性的**一个形容词**。它贯穿用户所有行为，定义了"这个人是什么样的"。
- 例：完美主义者、创新者、实干家、探索者、关怀者
- 只选一个最准确的形容词。如果还不确定，宁可空缺。

### 中心特质 (Central Traits)
5-10个描述用户典型行为模式的**核心形容词**。
- 例：勤奋、严谨、好奇、合作、独立、幽默、务实、开放、坚韧、细致
- 来自对话中用户表现出的稳定特征，不是单次行为。

### 次要特质 (Secondary Traits)
在特定情境下才显现的**偏好或风格**。只在特定上下文中成立。
- 例：写代码时偏好简洁风格、考试前会焦虑、讨论数学时特别兴奋、喜欢图表胜过文字、讨厌冗长的解释
- 格式：在[情境]下，用户[偏好/风格描述]

### 关键事实 (Key Facts)
客观不变的硬事实，必须带时间锚定。
- 例：[2026年6月] 用户是大三学生、主修计算机科学
- 仅记录用户明确表达的客观信息。推测一律排除。

## 规则
1. **特质用形容词**，不要用名词或句子。
2. **事实用陈述句**，必须带时间锚定。
3. **宁可漏记，不可错记**。不确定就 skip。
4. **检测矛盾**：如果新信息与已有记忆冲突（如大二→大三），标记 update。
5. **否定检测**：如果用户说"不再""已经不是""换专业了"，标记 forget。
6. 忽略临时性信息（如"今天好累""这题不会"）。

## 输出 JSON 格式
{
  "actions": [
    {"type": "set_cardinal",   "trait": "实干家"},
    {"type": "add_central",    "traits": ["勤奋", "严谨", "好奇"]},
    {"type": "remove_central", "trait": "拖延"},
    {"type": "add_secondary", "trait": "写代码时偏好简洁风格"},
    {"type": "set_requirement", "trait": "用户希望 AI 用中文回答"},
    {"type": "remember",       "fact": "[2026年6月] 用户是大三学生"},
    {"type": "update",         "old_fact": "用户是大二学生", "fact": "[2026年6月] 用户是大三学生"},
    {"type": "forget",         "old_fact": "用户主修数学"},
    {"type": "skip"}
  ]
}

type 可选值: set_cardinal | add_central | remove_central | add_secondary | set_requirement | remember | update | forget | skip
''';

  /// 分析一轮对话，提取/更新特质和事实。
  /// 返回 (added, updated, removed) 数量。
  Future<(int, int, int)> analyze(
    String userInput,
    String assistantReply,
    String timeAnchor,
  ) async {
    // 加载已有记忆
    final existingBlock = await _loadExistingContext();

    // 构建 prompt
    final prompt = '''
## 当前时间
$timeAnchor

## 已有记忆
$existingBlock

## 对话
用户：$userInput

助手：$assistantReply

请分析上述对话，输出 JSON。''';

    // 调用 LLM
    final messages = [
      Message.system(_systemPrompt),
      Message.user(prompt),
    ];
    List<Map<String, dynamic>> actions;

    try {
      final response = await _callLlm(messages);
      actions = _parseResponse(response);
    } catch (_) {
      return (0, 0, 0); // LLM 失败静默
    }

    return await _applyActions(actions);
  }

  /// 构建已有记忆的上下文字符串（Allport 格式）。
  Future<String> _loadExistingContext() async {
    final store = MemoryStore(_storeDir);
    store.load();
    final all = store.all();
    if (all.isEmpty) return '(暂无已有记忆)';

    // 按类型分组
    final cardinals = all.where((m) => m.type == MemoryType.user && m.priority == 'cardinal').toList();
    final centrals = all.where((m) => m.type == MemoryType.user && m.priority == 'central').toList();
    final secondaries = all.where((m) => m.type == MemoryType.user && m.priority == 'secondary').toList();
    final requirements = all.where((m) => m.priority == 'requirement').toList();
    final facts = all.where((m) => m.type == MemoryType.user && m.priority == 'high' ||
                             m.type != MemoryType.user).toList();

    final buf = StringBuffer();
    if (cardinals.isNotEmpty) {
      buf.writeln('首要特质：${cardinals.map((m) => m.title).join('')}');
    }
    if (centrals.isNotEmpty) {
      buf.writeln('中心特质：${centrals.map((m) => m.title).join('、')}');
    }
    if (secondaries.isNotEmpty) {
      buf.writeln('次要特质：');
      for (final s in secondaries) {
        buf.writeln('  - ${s.title}');
      }
    }
    if (requirements.isNotEmpty) {
      buf.writeln('用户需求：');
      for (final r in requirements) {
        buf.writeln('  - ${r.title}');
      }
    }
    // 过滤出真正的关键事实（非特质类）
    final keyFacts = facts.where((m) =>
        m.priority == 'high' &&
        m.type == MemoryType.user &&
        !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority)
    ).toList();
    if (keyFacts.isNotEmpty) {
      buf.writeln('关键事实：');
      for (final f in keyFacts) {
        buf.writeln('  - ${f.body}');
      }
    }
    return buf.toString();
  }

  Future<(int, int, int)> _applyActions(List<Map<String, dynamic>> actions) async {
    final store = MemoryStore(_storeDir);
    var added = 0;
    var updated = 0;
    var removed = 0;

    for (final action in actions) {
      final type = action['type'] as String? ?? '';
      switch (type) {
        case 'set_cardinal':
          final trait = (action['trait'] as String?)?.trim() ?? '';
          if (trait.isEmpty) break;
          // 先删旧的 cardinal
          store.load();
          final oldCardinal = store.all().where((m) => m.priority == 'cardinal');
          for (final old in oldCardinal) {
            store.delete(old.name);
          }
          store.save(_makeMemory('cardinal-$trait', trait, MemoryType.user, 'cardinal', trait));
          added++;
          break;

        case 'add_central':
          final traits = _parseList(action['traits'], action['trait']);
          for (final trait in traits) {
            if (trait.isEmpty) continue;
            store.save(_makeMemory('central-$trait', trait, MemoryType.user, 'central', trait));
            added++;
          }
          break;

        case 'remove_central':
          final trait = (action['trait'] as String?)?.trim() ?? '';
          if (trait.isEmpty) break;
          store.delete('central-$trait');
          removed++;
          break;

        case 'add_secondary':
          final trait = (action['trait'] as String?)?.trim() ?? '';
          if (trait.isEmpty) break;
          store.save(_makeMemory('secondary-${trait.hashCode.toRadixString(16)}', trait, MemoryType.user, 'secondary', trait));
          added++;
          break;

        case 'set_requirement':
          final trait = (action['trait'] as String?)?.trim() ?? '';
          if (trait.isEmpty) break;
          store.save(_makeMemory('requirement-${trait.hashCode.toRadixString(16)}', trait, MemoryType.user, 'requirement', trait));
          added++;
          break;

        case 'remember':
          final fact = (action['fact'] as String?)?.trim() ?? '';
          if (fact.isEmpty) break;
          store.save(_makeMemory(
            'fact-${fact.hashCode.toRadixString(16)}',
            fact.length > 80 ? '${fact.substring(0, 80)}...' : fact,
            MemoryType.user, 'high', fact,
          ));
          added++;
          break;

        case 'update':
          final oldFact = (action['old_fact'] as String?)?.trim() ?? '';
          final newFact = (action['fact'] as String?)?.trim() ?? '';
          if (oldFact.isNotEmpty) {
            store.delete('fact-${oldFact.hashCode.toRadixString(16)}');
            removed++;
          }
          if (newFact.isNotEmpty) {
            store.save(_makeMemory(
              'fact-${newFact.hashCode.toRadixString(16)}',
              newFact.length > 80 ? '${newFact.substring(0, 80)}...' : newFact,
              MemoryType.user, 'high', newFact,
            ));
            added++;
          }
          break;

        case 'forget':
          final oldFact = (action['old_fact'] as String?)?.trim() ?? '';
          if (oldFact.isNotEmpty) {
            store.delete('fact-${oldFact.hashCode.toRadixString(16)}');
            removed++;
          }
          break;
      }
    }

    return (added, updated, removed);
  }

  Memory _makeMemory(String name, String title, MemoryType type, String priority, String body) {
    return Memory(
      name: name,
      title: title,
      description: priority == 'cardinal' ? '首要特质' :
                   priority == 'central' ? '中心特质' :
                   priority == 'secondary' ? '次要特质' :
                   priority == 'requirement' ? '用户需求' : '关键事实',
      type: type,
      body: body,
      priority: priority,
    );
  }

  List<String> _parseList(dynamic traits, dynamic singleTrait) {
    if (traits is List) return traits.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    if (singleTrait is String && singleTrait.isNotEmpty) return [singleTrait.trim()];
    return [];
  }

  Future<String> _callLlm(List<Message> messages) async {
    final buf = StringBuffer();
    await for (final event in _llm.chat(messages: messages)) {
      if (event.kind == ProviderEventKind.content && event.text != null) {
        buf.write(event.text);
      }
    }
    return buf.toString();
  }

  List<Map<String, dynamic>> _parseResponse(String raw) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*"actions"[\s\S]*\}').firstMatch(raw);
      if (jsonMatch == null) return [];
      final decoded = jsonDecode(jsonMatch.group(0)!);
      final actions = decoded['actions'] as List? ?? [];
      return actions.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// 判断是否需要压缩。
  bool shouldCompact(int estimatedTokens, int contextWindow) {
    if (contextWindow <= 0) return false;
    return estimatedTokens > contextWindow * 0.7;
  }
}

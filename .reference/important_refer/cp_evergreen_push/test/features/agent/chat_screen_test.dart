/// Chat Screen 思考面板渲染逻辑测试
///
/// 覆盖 chat_screen.dart 中的关键渲染路径：
/// - 工具调度/结果事件的图标与标签
/// - :::reasoning 块解析
/// - 思考面板行前缀渲染（🧠 📋 🔧 ✅）
/// - 长结果截断
///
/// 运行: flutter test test/features/agent/chat_screen_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════
// 辅助函数 —— 镜像 chat_screen.dart 中的私有逻辑
// ═══════════════════════════════════════════════════════════

/// 根据工具名决定调度标签。
/// 对应 chat_screen.dart toolDispatch 分支。
({String icon, String label, String status}) toolDispatchLabel(String toolName) {
  final isRead = toolName == 'read_global_memory';
  final isWrite = toolName == 'write_global_memory';
  final isMemoryTool = isRead || isWrite;
  final isSkillTool = toolName == 'run_skill' || toolName == 'list_skills';

  final icon = isMemoryTool ? '🧠' : isSkillTool ? '📋' : '🔧';
  final label = isRead
      ? '回忆ing'
      : isWrite
          ? '记忆ing'
          : isSkillTool
              ? '加载 Skill'
              : '调用';
  final status = isMemoryTool
      ? '$icon ${isRead ? "回忆ing" : "记忆ing"}...'
      : isSkillTool
          ? '📋 $toolName...'
          : '调用 $toolName...';

  return (icon: icon, label: label, status: status);
}

/// 根据工具名决定结果状态文字。
/// 对应 chat_screen.dart toolResult 分支。
String toolResultStatus(String toolName) {
  final isRead = toolName == 'read_global_memory';
  final isWrite = toolName == 'write_global_memory';
  final isSkillTool = toolName == 'run_skill' || toolName == 'list_skills';

  if (isRead) return '🧠 回忆完成';
  if (isWrite) return '🧠 记忆完成';
  if (isSkillTool) return '📋 Skill 已加载';
  return '处理结果...';
}

/// 截断长输出为最多 [maxLines] 行预览。
/// 对应 chat_screen.dart toolResult 分支中的截断逻辑。
String truncateToolOutput(String output, {int maxLines = 15}) {
  final lines = output.split('\n');
  if (lines.length <= maxLines) return output;

  final preview = lines.take(maxLines).join('\n');
  final icon = output.startsWith('## 已加载 Skill') ? '📋' : '🧠';
  return '$preview\n\n$icon _...完整内容已加载（共 ${lines.length} 行）_';
}

/// 解析 :::reasoning 块，返回 (推理内容, 正文)。
/// 对应 _MessageBubble.build() 中的 reasoningMatch 正则。
({String? reasoning, String answer}) extractReasoning(String content) {
  final reasoningMatch =
      RegExp(r'^:::reasoning\n([\s\S]*?)\n:::(.?)').firstMatch(content);
  if (reasoningMatch == null) return (reasoning: null, answer: content);

  final reasoning = reasoningMatch.group(1)?.trim();
  final remaining = content.substring(reasoningMatch.end).trim();
  return (reasoning: reasoning, answer: remaining);
}

/// 判断思考面板行是否以指定前缀开头。
/// 对应 _buildThinkingContent 中的各行检测逻辑。
String classifyThinkingLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return 'empty';
  if (trimmed.startsWith('🧠')) return 'memory';
  if (trimmed.startsWith('📋')) return 'skill';
  if (trimmed.startsWith('🔧')) return 'tool_call';
  if (trimmed.startsWith('✅')) return 'tool_result';
  return 'plain';
}

/// 统计思考内容中工具调用数。
/// 对应 _countTools。
int countTools(String content) {
  return '🔧'.allMatches(content).length +
      '🧠'.allMatches(content).length +
      '📋'.allMatches(content).length;
}

/// 按时序拼接 timeline + answer，模拟 _buildCombinedMessage。
String buildTimelineMessage(String timeline, String answer) {
  final buf = StringBuffer();
  if (timeline.isNotEmpty) {
    buf.writeln(':::reasoning');
    buf.writeln(timeline);
    buf.writeln(':::');
    if (answer.isNotEmpty) buf.writeln();
  }
  buf.write(answer);
  return buf.toString().trim();
}

// ═══════════════════════════════════════════════════════════
// 1. 工具调度标签测试
// ═══════════════════════════════════════════════════════════

void testToolDispatchLabels() {
  group('toolDispatch 标签', () {
    test('read_global_memory → 回忆ing', () {
      final d = toolDispatchLabel('read_global_memory');
      expect(d.icon, '🧠');
      expect(d.label, '回忆ing');
      expect(d.status, contains('回忆ing'));
    });

    test('write_global_memory → 记忆ing', () {
      final d = toolDispatchLabel('write_global_memory');
      expect(d.icon, '🧠');
      expect(d.label, '记忆ing');
      expect(d.status, contains('记忆ing'));
    });

    test('run_skill → 加载 Skill', () {
      final d = toolDispatchLabel('run_skill');
      expect(d.icon, '📋');
      expect(d.label, '加载 Skill');
      expect(d.status, contains('📋'));
      expect(d.status, contains('run_skill'));
    });

    test('list_skills → 加载 Skill', () {
      final d = toolDispatchLabel('list_skills');
      expect(d.icon, '📋');
      expect(d.label, '加载 Skill');
    });

    test('普通工具 → 🔧 + 调用', () {
      final d = toolDispatchLabel('get_courses');
      expect(d.icon, '🔧');
      expect(d.label, '调用');
      expect(d.status, contains('get_courses'));
    });

    test('search_teacher → 🔧 + 调用', () {
      final d = toolDispatchLabel('search_teacher');
      expect(d.icon, '🔧');
      expect(d.label, '调用');
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 2. 工具结果状态测试
// ═══════════════════════════════════════════════════════════

void testToolResultStatus() {
  group('toolResult 状态', () {
    test('read_global_memory 结果 → 回忆完成', () {
      expect(toolResultStatus('read_global_memory'), '🧠 回忆完成');
    });

    test('write_global_memory 结果 → 记忆完成', () {
      expect(toolResultStatus('write_global_memory'), '🧠 记忆完成');
    });

    test('run_skill 结果 → Skill 已加载', () {
      expect(toolResultStatus('run_skill'), '📋 Skill 已加载');
    });

    test('list_skills 结果 → Skill 已加载', () {
      expect(toolResultStatus('list_skills'), '📋 Skill 已加载');
    });

    test('普通工具结果 → 处理结果...', () {
      expect(toolResultStatus('get_courses'), '处理结果...');
    });

    test('区分 read 和 write（不混淆）', () {
      final readStatus = toolResultStatus('read_global_memory');
      final writeStatus = toolResultStatus('write_global_memory');
      expect(readStatus, isNot(equals(writeStatus)));
      expect(readStatus, contains('回忆'));
      expect(writeStatus, contains('记忆'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 3. 截断逻辑测试
// ═══════════════════════════════════════════════════════════

void testTruncation() {
  group('工具结果截断', () {
    test('短于 15 行 → 完整保留', () {
      final short = List.generate(5, (i) => 'line $i').join('\n');
      expect(truncateToolOutput(short), equals(short));
    });

    test('恰好 15 行 → 完整保留', () {
      final exact = List.generate(15, (i) => 'line $i').join('\n');
      expect(truncateToolOutput(exact), equals(exact));
    });

    test('超过 15 行 → 截断', () {
      final long = List.generate(50, (i) => 'line $i').join('\n');
      final result = truncateToolOutput(long);
      expect(result, isNot(equals(long)));
      expect(result, contains('line 0'));
      expect(result, contains('line 14'));
      expect(result, isNot(contains('line 15')));
      expect(result, contains('完整内容已加载'));
      expect(result, contains('共 50 行'));
    });

    test('截断尾部包含行数统计', () {
      final long = List.generate(30, (i) => 'item $i').join('\n');
      final result = truncateToolOutput(long);
      expect(result, contains('共 30 行'));
    });

    test('空输出不变', () {
      expect(truncateToolOutput(''), isEmpty);
    });

    test('单行不变', () {
      expect(truncateToolOutput('hello'), equals('hello'));
    });

    test('Skill 长输出截断后仍带 📋 标记', () {
      final skill = '## 已加载 Skill：acceptance\n\n${List.generate(40, (i) => 'body line $i').join('\n')}';
      final result = truncateToolOutput(skill);
      expect(result, contains('📋'));
      expect(result, contains('完整内容已加载'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 4. :::reasoning 块解析测试
// ═══════════════════════════════════════════════════════════

void testReasoningExtraction() {
  group(':::reasoning 解析', () {
    test('纯文本（无 reasoning）→ reasoning=null', () {
      final r = extractReasoning('这是一段回答');
      expect(r.reasoning, isNull);
      expect(r.answer, '这是一段回答');
    });

    test('只有 reasoning → 正确分离', () {
      final r = extractReasoning(':::reasoning\n'
          '🔧 调用 get_courses\n'
          '✅ get_courses → 结果\n'
          ':::');
      expect(r.reasoning, contains('🔧'));
      expect(r.reasoning, contains('✅'));
      expect(r.answer, isEmpty);
    });

    test('reasoning + 答案 → 正确分离', () {
      final r = extractReasoning(':::reasoning\n'
          '🔧 调用 get_courses\n'
          ':::\n'
          '你有 6 门课程');
      expect(r.reasoning, contains('🔧'));
      expect(r.answer, '你有 6 门课程');
    });

    test('🧠 记忆工具在 reasoning 中', () {
      final r = extractReasoning(':::reasoning\n'
          '🧠 回忆ing\n'
          '🧠 **read_global_memory** 结果：\n'
          '\n'
          '## 全局记忆\n'
          '- 用户是浙大学生\n'
          ':::\n'
          '好的，我了解了。');
      expect(r.reasoning, contains('🧠'));
      expect(r.reasoning, contains('全局记忆'));
      expect(r.answer, '好的，我了解了。');
    });

    test('📋 Skill 在 reasoning 中', () {
      final r = extractReasoning(':::reasoning\n'
          '📋 加载 Skill run_skill\n'
          '📋 **run_skill** 结果：\n'
          '\n'
          '## 已加载 Skill：acceptance\n'
          ':::\n'
          '已按指引调整。');
      expect(r.reasoning, contains('📋'));
      expect(r.reasoning, contains('acceptance'));
      expect(r.answer, '已按指引调整。');
    });

    test('多工具混合 reasoning', () {
      final r = extractReasoning(':::reasoning\n'
          '🧠 回忆ing\n'
          '🧠 **read_global_memory** 结果：\n'
          '\n'
          '## 全局记忆\n'
          '\n'
          '📋 加载 Skill run_skill\n'
          ':::\n'
          '回答正文');
      expect(r.reasoning, contains('🧠'));
      expect(r.reasoning, contains('📋'));
      expect(r.answer, '回答正文');
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 5. 思考面板行分类测试
// ═══════════════════════════════════════════════════════════

void testLineClassification() {
  group('思考面板行分类', () {
    test('🧠 行 → memory', () {
      expect(classifyThinkingLine('🧠 回忆ing'), 'memory');
      expect(classifyThinkingLine('🧠 记忆ing'), 'memory');
      expect(classifyThinkingLine('🧠 **read_global_memory** 结果：'), 'memory');
    });

    test('📋 行 → skill', () {
      expect(classifyThinkingLine('📋 加载 Skill run_skill'), 'skill');
      expect(classifyThinkingLine('📋 _...完整 Skill 内容已加载（共 200 行）_'), 'skill');
    });

    test('🔧 行 → tool_call', () {
      expect(classifyThinkingLine('🔧 调用 get_courses'), 'tool_call');
      expect(classifyThinkingLine('🔧 调用 search_teacher'), 'tool_call');
    });

    test('✅ 行 → tool_result', () {
      expect(classifyThinkingLine('✅ get_courses → 结果'), 'tool_result');
    });

    test('空行 → empty', () {
      expect(classifyThinkingLine(''), 'empty');
      expect(classifyThinkingLine('   '), 'empty');
    });

    test('普通文本 → plain', () {
      expect(classifyThinkingLine('## 全局记忆'), 'plain');
      expect(classifyThinkingLine('- 用户是浙大学生'), 'plain');
      expect(classifyThinkingLine('普通思考文本'), 'plain');
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 6. 工具计数测试
// ═══════════════════════════════════════════════════════════

void testCountTools() {
  group('_countTools 统计', () {
    test('空内容 → 0', () {
      expect(countTools(''), 0);
    });

    test('只有 🧠 → 计 1', () {
      expect(countTools('🧠 回忆ing'), 1);
    });

    test('只有 📋 → 计 1', () {
      expect(countTools('📋 加载 Skill'), 1);
    });

    test('只有 🔧 → 计 1', () {
      expect(countTools('🔧 调用 get_courses'), 1);
    });

    test('混合 → 正确计数', () {
      final content = '🧠 回忆ing\n'
          '🧠 **结果**\n'
          '📋 加载 Skill\n'
          '🔧 调用 get_courses\n'
          '✅ 结果';
      expect(countTools(content), 4); // 2x🧠 + 1x📋 + 1x🔧
    });

    test('✅ 不计入工具数', () {
      expect(countTools('✅ get_courses → 结果'), 0);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 7. 时间线拼接测试（_buildCombinedMessage 新架构）
// ═══════════════════════════════════════════════════════════

void testTimelineMessage() {
  group('时间线拼接 (_buildCombinedMessage)', () {
    test('只有答案 → 无 reasoning 块', () {
      final msg = buildTimelineMessage('', '你好');
      expect(msg, equals('你好'));
      expect(msg, isNot(contains(':::reasoning')));
    });

    test('只有时间线 → 仅 reasoning 块', () {
      final msg = buildTimelineMessage('🔧 调用 get_courses\n✅ get_courses → 结果', '');
      expect(msg, contains(':::reasoning'));
      expect(msg, contains('🔧'));
      expect(msg, contains('✅'));
      expect(msg, isNot(contains('你好')));
    });

    test('时间线 + 答案 → reasoning 块在上，答案在下', () {
      final timeline = '🧠 回忆ing\n'
          '🧠 **read_global_memory** 结果：\n'
          '\n'
          '## 全局记忆\n'
          '- 用户是浙大学生\n'
          '\n'
          '🔧 调用 get_courses\n'
          '✅ get_courses → 查询结果';
      final answer = '你有 6 门课程';
      final msg = buildTimelineMessage(timeline, answer);

      // reasoning 块包含时间线
      expect(msg, contains(':::reasoning'));
      expect(msg, contains('🧠'));
      expect(msg, contains('🔧'));
      expect(msg, contains('✅'));
      // 答案在 ::: 之后（writeln 产生两个换行）
      final answerIdx = msg.indexOf('你有 6 门课程');
      // 找闭合的 ::: (第二个 :::)
      final firstClose = msg.indexOf(':::');
      final closeIdx = msg.indexOf(':::', firstClose + 3) + 3;
      expect(closeIdx, lessThan(answerIdx));
    });

    test('按时序：推理 → 工具 → 结果 → 推理 交织', () {
      final timeline = '让我先查一下记忆...\n'
          '🧠 回忆ing\n'
          '🧠 **read_global_memory** 结果：\n'
          '\n'
          '- 用户是浙大学生\n'
          '\n'
          '了解了，再查课程。\n'
          '🔧 调用 get_courses\n'
          '✅ get_courses → 结果';
      final answer = '好的，你是浙大学生...';
      final msg = buildTimelineMessage(timeline, answer);

      // 验证顺序：推理在工具之前
      final reasoningIdx = msg.indexOf('让我先查一下记忆');
      final memoryIdx = msg.indexOf('🧠 回忆ing');
      final toolIdx = msg.indexOf('🔧 调用 get_courses');
      expect(reasoningIdx, lessThan(memoryIdx));
      expect(memoryIdx, lessThan(toolIdx));
    });

    test('空时间线和空答案 → 空字符串', () {
      expect(buildTimelineMessage('', ''), isEmpty);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 8. 模拟真实事件流 — 镜像 _subscribeToEvents 全处理管线
// ═══════════════════════════════════════════════════════════

/// 事件管线模拟器：接收事件流，输出最终消息。
class EventPipelineSimulator {
  final StringBuffer _timeline = StringBuffer();
  final StringBuffer _answer = StringBuffer();

  // ── 事件输入 ──

  void dispatch(String toolName) {
    // 工具调用前：刷新已累积文本到时间线
    _flushAnswerToTimeline();
    final d = toolDispatchLabel(toolName);
    _timeline.writeln('\n${d.icon} ${d.label} ${d.icon == '🧠' ? '' : toolName}');
  }

  void _flushAnswerToTimeline() {
    if (_answer.isNotEmpty) {
      _timeline.write(_answer.toString());
      _answer.clear();
    }
  }

  void result(String toolName, String output) {
    final isRead = toolName == 'read_global_memory';
    final isWrite = toolName == 'write_global_memory';
    final isMemoryTool = isRead || isWrite;
    final isSkillTool = toolName == 'run_skill' || toolName == 'list_skills';
    final icon = isMemoryTool ? '🧠' : isSkillTool ? '📋' : '🔧';

    if (isMemoryTool || isSkillTool) {
      _timeline.writeln('\n$icon **$toolName** 结果：\n');
      const maxLines = 15;
      final lines = output.split('\n');
      if (lines.length > maxLines) {
        _timeline.writeln('${lines.take(maxLines).join('\n')}\n');
        _timeline.writeln('$icon _...完整内容已加载（共 ${lines.length} 行）_');
      } else {
        _timeline.writeln('$output\n');
      }
    } else {
      final preview = output.length > 200 ? '${output.substring(0, 200)}...' : output;
      _timeline.writeln('\n✅ $toolName → $preview');
    }
  }

  void reasoning(String text) {
    _timeline.write(text);
  }

  void text(String t) {
    _answer.write(t);
  }

  // ── 输出 ──

  String buildMessage() => buildTimelineMessage(
        _timeline.toString().trim(),
        _answer.toString().trim(),
      );

  String get rawTimeline => _timeline.toString();
}

/// 从消息中提取 reasoning 块内的非空行（跳过 \n 分隔符产生的空行）。
List<String> reasoningLines(String message) {
  final r = extractReasoning(message);
  if (r.reasoning == null) return [];
  return r.reasoning!.split('\n').where((l) => l.isNotEmpty).toList();
}

void testEventPipeline() {
  group('事件管线模拟 (EventPipeline)', () {
    // ── 基本场景 ──

    test('纯文本回复 → 无 reasoning 块', () {
      final sim = EventPipelineSimulator();
      sim.text('你有 6 门课程');
      final msg = sim.buildMessage();

      expect(msg, equals('你有 6 门课程'));
      expect(extractReasoning(msg).reasoning, isNull);
    });

    test('一次工具调用 + 文本回复', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('get_courses');
      sim.result('get_courses', '{"courses": [{"name": "数据结构"}]}');
      sim.text('你有 1 门课程');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      // 时间线：调用行 → 结果行
      expect(lines[0], contains('🔧'));
      expect(lines[0], contains('get_courses'));
      expect(lines[1], contains('✅'));
      expect(lines[1], contains('get_courses'));
      // 答案在 ::: 后
      expect(msg, contains('你有 1 门课程'));
    });

    test('两次工具调用交错推理', () {
      final sim = EventPipelineSimulator();
      sim.reasoning('先查一下课程...');
      sim.dispatch('get_courses');
      sim.result('get_courses', '2 courses found');
      sim.reasoning('再查成绩...');
      sim.dispatch('get_scores');
      sim.result('get_scores', 'GPA: 4.5');
      sim.text('总结');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      // 验证时序：推理1 → 工具1 → 推理2 → 工具2
      final r1 = lines.indexWhere((l) => l.contains('先查一下课程'));
      final t1 = lines.indexWhere((l) => l.contains('🔧') && l.contains('get_courses'));
      final r2 = lines.indexWhere((l) => l.contains('再查成绩'));
      final t2 = lines.indexWhere((l) => l.contains('🔧') && l.contains('get_scores'));

      expect(r1, lessThan(t1));
      expect(t1, lessThan(r2));
      expect(r2, lessThan(t2));
      expect(msg, contains('总结'));
    });

    // ── 记忆工具场景 ──

    test('读取全局记忆 + 普通工具 + 回复', () {
      final sim = EventPipelineSimulator();
      sim.reasoning('先回忆一下用户信息...');
      sim.dispatch('read_global_memory');
      sim.result('read_global_memory', '## 全局记忆\n\n- 用户是浙大学生\n- 主修计算机科学');
      sim.reasoning('了解了，查课程。');
      sim.dispatch('get_courses');
      sim.result('get_courses', '3 courses');
      sim.text('根据你的记忆，你是浙大计算机专业的学生，有3门课。');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      // 记忆调度行
      expect(lines.any((l) => l.contains('🧠') && l.contains('回忆')), isTrue);
      // 记忆结果行
      expect(lines.any((l) => l.contains('全局记忆')), isTrue);
      expect(lines.any((l) => l.contains('浙大学生')), isTrue);
      // 推理在调度之前
      final reasonIdx = lines.indexWhere((l) => l.contains('先回忆一下'));
      final memIdx = lines.indexWhere((l) => l.contains('🧠') && l.contains('回忆'));
      expect(reasonIdx, lessThan(memIdx));
      // 答案完整
      expect(msg, contains('你是浙大计算机专业的学生'));
    });

    test('写入全局记忆 + 回复', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('write_global_memory');
      sim.result('write_global_memory', '✅ 已记录关键事实：用户主修计算机科学，2026年6月');
      sim.text('已为你记住这个信息。');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      expect(lines.any((l) => l.contains('🧠') && l.contains('记忆')), isTrue);
      expect(lines.any((l) => l.contains('已记录')), isTrue);
      expect(msg, contains('已为你记住'));
    });

    // ── Skill 场景 ──

    test('加载 Skill + 回复', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('run_skill');
      sim.result('run_skill', '## 已加载 Skill：acceptance\n\n接受用户观点的指引内容...\n身体前倾表示专注...\n用"我理解"开头...');
      sim.text('已按 acceptance skill 调整回应方式。');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      expect(lines.any((l) => l.contains('📋') && l.contains('run_skill')), isTrue);
      expect(lines.any((l) => l.contains('acceptance')), isTrue);
      expect(msg, contains('已按 acceptance skill 调整'));
    });

    // ── 截断场景 ──

    test('长记忆结果 → 截断为 15 行', () {
      final sim = EventPipelineSimulator();
      final longOutput = List.generate(50, (i) => 'memory line $i').join('\n');
      sim.dispatch('read_global_memory');
      sim.result('read_global_memory', longOutput);
      sim.text('ok');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      // 验证截断存在
      expect(lines.any((l) => l.contains('完整内容已加载')), isTrue);
      expect(lines.any((l) => l.contains('共 50 行')), isTrue);
      // 验证第 15 行之后的内容不在
      expect(msg, isNot(contains('memory line 15')));
      // 验证前 15 行在
      expect(msg, contains('memory line 0'));
      expect(msg, contains('memory line 14'));
    });

    test('长 Skill 结果 → 截断为 15 行', () {
      final sim = EventPipelineSimulator();
      final longSkill = '## 已加载 Skill：huge\n\n${List.generate(100, (i) => 'body $i').join('\n')}';
      sim.dispatch('run_skill');
      sim.result('run_skill', longSkill);
      sim.text('done');

      final msg = sim.buildMessage();
      expect(msg, contains('完整内容已加载'));
      expect(msg, contains('共 102 行'));
      expect(msg, isNot(contains('body 15')));
    });

    // ── 边界场景 ──

    test('仅 reasoning 无工具无回复', () {
      final sim = EventPipelineSimulator();
      sim.reasoning('正在思考...');
      final msg = sim.buildMessage();

      expect(msg, contains(':::reasoning'));
      expect(msg, contains('正在思考...'));
      final r = extractReasoning(msg);
      expect(r.answer, isEmpty);
    });

    test('仅工具调用无回复（被取消等）', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('get_courses');
      sim.result('get_courses', 'timeout');
      final msg = sim.buildMessage();

      expect(msg, contains(':::reasoning'));
      expect(msg, contains('🔧'));
      expect(msg, contains('✅'));
      final r = extractReasoning(msg);
      expect(r.answer, isEmpty);
    });

    test('auto-read → tool → answer 完整链路', () {
      // 模拟 _autoReadGlobalMemory 后的完整对话
      final sim = EventPipelineSimulator();
      // auto-read
      sim.reasoning('让我先了解用户...');
      sim.dispatch('read_global_memory');
      sim.result('read_global_memory', '- INFJ\n- 浙大学生\n- 主修计算机');
      // 用户实际工具调用
      sim.reasoning('现在查课表。');
      sim.dispatch('get_timetable');
      sim.result('get_timetable', '周一: 数据结构, 周二: 操作系统');
      sim.text('你的课表已查到。你是计算机专业，这些是核心课程。');

      final msg = sim.buildMessage();
      final lines = reasoningLines(msg);

      // 验证 auto-read 结果在时间线中
      expect(lines.any((l) => l.contains('回忆')), isTrue);
      expect(lines.any((l) => l.contains('INFJ')), isTrue);
      // 验证后续工具也在
      expect(lines.any((l) => l.contains('get_timetable')), isTrue);
      // 答案正确
      expect(msg, contains('你的课表已查到'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 9. 推理-答案分离测试（防止思考内容泄露到回复区）
// ═══════════════════════════════════════════════════════════

void testReasoningAnswerSeparation() {
  group('推理与答案分离', () {
    test('推理文本只在 :::reasoning 内，不在答案区', () {
      final sim = EventPipelineSimulator();
      sim.reasoning('让我想一想...');
      sim.text('这是正式回复');
      final msg = sim.buildMessage();

      final r = extractReasoning(msg);
      expect(r.reasoning, contains('让我想一想'));
      expect(r.answer, equals('这是正式回复'));
      // 答案区不含推理
      expect(r.answer, isNot(contains('让我想一想')));
    });

    test('推理 + 工具 + 推理 都在 reasoning 内', () {
      final sim = EventPipelineSimulator();
      sim.reasoning('先想想...');
      sim.dispatch('get_courses');
      sim.result('get_courses', '2 courses');
      sim.reasoning('好的，总结一下...');
      sim.text('总结回复');
      final msg = sim.buildMessage();

      final r = extractReasoning(msg);
      expect(r.reasoning, contains('先想想'));
      expect(r.reasoning, contains('get_courses'));
      expect(r.reasoning, contains('总结一下'));
      expect(r.answer, equals('总结回复'));
      // 答案不含任何思考或工具内容
      expect(r.answer, isNot(contains('先想想')));
      expect(r.answer, isNot(contains('🔧')));
      expect(r.answer, isNot(contains('✅')));
    });

    test('无推理纯工具 → reasoning 仅含工具，答案独立', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('get_courses');
      sim.result('get_courses', '3 courses');
      sim.text('你有3门课');
      final msg = sim.buildMessage();

      final r = extractReasoning(msg);
      expect(r.reasoning, isNotNull);
      expect(r.reasoning, contains('🔧'));
      expect(r.answer, equals('你有3门课'));
      expect(r.answer, isNot(contains('🔧')));
      expect(r.answer, isNot(contains('get_courses')));
    });

    test('纯推理无回复（cancel 场景模拟）', () {
      // 模拟用户 cancel 时的状态：只有部分思考内容
      final sim = EventPipelineSimulator();
      sim.reasoning('让我想一想这个问题...这需要');
      // cancel 发生，没有后续 text
      final msg = sim.buildMessage();

      final r = extractReasoning(msg);
      expect(r.reasoning, isNotNull);
      expect(r.reasoning, contains('让我想一想'));
      expect(r.answer, isEmpty);
    });

    test('中途 cancel 后消息仍合法', () {
      // cancel 后 timeline 可能不完整，但消息格式应正确
      final sim = EventPipelineSimulator();
      sim.reasoning('正在查询...');
      sim.dispatch('get_courses');
      // cancel 在 result 返回之前发生
      final msg = sim.buildMessage();

      // 仍能被正确解析
      final r = extractReasoning(msg);
      expect(r.reasoning, isNotNull);
      // 推理在 reasoning 内
      expect(r.reasoning, contains('正在查询'));
      // 调度在 reasoning 内
      expect(r.reasoning, contains('🔧'));
      // 答案为空
      expect(r.answer, isEmpty);
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 10. 中间文本刷新测试（只有最后一条回复是答案）
// ═══════════════════════════════════════════════════════════

void testTextFlushToTimeline() {
  group('中间文本刷新到时间线', () {
    test('纯文本无工具 → 全部是答案', () {
      final sim = EventPipelineSimulator();
      sim.text('你有3门课程：数据结构、操作系统、计算机网络');
      final msg = sim.buildMessage();

      final r = extractReasoning(msg);
      expect(r.reasoning, isNull);
      expect(r.answer, contains('你有3门课程'));
    });

    test('文本 → 工具 → 文本：中间文本在 timeline，最后文本在答案', () {
      final sim = EventPipelineSimulator();
      sim.text('让我查一下你的课程...');
      sim.dispatch('get_courses');
      sim.result('get_courses', '3 courses');
      sim.text('你有3门课程：数据结构、操作系统、计算机网络');

      final msg = sim.buildMessage();
      final r = extractReasoning(msg);

      // 中间文本在 timeline
      expect(r.reasoning, contains('让我查一下你的课程'));
      // 最后文本是答案
      expect(r.answer, contains('你有3门课程'));
      // 答案不含中间文本
      expect(r.answer, isNot(contains('让我查一下')));
    });

    test('多轮工具调用 → 中间文本全在 timeline', () {
      final sim = EventPipelineSimulator();
      sim.text('让我查一下...');
      sim.dispatch('get_courses');
      sim.result('get_courses', '2 courses');
      sim.text('还有成绩...');
      sim.dispatch('get_scores');
      sim.result('get_scores', 'GPA: 4.5');
      sim.text('总结：你有2门课，GPA 4.5');

      final msg = sim.buildMessage();
      final r = extractReasoning(msg);

      expect(r.reasoning, contains('让我查一下'));
      expect(r.reasoning, contains('还有成绩'));
      expect(r.answer, contains('总结：你有2门课，GPA 4.5'));
      expect(r.answer, isNot(contains('让我查一下')));
      expect(r.answer, isNot(contains('还有成绩')));
    });

    test('工具调用前无文本 → 正常', () {
      final sim = EventPipelineSimulator();
      sim.dispatch('get_courses');
      sim.result('get_courses', '3 courses');
      sim.text('你有3门课');

      final msg = sim.buildMessage();
      final r = extractReasoning(msg);
      expect(r.reasoning, contains('🔧'));
      expect(r.answer, contains('你有3门课'));
    });
  });
}

// ═══════════════════════════════════════════════════════════
// 主入口
// ═══════════════════════════════════════════════════════════

void main() {
  testToolDispatchLabels();
  testToolResultStatus();
  testTruncation();
  testReasoningExtraction();
  testLineClassification();
  testCountTools();
  testTimelineMessage();
  testEventPipeline();
  testReasoningAnswerSeparation();
  testTextFlushToTimeline();
}

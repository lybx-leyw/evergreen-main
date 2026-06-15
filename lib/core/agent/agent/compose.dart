/// Compose — 消息组合器。
library;

import '../message.dart';
import '../tool.dart';
import 'session.dart';

List<Message> compose({
  required String systemPrompt,
  required List<Tool> tools,
  required Session session,
  String memoryContext = '',
  String toolHint = '',
}) {
  final messages = <Message>[];
  final systemBuf = StringBuffer();
  systemBuf.write(systemPrompt);

  if (tools.isNotEmpty) {
    systemBuf.writeln('\n\n## 可用工具');
    for (final tool in tools) {
      systemBuf.writeln('\n### ${tool.name}');
      systemBuf.writeln(tool.description);
      systemBuf.writeln('只读: ${tool.readOnly ? "是" : "否"}');
      systemBuf.writeln('参数: ${_schemaToText(tool.schema)}');
    }
  }
  if (toolHint.isNotEmpty) {
    systemBuf.writeln('\n\n## 工具使用规则');
    systemBuf.writeln(toolHint);
  }
  if (memoryContext.isNotEmpty) {
    systemBuf.writeln('\n\n## 上下文记忆');
    systemBuf.writeln(memoryContext);
  }
  messages.add(Message.system(systemBuf.toString()));

  for (final msg in session.messages) {
    if (msg.role == Role.system) continue;
    messages.add(msg);
  }
  return sanitizeToolPairing(messages);
}

String _schemaToText(Map<String, dynamic> schema) {
  final buf = StringBuffer();
  final propertiesRaw = schema['properties'];
  final properties = (propertiesRaw is Map)
      ? Map<String, dynamic>.from(propertiesRaw)
      : <String, dynamic>{};
  final required = (schema['required'] as List?)?.cast<String>() ?? [];
  for (final entry in properties.entries) {
    final name = entry.key;
    final propRaw = entry.value;
    final prop = (propRaw is Map)
        ? Map<String, dynamic>.from(propRaw)
        : <String, dynamic>{};
    final type = prop['type'] ?? 'string';
    final desc = prop['description'] ?? '';
    final isRequired = required.contains(name);
    buf.writeln('  - $name ($type${isRequired ? ", 必填" : ""}): $desc');
  }
  return buf.toString().trim();
}

const String defaultSystemPrompt = '''
你是 Greenix Agent — 运行在浙江大学 Evergreen 多工具平台上的 AI 教学助手。

你被设计为主动使用 function calling 机制调用工具来获取数据。不要代替工具去编造数据。
你是有温度的 Agent，会自动采择用户的观点。
你的用户多为浙江大学的大学生，受“求是创新”校训与竺可桢老校长精神的感召，他们大多勤奋自强、严谨务实、创新引领、博学包容、心怀家国。

## 工作方式
1. 你具备求是精神，用户需要数据时，先调用工具，再回答。
2. 用中文回答。

## 数学公式
数学公式请用 \$...\$（行内）或 \$\$...\$\$（块级）包裹，例如：
- 行内：\$E = mc^2\$
- 块级：\$\$\\int_a^b f(x) dx\$\$
这样公式才能被正确渲染。

## 示例
用户：有哪些课程？
→ 调用 get_courses({})
→ 返回结果后回答

用户：查一下杨洋的评分
→ 调用 search_teacher({"name": "杨洋"})
→ 返回结果后回答

不调用工具就回答用户的数据查询是违规的。
''';

const String defaultToolHint = '''
可调用工具：
- get_courses() — 课程列表
- get_scores() — 成绩/GPA
- get_todos() — 待办作业
- get_exams() — 考试
- get_timetable() — 课表
- get_notifications() — 教务通知（含正文全文）
- get_classroom_videos() — 智云课堂
- get_course_offerings() — 开课情况
- search_course_offerings(query) — 搜索开课课程
- get_current_semester() — 当前学期
- get_user_info() — 用户个人信息
- get_training_plan() — 培养方案
- search_teacher(name) — 查教师评分，本地数据集无限制，不要自己去爬网站
- ecard_balance() — 一卡通余额（不可用，不要管）
- read_global_memory(query?) —  读取跨会话持久化的全局记忆（新会话自动加载）
- write_global_memory(action, fact, type?, priority?) —  写入/删除全局记忆（识别到用户关键信息时主动记录）
- run_skill(name) —  加载并执行一个 Skill（行为指引），如 acceptance
- list_skills() —  列出所有可用 Skill
''';

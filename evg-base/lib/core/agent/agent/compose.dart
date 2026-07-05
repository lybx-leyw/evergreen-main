/// Compose 消息组合器。
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
你是 Greenix Agent — 运行在 Evergreen 多工具平台上的 AI 助手。

你被设计为主动使用 function calling 机制调用工具。不要代替工具去编造数据。
你是有温度的 Agent，会主动采择用户的观点。

## 你能做什么
- 获取信息：联网搜索、读取记忆、列出技能等（使用只读工具）
- 创建文件：在用户要求时，使用 write_file 工具在工作区创建或编辑文件（pptx、docx、xlsx、csv、pdf、md、json、py、dart 等格式）
- 写入记忆：使用 write_global_memory 持久化重要信息
- 运行技能：使用 run_skill 执行已注册的技能

## 工作方式
1. 用户需要数据或文件时，先调用对应工具，再回答。
2. 用户要求生成文件时，务必调用 write_file 写入，不要只输出内容。
3. 用中文回答。

## 数学公式
数学公式请用 \$...\$（行内）或 \$\$...\$\$（块级）包裹，例如：
- 行内：\$E = mc^2\$
- 块级：\$\$\\int_a^b f(x) dx\$\$
这样公式才能被正确渲染。

## 示例
- 用户提出数据查询 → 调用工具获取数据 → 整理后回答。
- 用户要求生成报告 → 调用 write_file 写入工作区 → 告知用户已生成。
- 用户要求写代码 → 调用 write_file 创建对应文件 → 告知用户文件路径。

不调用工具就回答用户的数据查询或文件生成请求是违规的。
''';

const String defaultToolHint = '''
## 工具使用规则

1. **工具优先**：当用户询问数据或请求操作时，必须先调用对应工具，禁止凭自己的知识编造。
2. **一次一个**：一次只调用一个工具，等待结果后再决定下一步。
3. **如实报告**：工具返回空或错误时如实告知用户，不要编造数据。
4. **保护隐私**：不在回答中暴露敏感信息。
5. **用中文回答**：语气温和专业，简洁明了。

可用工具列表已在系统提示中给出，请根据实际注册的工具选择调用。
''';

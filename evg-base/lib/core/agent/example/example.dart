/// Agent API 示例 — 覆盖全部对外接口，面向平台开发者与插件开发者。
///
/// 本文件以教程形式组织，从最简单的 Tool 接口开始，逐步深入到完整的模拟对话和在线 API 调用。
/// 每个 Section 都包含详细的中文注释，适合初学者按顺序阅读。
///
/// ## 学习路线
/// | Section | 受众 | 学什么 | 难度 |
/// |---------|------|--------|------|
/// | 1 | 平台 | `Tool` / `SimpleTool` — 工具怎么定义 | ★ |
/// | 2 | 平台 | `toolToSchema` / `toolsToSchemas` — Tool 如何转为 API 格式 | ★ |
/// | 3 | 平台 | `Registry` — 工具的注册/启用/禁用/调用全流程 | ★★ |
/// | 4 | 平台 | `BuiltinRegistry` — 编译时就确定的内置工具 | ★ |
/// | 5 | 平台 | `Previewer` / `ToolChange` — 写文件前的预览机制 | ★★ |
/// | 6 | 双方 | `PluginManifest` / `ArgSpec` — .exe 插件怎么声明自己 | ★★ |
/// | 7 | 插件 | 真实插件发现与执行 — 用 4 个已构建的 .exe 演示 | ★★★ |
/// | 8 | 平台 | `Message` 五种工厂 — system/user/assistant/tool 消息怎么造 | ★★ |
/// | 9 | 平台 | `Session` — 会话的消息历史、token 统计、序列化 | ★★ |
/// | 10 | 平台 | `AgentEvent` / `TokenUsage` / `StreamEventSink` — 事件总线 | ★★★ |
/// | 11 | 平台 | `OutputStyle` / `StyleManager` — 控制模型输出风格 | ★★ |
/// | 12 | 平台 | `Gate` / `PermissionRule` — 工具权限控制 | ★★ |
/// | 13 | 平台 | Flutter/Riverpod 专有 API 参考 — 在真实 App 中怎么用 | ★★ |
/// | 14 | 双方 | 模拟对话 — 上面所有组件串起来的完整流程 | ★★★ |
/// | 15 | 平台 | 在线 DeepSeek API — 真实的 HTTP 流式调用 | ★★★ |
/// | 16 | 双方 | 文件 I/O 与工作区 — workspace / read_file / write_file 六种编辑 | ★★ |
/// | 17 | 平台 | `AiUnavailableException` — 6 种工厂 + fromStatusCode 降级 | ★★ |
/// | 18 | 平台 | `MockEventStream` — 全部 17 种 EventKind 的模拟流 | ★★ |
///
/// ## API 覆盖总览
/// | 类别 | 覆盖的类/函数 |
/// |------|-------------|
/// | 工具 | `Tool` `SimpleTool` `Previewer` `ToolChange` `toolToSchema` `toolsToSchemas` |
/// | 注册表 | `Registry` `BuiltinRegistry` |
/// | 消息 | `Message`（5 种工厂）`Role` `ToolCall` `ToolSchema` `sanitizeToolPairing` |
/// | 会话 | `Session`（消息历史/token 累计/序列化往返） |
/// | 事件 | `AgentEvent` `EventKind` `TokenUsage` `ToolEventPayload` `StreamEventSink` |
/// | 风格 | `OutputStyle` `BuiltinStyles` `StyleManager` |
/// | 权限 | `PermissionLevel` `PermissionRule` `InteractiveGate` `NoOpGate`（代码片段） |
/// | 插件 | `PluginBridge` `PluginManifest` `PluginTool` `ArgSpec` |
/// | 平台 | `AgentRuntime` `ChatMessage` `SessionStoreInterface` `Controller`（代码片段） |
/// | 文件 | `WorkspaceTool` `ReadFileTool` `WriteFileTool`（六种编辑操作） |
/// | 异常 | `AiUnavailableException`（6 个工厂 + fromStatusCode） |
/// | Mock | `MockEventStream`（generate + eventKindReference） |
///
/// ## 运行方式
/// | 命令 | 说明 |
/// |------|------|
/// | `dart run example/example.dart` | 仅本地示范（sections 1–14） |
/// | `dart run example/example.dart --api-key sk-xxx` | 含在线 DeepSeek API（section 15） |
///
/// API Key 读取顺序：`--api-key` 命令行参数 → `DEEPSEEK_API_KEY` 环境变量。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 以下全部使用相对导入，兼容独立 `dart run` 场景（不依赖 Flutter 工具链）
import '../tool.dart'; // Tool / SimpleTool / Registry / BuiltinRegistry / Previewer / ToolChange
import '../event.dart'; // AgentEvent / TokenUsage / EventKind / StreamEventSink 等
import '../message.dart'; // Message / Role / ToolCall / sanitizeToolPairing
import '../tools/plugin_bridge.dart'; // PluginBridge / PluginManifest / PluginTool / ArgSpec
import '../tools/workspace_tool.dart'; // WorkspaceTool — 列出/读取工作区文件
import '../tools/read_file.dart'; // ReadFileTool — 读取磁盘文件
import '../tools/write_file.dart'; // WriteFileTool — 精准文件编辑
import '../agent/session.dart'; // Session（消息历史 + token 统计 + 序列化）
import '../output_style/style.dart'; // OutputStyle / BuiltinStyles / StyleManager
import '../provider.dart'; // AiUnavailableException
import '../tools/mock_event_stream.dart'; // MockEventStream
import '../tools/ocr_attachment_handler.dart'; // OcrAttachmentHandler / OcrResult

// ═══════ helpers ═══════
// 以下辅助函数供 main() 和各个 Demo 共用。

/// 解析 API Key。
///
/// 查找顺序（优先级从高到低）：
/// 1. 命令行参数 `--api-key <value>`
/// 2. 环境变量 `DEEPSEEK_API_KEY`
///
/// 返回 `null` 表示两者都未设置，此时 section 15（在线 API 演示）将跳过。
String? _resolveApiKey(List<String> args) {
  // Step 1：扫描命令行参数，查找 "--api-key" 标志，下一个参数即为 key
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--api-key') return args[i + 1];
  }
  // Step 2：回退到环境变量（适用于 CI / 不方便在命令行明文输入的场景）
  return Platform.environment['DEEPSEEK_API_KEY'];
}

/// 打印 section 分隔标题，使输出清晰可读。
///
/// 输出格式：空行 + `═══ 标题 ═══` + 空行。
void _section(String title) => print('\n═══ $title ═══\n');

// ═══════ main ═══════

/// 程序入口：按顺序执行 15 个 Demo。
///
/// 执行策略：
/// - sections 1–14 始终执行（纯本地，无外部依赖）
/// - section 15 仅当 API Key 可用时执行（需要网络 + 有效 key）
///
/// 每个 section 是一个独立的 `_demoXxx()` 函数，可单独跳读。
void main(List<String> args) async {
  final apiKey = _resolveApiKey(args);
  // 打印 API Key 状态（仅显示前 8 位用于确认，不泄露完整 key）
  print('API Key: ${apiKey != null ? "✅ ${apiKey.substring(0, 8)}..." : "❌ 未提供（在线 demo 将跳过）"}');

  // ── 始终执行的 sections（1–14） ──
  await _demoToolInterface(); // 1. Tool 基础
  _demoSchemaFunctions(); // 2. Schema 转换
  await _demoRegistry(); // 3. Registry 全生命周期
  _demoBuiltinRegistry(); // 4. 内置注册表
  _demoPreviewer(); // 5. 文件预览
  _demoPluginManifest(); // 6. 插件清单解析
  await _demoPlugins(); // 7. 真实插件执行
  _demoMessages(); // 8. Message 工厂
  _demoSession(); // 9. Session 会话
  _demoEvents(); // 10. 事件系统
  _demoOutputStyle(); // 11. 输出风格
  _demoGate(); // 12. 权限门控
  _demoFlutterOnlyApis(); // 13. Flutter API 参考
  await _demoSimulatedConversation(); // 14. 模拟对话

  // ── 仅当 API Key 可用时执行 section 15 ──
  if (apiKey != null) {
    await _demoLiveApi(apiKey);
  } else {
    _section('15. 在线 API 示范 — 已跳过');
    print('提供 API Key 以启用:');
    print('  dart run example/example.dart --api-key sk-xxxx');
    print('  或设置环境变量 DEEPSEEK_API_KEY');
  }

  // ── Section 16：文件 I/O 与工作区工具 ──
  await section16_fileAndWorkspaceTools();

  // ── Section 17-18：新增 API（Sprint 1 交付物） ──
  _demoAiUnavailableException(); // 17. AI 不可用降级
  await _demoMockEventStream(); // 18. Mock 事件流
}

// ═══════ 1. Tool 接口 ═══════

/// # 1. Tool 接口 — 工具怎么定义
///
/// 学习目标：理解 `Tool` 抽象类和 `SimpleTool` 便捷构造器的用法。
///
/// 核心概念：
/// - `Tool` 是 Agent 可调用的"函数"，模型通过 function calling 来调用它
/// - 每个 Tool 必须提供：name（蛇形命名）、description（给模型看）、schema（JSON Schema）、execute（真正执行）
/// - `SimpleTool` 是一种快捷方式：不需要定义子类，直接传闭包即可
Future<void> _demoToolInterface() async {
  _section('1. Tool / SimpleTool 接口');

  // ── 方式 1：继承 Tool 抽象类 ──
  // 适用场景：工具逻辑复杂、需要复用、需要配合 Previewer 等 mixin
  // 步骤：① 创建类 extends Tool  ② override name/description/schema/execute
  final echo = _EchoTool(); // _EchoTool 定义在文件末尾
  print('— Tool 子类（继承 Tool 抽象类）—');
  // name：蛇形命名（snake_case），这是模型调用时使用的标识符
  print('name: ${echo.name}');
  // description：给模型看的"使用说明书"，模型依据此字段决定何时调用
  print('description: ${echo.description}');
  // schema：JSON Schema 格式的参数定义，每个属性都要有 description 帮助模型理解
  print('schema.properties: ${echo.schema['properties']!.keys}');
  // readOnly：true=只读（可并行执行），false=写操作（需串行等待）
  print('readOnly: ${echo.readOnly}');
  // execute：真正干活的方法，接收模型生成的参数 Map，返回结果字符串
  print('execute({message: "hi"}) → ${await echo.execute({'message': 'hi'})}');

  // ── 方式 2：使用 SimpleTool ──
  // 适用场景：一次性工具、原型验证、测试用例
  // 优势：不需要定义类，所有逻辑内联在一个构造函数调用中
  print('\n— SimpleTool（内联定义，无需子类）—');
  final simple = SimpleTool(
    name: 'greet',
    description: '打招呼。',
    // schema：和 Tool 子类完全一样，JSON Schema 格式
    schema: {
      'type': 'object',
      'properties': {'name': {'type': 'string'}},
      'required': ['name'],
    },
    // execute 作为闭包传入，捕获外部变量也很方便
    execute: (args) async => 'Hello, ${args["name"]}!',
  );
  print('name: ${simple.name}');
  print('execute({name: "World"}) → ${await simple.execute({"name": "World"})}');
  // SimpleTool 和 Tool 子类在使用上没有区别——Registry 对两者一视同仁
}

// ═══════ 2. Schema 工具函数 ═══════

/// # 2. Schema 工具函数 — Tool 如何转为 API 格式
///
/// 学习目标：理解 `toolToSchema` 和 `toolsToSchemas` 的作用。
///
/// 核心概念：
/// - OpenAI/DeepSeek API 要求的 tools 参数是特定的 JSON 格式：`{type: "function", function: {name, description, parameters}}`
/// - `toolToSchema` 把一个 Tool 转成这个格式
/// - `toolsToSchemas` 是批量版本
void _demoSchemaFunctions() {
  _section('2. toolToSchema / toolsToSchemas');

  final tool = _EchoTool();
  // toolToSchema：Tool 对象 → API 兼容的 function schema map
  // 返回结构：{type: "function", function: {name: "echo", description: "...", parameters: {...}}}
  final schema = toolToSchema(tool);
  print('toolToSchema → type=${schema['type']}, function.name=${schema['function']!['name']}');
  // 这个 schema 最终会放进 API 请求的 tools 数组中

  // toolsToSchemas：批量转换，一次处理多个 Tool
  // 等价于 tools.map(toolToSchema).toList()
  final schemas = toolsToSchemas([tool, _ClockTool()]);
  print('toolsToSchemas([echo, clock]) → ${schemas.length} 个 schema');
  // 在 agent/agent.dart 中，Agent 主循环会调用 toolsToSchemas(registry.enabled())
  // 把当前所有启用的工具转为 schema 列表，传给 LLM API
}

// ═══════ 3. Registry 全生命周期 ═══════

/// # 3. Registry 全生命周期 — 工具的注册与管理
///
/// 学习目标：掌握 Registry 的全部操作——注册/查找/启用/禁用/移除/调用/异常处理。
///
/// 核心概念：
/// - Registry 是运行时工具注册表，相当于一个"工具箱"
/// - 每个工具按 name 唯一标识（重复注册会抛异常）
/// - 支持启用/禁用（临时关掉某个工具）和移除（永久删除）
/// - readOnlyToolNames 用于并行调度判断（只读工具可并行调用）
Future<void> _demoRegistry() async {
  _section('3. Registry 全生命周期');

  // 创建一个空的注册表
  final registry = Registry();

  // ── 注册工具 ──
  // register()：注册一个工具。如果 name 已存在，抛出 ArgumentError
  registry.register(_EchoTool()); // 只读工具（readOnly=true），可并行
  registry.register(_ClockTool()); // 只读工具
  registry.register(_WriteTool()); // ⚠️ 写工具（readOnly=false），必须串行

  // enabled()：返回当前启用且按 name 排序的工具列表
  print('注册后 enabled():');
  for (final t in registry.enabled()) {
    print('  - ${t.name} (readOnly=${t.readOnly})');
  }

  // ── 查找工具 ──
  // has()：工具是否存在（不论启用/禁用状态）
  print('has("echo"): ${registry.has("echo")}');
  print('has("nonexist"): ${registry.has("nonexist")}');
  // get()：按名称获取 Tool 对象，不存在返回 null
  print('get("clock")!.name: ${registry.get("clock")!.name}');

  // ── 启用/禁用 ──
  // disable()：临时禁用，工具仍在注册表中但不会被调用
  registry.disable('clock');
  print('disable("clock") → isEnabled: ${registry.isEnabled("clock")}');
  // enable()：重新启用
  registry.enable('clock');
  print('enable("clock") → isEnabled: ${registry.isEnabled("clock")}');

  // ── 移除工具 ──
  // remove()：永久删除。同时清除禁用标记
  registry.remove('clock');
  print('remove("clock") → has: ${registry.has("clock")}');

  // ── 只读工具集合 ──
  // readOnlyToolNames：返回所有 readOnly=true 的工具名
  // Agent 用它判断哪些工具可以并行调用（同一轮中同时发出多个只读工具调用）
  print('readOnlyToolNames: ${registry.readOnlyToolNames}');

  // ── 调用工具 ──
  // call(name, jsonString)：接收模型生成的原始 JSON 字符串
  // 内部：jsonDecode → execute(args) → 返回结果文本
  final r1 = await registry.call('echo', '{"message":"Hello"}');
  print('call("echo", json) → $r1');

  // callWithArgs(name, map)：参数已经解析为 Map，适合编程调用
  final r2 = await registry.callWithArgs('echo', {'message': 'World'});
  print('callWithArgs("echo", map) → $r2');

  // ── 异常情况 ──
  // 调用不存在的工具 → 返回错误文本（不抛异常，保证 Agent 循环不中断）
  final r3 = await registry.call('nope', '{}');
  print('call("nope") → $r3');

  // 调用已禁用的工具 → 同样返回错误文本
  registry.disable('echo');
  final r4 = await registry.call('echo', '{}');
  print('call 禁用工具 → $r4');

  // 重复注册 → 抛出 ArgumentError
  try {
    registry.register(_EchoTool());
  } catch (e) {
    print('重复注册 → $e');
  }
}

// ═══════ 4. BuiltinRegistry ═══════

/// # 4. BuiltinRegistry — 编译时内置工具
///
/// 学习目标：理解 BuiltinRegistry 与 Registry 的区别。
///
/// 核心概念：
/// - BuiltinRegistry 是全局静态注册表，在 main() 之前就可以注册
/// - 用于"出厂自带"的工具（如 web_search、read_global_memory）
/// - createRegistry() 方法可以从内置工具创建一个运行时 Registry
/// - 可以指定 exclude 列表排除某些内置工具
void _demoBuiltinRegistry() {
  _section('4. BuiltinRegistry');

  // 静态注册（实际项目中在 main() 之前调用）
  // 重复注册同名工具也会抛异常
  BuiltinRegistry.register(_EchoTool());

  // all()：返回所有已注册的内置工具
  print('BuiltinRegistry.all() → ${BuiltinRegistry.all().map((t) => t.name).join(", ")}');

  // get()：按名称查找
  print('BuiltinRegistry.get("echo")!.name: ${BuiltinRegistry.get("echo")!.name}');

  // createRegistry()：从内置工具创建运行时 Registry
  // exclude 参数指定要排除的工具名列表
  final r = BuiltinRegistry.createRegistry(exclude: ['echo']);
  print('createRegistry(exclude:["echo"]) → enabled: ${r.enabled().map((t) => t.name).join(", ")}');
  // 这在测试场景中很有用：排除某些工具来模拟特定环境
}

// ═══════ 5. Previewer + ToolChange ═══════

/// # 5. Previewer + ToolChange — 文件变更预览
///
/// 学习目标：理解写工具的预览机制。
///
/// 核心概念：
/// - `Previewer` 是一个 mixin，只能混入到 Tool 子类上
/// - `preview(args)` 方法在实际执行前被调用，返回 `ToolChange?`
/// - 返回 null 表示无预览（如只读工具、或不支持预览的写操作）
/// - `ToolChange` 包含 path/oldText/newText/binary 四个字段
/// - 前端用 ToolChange 展示"批准卡片"：这个工具会改什么文件？改了什么内容？
void _demoPreviewer() {
  _section('5. Previewer + ToolChange');

  final tool = _PreviewWriteTool();

  // ── 场景 1：创建新文件 ──
  // oldText 为 null 表示这是新建文件（之前不存在）
  // cast 为 Previewer 是因为 Tool 类型上不暴露 preview() 方法
  final c1 = (tool as Previewer).preview({'path': '/tmp/test', 'content': 'hello'});
  print('新文件 → path=${c1!.path}, oldText=${c1.oldText ?? "(null=新文件)"}, newText=${c1.newText}');
  // 前端看到这个 ToolChange：显示 "+ 新文件 /tmp/test"，无 diff

  // ── 场景 2：修改已有文件 ──
  // oldText + newText 都有值，前端可以做 diff 视图
  // binary=true 表示二进制文件（不显示文本 diff，只显示文件大小变化）
  final c2 = ToolChange(path: '/tmp/existing', oldText: '旧内容', newText: '新内容');
  print('修改 → path=${c2.path}, oldText=${c2.oldText}, newText=${c2.newText}');
  // 前端看到这个 ToolChange：显示 diff（旧内容 → 新内容）
}

// ═══════ 6. PluginManifest + ArgSpec ═══════

/// # 6. PluginManifest + ArgSpec — .exe 插件怎么声明自己
///
/// 学习目标：理解 manifest.json 的解析及 ArgSpec 的三种命令行风格。
///
/// 核心概念：
/// - `PluginManifest` 从 JSON 解析而来，描述一个 .exe 插件的元数据
/// - `isValid` 检查 name 是否为空（空 name 的插件会被 PluginBridge 跳过）
/// - `ArgSpec` 控制 JSON 参数如何映射到命令行参数（仅当 argMode="args" 时生效）
/// - 三种风格：flag (`--key value`)、positional（纯 value）、json（`--args=<json>`）
void _demoPluginManifest() {
  _section('6. PluginManifest.fromJson + ArgSpec 三种风格');

  // ── 解析完整的 manifest JSON ──
  // 这个 JSON 模拟了 weather 插件的配置：flag 风格 + 短 flag 映射
  const json = '''
{
  "name": "search",
  "description": "搜索工具。",
  "schema": { "type": "object", "properties": { "q": { "type": "string" } } },
  "readOnly": true,
  "argMode": "args",
  "argSpec": { "style": "flag", "prefix": "--", "flags": { "q": "-q" } }
}''';

  // fromJson：把 JSON 字符串解析为 PluginManifest 对象
  final m = PluginManifest.fromJson(json);
  // 打印所有字段，验证解析结果
  print('name: ${m.name}  |  description: ${m.description}');
  print('readOnly: ${m.readOnly}  |  argMode: ${m.argMode}  |  isValid: ${m.isValid}');
  // argSpec 的各字段：
  //   style="flag" → 每个 key 变成 --key value
  //   prefix="--" → flag 前缀
  //   flags={"q":"-q"} → key "q" 使用短 flag "-q" 而非默认 "--q"
  print('argSpec.style: ${m.argSpec.style}  prefix: ${m.argSpec.prefix}  flags: ${m.argSpec.flags}');

  // ── 无效 manifest ──
  // 空 name → isValid=false → PluginBridge.discover 会跳过这个插件
  final invalid = PluginManifest.fromJson('{"name":"","description":"","schema":{}}');
  print('空 name → isValid: ${invalid.isValid}');

  // ── ArgSpec 三种风格详解 ──
  // 输入：{"q":"hi", "limit":5}
  print('\n— ArgSpec 三种风格（输入 {"q":"hi","limit":5}）—');
  // flag 风格：每个 key 变成 --key value，支持 flags 映射和 bool 简写
  print('— flag 风格 —  prefix=-- flags={q: -q}  →  -q hi --limit 5');
  // positional 风格：按 order 数组顺序输出纯 value，不输出 key 名
  print('— positional 风格 —  order=[q, limit]  →  hi 5');
  // json 风格（默认）：整个 JSON 作为一个命令行参数传递
  print('— json 风格（默认）—  →  --args={"q":"hi","limit":5}');
  // 什么时候用哪种？
  //   flag：最常用，适合大多数 CLI 工具（Python argparse、Go flag 等）
  //   positional：适合简单命令（如 echo、grep 的参数）
  //   json：适合复杂嵌套参数，或工具本身期望 JSON 输入
}

// ═══════ 7. 插件发现与执行 ═══════

/// # 7. 插件发现与执行 — 用真实 .exe 演示
///
/// 学习目标：理解 PluginBridge 的完整流程——扫描目录 → 解析 manifest → 注册 → 执行 → 刷新。
///
/// 核心概念：
/// - `PluginBridge.discover(dir)` 同步扫描 `plugins/<name>/` 下的每个子目录
/// - 发现规则：必须有 `<name>.exe`（或目录下任一 .exe）+ 有效的 `manifest.json`
/// - 执行方式取决于 manifest.argMode：stdin（JSON 写入标准输入）或 args（根据 ArgSpec 构造命令行）
/// - 4 个示例插件覆盖了不同语言（Python/C）和不同 arg 风格
Future<void> _demoPlugins() async {
  _section('7. 插件发现与执行');

  // Step 1：指定插件目录
  final pluginsDir = Directory('example/plugins');
  if (!pluginsDir.existsSync()) {
    print('example/plugins/ 目录不存在，跳过。');
    return;
  }

  // Step 2：discover — 扫描目录，返回发现的所有 PluginTool
  // PluginBridge 内部逻辑：
  //   遍历每个子目录 → 找 .exe 文件（优先匹配目录同名的）→ 读 manifest.json → 构造 PluginTool
  final tools = PluginBridge.discover(pluginsDir);
  if (tools.isEmpty) {
    print('未发现插件（需 .exe + manifest.json）。');
    return;
  }

  // Step 3：展示每个插件的元数据
  print('PluginBridge.discover() → 发现 ${tools.length} 个插件:\n');
  for (final t in tools) {
    final pt = t as PluginTool; // 所有扫描到的都是 PluginTool 类型
    print('  ${pt.name}  |  ${pt.description}  |  readOnly=${pt.readOnly}');
    // schema.properties：工具接受的参数定义
    final props = pt.schema['properties'] as Map<String, dynamic>? ?? {};
    // schema.required：哪些参数是必填的
    final required = (pt.schema['required'] as List?)?.cast<String>() ?? <String>[];
    print('    schema: {${props.keys.join(", ")}}  required: [${required.join(", ")}]');
  }
  // 应发现 4 个：time（Python arg+flag）、date（Python stdin）、
  //            weather（Python arg+flag+短 flag）、random（C arg+flag）

  // Step 4：registerAll — 将发现的工具批量注册到 Registry
  final registry = Registry();
  PluginBridge.registerAll(registry, pluginsDir);
  print('\nregisterAll → ${registry.enabled().length} 个已注册\n');

  // Step 5：逐个执行插件
  // 每个插件的 argMode 和 argSpec 不同，PluginTool.execute 会自动选择正确的调用方式：
  //   stdin → 启动进程，JSON 写入 stdin，收集 stdout
  //   args → 根据 ArgSpec 构造命令行参数（--key value / positional / --args=json）
  final testCases = [
    // time：argMode=args, argSpec=flag → --offset 8 --format 24h
    ('time', {'offset': 8, 'format': '24h'}),
    // date：argMode=stdin → JSON 通过 stdin 传入
    ('date', {'format': 'cn'}),
    // weather：argMode=args, argSpec=flag+flags={"city":"-c","days":"-d"} → -c 北京 -d 2
    ('weather', {'city': '北京', 'days': 2}),
    // random：argMode=args, argSpec=flag, C 语言实现 → --min 1 --max 100
    ('random', {'min': 1, 'max': 100}),
  ];

  for (final tc in testCases) {
    final name = tc.$1;
    final args = tc.$2;
    if (!registry.has(name)) continue;
    // callWithArgs → PluginTool.execute → 启动 .exe 进程 → 传入参数 → 收集 stdout
    final result = await registry.callWithArgs(name, args);
    // 截断过长输出，保持控制台整洁
    final preview = result.length > 120 ? '${result.substring(0, 120)}...' : result.trimRight();
    print('  $name$args → $preview');
  }

  // Step 6：refresh — 重新扫描，同步增删
  // 如果有人在运行时新增/删除了插件目录，refresh 会同步到 Registry：
  //   新增的 → register；已删除的 → remove（通过 PluginTool 类型判断）
  print('\nrefresh() → 同步增删（当前 ${registry.enabled().length} 个）');
  PluginBridge.refresh(registry, pluginsDir);
}

// ═══════ 8. Message 工厂 ═══════

/// # 8. Message 工厂 — 对话消息怎么构建
///
/// 学习目标：掌握 4 种 Role 和 5 个工厂构造函数，以及 tool 消息的配对修复。
///
/// 核心概念：
/// - 一条 Message 代表对话历史中的一轮发言（system/user/assistant/tool）
/// - 工厂构造函数让代码更可读：`Message.user("你好")` 比 `Message(role: Role.user, content: "你好")` 更清晰
/// - `sanitizeToolPairing` 修复孤立的 tool 结果（没有对应 assistant 调用的结果），在上下文压缩后尤其重要
void _demoMessages() {
  _section('8. Message 工厂');

  // ── 五种工厂构造函数 ──
  // system：系统提示词，定义 AI 的行为边界
  final sys = Message.system('你是有用的助手。');
  // user：用户输入
  final user = Message.user('你好');
  // assistant：AI 回复，可附带 reasoning（思考过程，DeepSeek 特有）
  final assistant = Message.assistant('你好！有什么可以帮你的？', reasoning: '用户用中文打招呼');
  // assistantTool：模型决定调用工具时的消息，包含一组 ToolCall
  // ToolCall 三个字段：id（调用唯一标识）、name（工具名）、arguments（模型生成的 JSON 参数）
  final toolCall = ToolCall(id: 'call_1', name: 'search', arguments: '{"q":"天气"}');
  final toolMsg = Message.assistantTool([toolCall]);
  // toolResult：工具执行完毕后的结果消息
  // toolCallId 必须与对应的 ToolCall.id 匹配，name 是可选的
  final result = Message.toolResult('call_1', '北京晴，25°C', name: 'search');

  // 打印每种消息的关键信息
  print('system:   role=${sys.role.value}  content="${sys.content}"');
  print('user:     role=${user.role.value}  content="${user.content}"');
  print('assistant: role=${assistant.role.value}  content="${assistant.content}"  reasoning="${assistant.reasoningContent}"');
  // hasToolCalls：快捷判断是否包含工具调用
  print('assistantTool: hasToolCalls=${toolMsg.hasToolCalls}  toolCalls[0].name=${toolMsg.toolCalls[0].name}');
  // isToolResult：快捷判断是否为 tool 角色
  print('toolResult: isToolResult=${result.isToolResult}  toolCallId=${result.toolCallId}  content="${result.content}"');

  // ── toJson()：序列化为 API 兼容格式 ──
  // role=assistant + tool_calls 的 JSON 结构：
  //   {"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{...}}]}
  print('\ntoJson() — assistant 消息:');
  final json = toolMsg.toJson();
  print('  role=${json["role"]}, tool_calls 数量=${(json["tool_calls"] as List).length}');

  // ── sanitizeToolPairing：修复孤立的 tool 消息 ──
  // 什么情况下会出现孤立 tool 消息？
  //   1. 上下文压缩删除了中间的 assistant tool_calls 消息
  //   2. 手动编辑消息历史时删除了调用但保留了结果
  // 这个函数遍历消息列表，移除所有找不到对应 assistant tool_calls 的 tool result
  final orphan = Message.toolResult('orphan_id', '孤立结果'); // 没有对应的 assistant 调用
  final cleaned = sanitizeToolPairing([sys, user, assistant, orphan]);
  print('\nsanitizeToolPairing: ${[sys, user, assistant, orphan].length} → ${cleaned.length}（移除孤立的 tool 消息）');

  // interruptedToolResult：对话中断时的占位文本
  // 当用户取消对话或发生异常时，未完成的工具调用会被替换为此文本
  print('interruptedToolResult: "$interruptedToolResult"');
}

// ═══════ 9. Session ═══════

/// # 9. Session — 会话状态管理
///
/// 学习目标：理解 Session 的数据结构和操作——消息历史、token 累计、序列化。
///
/// 核心概念：
/// - Session 是 Agent 运行时的"大脑"：存储完整对话历史、追踪 token 用量
/// - id 自动生成（UUID v4），title 可自定义
/// - accumulateUsage() 每轮调用后累计 token，用于成本追踪和上下文压实判断
/// - toJson/fromJson 支持持久化（保存/恢复会话）
void _demoSession() {
  _section('9. Session');

  // 创建 Session，id 自动生成
  final session = Session(title: 'API 示范');
  print('id: ${session.id}  |  title: ${session.title}');
  print('messageCount: ${session.messageCount}'); // 初始为 0

  // ── 添加消息 ──
  // setSystemMessage：设置 system prompt（始终放在消息列表最前面）
  session.setSystemMessage('你是有用的助手。');
  // add：追加一条消息到末尾，同时自动更新 updatedAt 时间戳
  session.add(Message.user('你好'));
  session.add(Message.assistant('你好！'));
  print('添加 3 条后 → messageCount: ${session.messageCount}');
  // systemMessage：获取当前的 system prompt 消息（第一条 role=system 的消息）
  print('systemMessage: "${session.systemMessage!.content}"');

  // ── Token 用量累计 ──
  // 参数说明：
  //   promptTokens = 输入 token 数（包括 system prompt + 对话历史 + 工具结果）
  //   completionTokens = 模型输出 token 数
  //   promptCacheHitTokens = 前缀缓存命中的 token 数（省钱）
  //   promptCacheMissTokens = 未命中缓存的 token 数（正常计费）
  session.accumulateUsage(TokenUsage(
    promptTokens: 120,
    completionTokens: 50,
    totalTokens: 170,
    promptCacheHitTokens: 80,
    promptCacheMissTokens: 40,
    cacheHitRatio: 0.67,
  ));
  // totalTokens：累计所有轮次的 promptTokens + completionTokens
  print('totalTokens: ${session.totalTokens}');
  // cacheHitRate：缓存命中率（命中 / (命中+未命中)），越高越省钱
  print('cacheHitRate: ${session.cacheHitRate.toStringAsFixed(0)}%');

  // ── 序列化往返 ──
  // toJson()：将 Session 转为 Map（所有 messages 也转为 JSON）
  final json = session.toJson();
  // fromJson()：从 Map 恢复 Session（包括 messages 的逐条解析）
  final restored = Session.fromJson(json);
  print('toJson → fromJson 往返: id=${restored.id} messageCount=${restored.messageCount}');
  // 验证往返后数据一致

  // last(n)：获取最近 N 条消息（用于构造 LLM 请求时裁剪历史）
  print('last(2): ${session.last(2).map((m) => m.role.value).join(", ")}');
  // estimatedContextTokens：粗略估算上下文大小（用于压实判断，见 compact/compact.dart）
  // 算法：用 content 字符数 / 2 近似估算（中文约 2 chars/token）
  print('estimatedContextTokens: ${session.estimatedContextTokens}');
}

// ═══════ 10. AgentEvent + TokenUsage + ToolEventPayload ═══════

/// # 10. 事件系统 — Agent 如何与 UI 通信
///
/// 学习目标：理解 AgentEvent（17 种事件类型）、TokenUsage、StreamEventSink。
///
/// 核心概念：
/// - Agent 运行时通过事件流（Stream<AgentEvent>）与 UI 通信
/// - 每种事件都有对应的工厂构造函数，携带类型化负载
/// - `StreamEventSink` = `EventSink`（回调式输出） + `StreamController`（Stream 输出）
/// - UI 订阅 `runtime.events` 这个 Stream，根据不同 EventKind 渲染不同 UI
void _demoEvents() {
  _section('10. AgentEvent / TokenUsage / ToolEventPayload');

  // ── EventKind 枚举（17 种） ──
  // 完整列表：turnStarted, reasoning, text, message, toolDispatch, toolResult,
  //           usage, notice, phase, approvalRequest, askRequest, turnDone,
  //           compactionStarted, compactionDone, toolProgress, mcpSurfaceReady, retrying
  print('— EventKind 枚举 —');
  print('  ${EventKind.values.map((e) => e.name).join(", ")}');
  print('  （共 ${EventKind.values.length} 种事件类型）');

  // ── AgentEvent 工厂 — 逐一构造 ──
  print('\n— AgentEvent 工厂（逐一演示）—');
  final events = [
    // turnStarted：新一轮对话开始，前端重置渲染状态
    AgentEvent.turnStarted(),
    // reasoning：思考过程 delta（DeepSeek 的 reasoning_content），流式到达
    AgentEvent.reasoning('让我想想…'),
    // text：回答文本 delta，流式到达，前端逐字追加
    AgentEvent.text('你好！'),
    // message：完整的 assistant 消息（可包含 reasoning），前端可据此重渲染 Markdown
    AgentEvent.message(text: '完整回答', reasoning: '思考过程'),
    // toolDispatch：工具即将执行，前端显示工具调用卡片
    AgentEvent.toolDispatch(ToolEventPayload(id: 'c1', name: 'search', arguments: '{"q":"x"}', readOnly: true)),
    // toolResult：工具执行完毕，包含 output（成功）或 error（失败）
    AgentEvent.toolResult(ToolEventPayload(id: 'c1', name: 'search', arguments: '{"q":"x"}', output: '3 条结果')),
    // usage：token 用量统计（本轮累计）
    AgentEvent.usage(TokenUsage(promptTokens: 100, completionTokens: 30, totalTokens: 130)),
    // notice：带外通知，如"上下文已压缩"警告
    AgentEvent.notice('上下文已压缩', level: NoticeLevel.warn),
    // phase：阶段切换，如"planning"→"execution"
    AgentEvent.phase('execution'),
    // approvalRequest：请求用户批准工具执行（高危操作），Agent 会阻塞等待
    AgentEvent.approvalRequest(ApprovalPayload(id: 'a1', toolName: 'save_file', subject: '保存 3 个文件')),
    // retrying：API 调用失败后的重试通知（attempt/maxRetries/reason）
    AgentEvent.retrying(2, 5, 'rate limit'),
    // compactionStarted：上下文压实开始，前端显示"压缩中…"
    AgentEvent.compactionStarted('token_limit'),
    // compactionDone：压实完成，payload 包含压缩前后的消息数 + 摘要
    AgentEvent.compactionDone(CompactionPayload(trigger: 'token_limit', messagesBefore: 50, messagesAfter: 20, summary: '...')),
    // turnDone：本轮对话结束，error 非 null 表示本轮失败
    AgentEvent.turnDone(),
  ];
  for (final e in events) {
    // 提取每个事件的关键负载信息用于展示
    final extra = e.text ?? e.reasoning ?? e.tool?.name ?? e.usage?.toString() ?? '';
    print('  ${e.kind.name} ${extra.isNotEmpty ? "— $extra" : ""}');
  }

  // ── TokenUsage.fromApi ──
  // 从 DeepSeek/OpenAI API 响应的 usage 字段直接解析
  // API 返回示例：
  //   {"prompt_tokens":150, "completion_tokens":80, "total_tokens":230,
  //    "prompt_cache_hit_tokens":100, "prompt_cache_miss_tokens":50}
  print('\n— TokenUsage.fromApi —');
  final usage = TokenUsage.fromApi({
    'prompt_tokens': 150,
    'completion_tokens': 80,
    'total_tokens': 230,
    'prompt_cache_hit_tokens': 100,
    'prompt_cache_miss_tokens': 50,
    'cache_hit_ratio': 0.67,
  });
  // toString 输出示例："230tok (↑150 ↓80) cache:67%"
  print('  $usage');

  // ── StreamEventSink — EventSink + Stream 的桥接 ──
  // 用法：Agent 内部调用 sink.emit(event)，UI 通过 sink.stream.listen() 消费
  print('\n— StreamEventSink —');
  final sink = StreamEventSink(); // 内部创建 StreamController.broadcast()
  // 订阅 stream，收到事件时打印
  sink.stream.listen((e) => print('  stream 收到: ${e.kind.name}'));
  // emit 等价于 EventSink.emit()，实际调用 StreamController.add()
  sink.emit(AgentEvent.text('hello via stream'));
  // 用完后关闭（释放 StreamController 资源）
  sink.close();
}

// ═══════ 11. OutputStyle + StyleManager ═══════

/// # 11. OutputStyle — 控制模型的说话风格
///
/// 学习目标：理解 OutputStyle 的作用和 StyleManager 的用法。
///
/// 核心概念：
/// - OutputStyle 通过修改 system prompt 来控制模型输出风格
/// - `keepCoding=true`：风格文本追加到原有 system prompt 后面（保留编程指令）
/// - `keepCoding=false`：风格文本完全替换 system prompt
/// - 4 种内置风格：explanatory（解释型）、learning（学习型）、concise（简洁型）、socratic（苏格拉底式）
void _demoOutputStyle() {
  _section('11. OutputStyle / StyleManager');

  // ── 4 种内置风格 ──
  print('— BuiltinStyles —');
  for (final s in BuiltinStyles.all) {
    // 每个风格有 name（标识符）和 description（一行描述）
    print('  ${s.name}: ${s.description}');
  }

  // ── StyleManager 用法 ──
  final mgr = StyleManager();

  // setByName：按名称设置风格（不区分大小写）
  // 内部先查 BuiltinStyles.byName，找不到返回 false
  print('\nsetByName("concise") → ${mgr.setByName("concise")}');
  print('current!.name: ${mgr.current!.name}'); // 当前已生效的风格

  // applyTo：将风格 body 注入到 base prompt 中
  // concise.keepCoding=true，所以风格文本追加到末尾而非替换
  final basePrompt = '你是一个代码助手。写 Python。';
  final combined = mgr.applyTo(basePrompt);
  print('applyTo(base) → ${combined.length} chars（原 ${basePrompt.length} + style body）');

  // 设置不存在的风格 → 返回 false，current 不变
  print('setByName("nonexist") → ${mgr.setByName("nonexist")}');
  // clear：移除风格，恢复默认 system prompt
  mgr.clear();
  print('clear() → current: ${mgr.current}'); // null = 无风格
}

// ═══════ 12. Gate + PermissionRule（代码片段） ═══════

/// # 12. Gate — 工具权限控制
///
/// 学习目标：理解权限模型（PermissionLevel）和 InteractiveGate 的用法。
///
/// 核心概念：
/// - Gate 在工具执行前拦截，根据 PermissionRule 决定允许/确认/批准/拒绝
/// - InteractiveGate 带交互式回调：遇到需要批准的操作时调用 pendingCallback
/// - NoOpGate 允许一切，用于测试或无 UI 场景
/// - 匹配规则：精确匹配 > 前缀通配符（"save*"） > 全局通配符（"*"）
///
/// ⚠️ 本 section 以代码片段展示，因为 gate.dart 依赖 provider.dart → dio，
/// 在独立 `dart run` 环境下无法直接 import。
void _demoGate() {
  _section('12. Gate / PermissionRule（代码片段）');

  print('Gate 和 InteractiveGate 定义在 agent/gate.dart。');
  print('因 gate.dart 依赖链需要 dio（stub 不可用），以代码片段展示：\n');

  // ── PermissionLevel 四级 ──
  // always：总是允许（只读工具如 search）
  // confirm：需要用户确认（弹确认框）
  // approve：需要明确批准（高危操作如写文件、执行命令）
  // deny：总是拒绝（如禁用 rm -rf）
  print('PermissionLevel: always | confirm | approve | deny');
  print('');

  // ── InteractiveGate 构造 ──
  print('// 构造 InteractiveGate（带交互式批准）');
  print('final gate = InteractiveGate(');
  print('  rules: [');
  print('    // 只读工具总是允许');
  print('    PermissionRule("echo", PermissionLevel.always),');
  print('    // save 开头的工具需要明确批准');
  print('    PermissionRule("save*", PermissionLevel.approve, reason: "文件写入需批准"),');
  print('    // 其余所有工具默认需确认');
  print('    PermissionRule("*", PermissionLevel.confirm),');
  print('  ],');
  print('  // 批准回调：返回 true=批准，false=拒绝');
  print('  pendingCallback: (toolCall) async => true,');
  print(');');
  print('');

  // ── NoOpGate ──
  print('// NoOpGate：所有工具调用都允许（测试/无 UI 场景）');
  print('final gate = NoOpGate();');

  // ── 匹配规则 ──
  print('\n// 匹配规则优先级：精确匹配 > 前缀通配符（save*）> 全局通配符（*）');
  print('// 例如工具 "save_file"：先试精确匹配 → 再试 "save*" → 最后 "*"');
}

// ═══════ 13. Flutter-Only API 参考 ═══════

/// # 13. Flutter-Only API 参考 — 在真实 App 中怎么用
///
/// 学习目标：了解需要 Flutter/Riverpod 环境的 API（AgentRuntime、ChatMessage、SessionStoreInterface）。
///
/// 这些 API 无法在独立 dart 脚本中运行（需要 Flutter 的 Provider 容器），
/// 以代码片段形式展示典型用法供平台开发者参考。
void _demoFlutterOnlyApis() {
  _section('13. Flutter-Only API 参考（代码片段）');

  print('以下 API 依赖 Flutter/Riverpod，无法在独立 dart 脚本中运行：\n');

  // ── AgentRuntime ──
  // 定义在 agent_runtime.dart，是整个 Agent 系统的入口
  print('— AgentRuntime（agent_runtime.dart）—');
  print('  // 通过 Riverpod Provider 获取全局唯一实例');
  print('  final runtime = ref.watch(agentRuntimeProvider);');
  print('  runtime.controller.send("你好"); // 发送用户输入');
  print('  runtime.events.listen((e) { ... }); // 订阅事件流');

  // ── ChatMessage ──
  // 定义在 session_manager.dart，UI 层的消息管理
  print('\n— ChatMessage（session_manager.dart）—');
  print('  // 获取 StateNotifier 来操作聊天消息列表');
  print('  final notifier = ref.read(chatMessagesProvider.notifier);');
  print('  notifier.addUser("你好"); // 添加用户消息到 UI');
  print('  notifier.addAssistant("你好！", reasoning: "..."); // AI 回复');
  print('  notifier.updateLastAssistant("追加"); // 流式追加到最新消息');
  print('  notifier.addToolCall("search"); // 工具调用卡片');
  print('  notifier.addToolResult("search", "3条结果"); // 工具结果卡片');
  print('  notifier.clear(); // 清空');

  // ── 开关 ──
  print('\n— 开关（StateProvider）—');
  print('  webSearchEnabledProvider     StateProvider<bool>  默认 false');
  print('  deepThinkingEnabledProvider  StateProvider<bool>  默认 false');
  print('  // 用法：ref.read(webSearchEnabledProvider.notifier).state = true;');

  // ── SessionStoreInterface ──
  // 可插拔的会话持久化后端（默认内存，可 override 为文件/数据库）
  print('\n— SessionStoreInterface（可插拔持久化）—');
  print('  class MyStore implements SessionStoreInterface {');
  print('    Future<void> save(Session s) async { ... }');
  print('    Session? load(String id) { ... }');
  print('    Future<void> delete(String id) async { ... }');
  print('    List<Session> listAll() { ... }');
  print('  }');
  print('  // 在 Provider 中覆盖默认实现');
  print('  sessionStoreProvider.overrideWith((ref) => MyStore());');

  // ── Session Providers ──
  print('\n— Session Providers（CRUD 操作）—');
  print('  sessionListProvider           出: AsyncValue<List<Session>>');
  print('  createSessionProvider(title?)  入: String? / 新建并切换');
  print('  switchSessionProvider(id)      入: String / 切换（自动保存当前）');
  print('  saveCurrentSessionProvider(id) 入: String / 保存当前');
  print('  deleteSessionProvider(id)      入: String / 删除');
  print('  renameSessionProvider(id, t)   入: String, String / 重命名');
  print('  activeSessionTitleProvider     出: String / 当前标题');

  // ── Controller ──
  // UI 和 Agent 之间的桥梁
  print('\n— Controller（UI ↔ Agent 桥梁）—');
  print('  controller.send("用户输入"); // 启动 Agent 对话');
  print('  controller.cancel(); // 取消当前对话');
  print('  controller.approve(toolCallId); // 批准工具调用');
  print('  controller.reject(toolCallId, reason: "..."); // 拒绝工具调用');
  print('  controller.setSystemPrompt("自定义系统提示"); // 覆盖 system prompt');
  print('  controller.activateSkill("acceptance"); // 激活技能（注入 body 到 system prompt）');
  print('  controller.deactivateSkill("acceptance"); // 停用技能');
  print('  controller.send("分析这张图", attachments: ocrContext); // 带附件上下文');
  print('  controller.activeSkillIds; // 当前激活的技能 ID 列表');
}

// ═══════ 14. 模拟对话 ═══════

/// # 14. 模拟对话 — 把全部组件串起来
///
/// 学习目标：理解 Agent 主循环中各组件的协作关系。
///
/// 完整流程（对应 agent/agent.dart 的 Agent.run()）：
/// 1. 用户输入 → Message.user
/// 2. compose（构建系统提示词 + 消息历史 + 工具定义）
/// 3. LLM API 调用 → 返回 assistant 消息（可能包含 tool_calls）
/// 4. 如果有 tool_calls → Gate 检查权限 → Registry 执行工具 → 写入 tool result
/// 5. 回到步骤 2（带 tool result 再次调用 LLM）
/// 6. LLM 生成最终回答 → turnDone
Future<void> _demoSimulatedConversation() async {
  _section('14. 模拟对话（串联全部组件）');

  // Step 1: 初始化 Registry — 内置工具 + 插件自动发现
  final registry = Registry();
  final pluginsDir = Directory('example/plugins');
  if (pluginsDir.existsSync()) {
    // PluginBridge 扫描并注册 4 个示例插件
    PluginBridge.registerAll(registry, pluginsDir);
  }
  // 同时注册内部测试工具
  registry.register(_EchoTool());
  registry.register(_ClockTool());

  // Step 2: 创建 Session — 对话状态的容器
  final session = Session(title: '模拟对话');
  session.setSystemMessage('你是有用的助手。');

  // Step 3: 用户提问 — 对应 controller.send("帮我查...")
  session.add(Message.user('帮我查北京天气和当前时间'));
  print('用户: 帮我查北京天气和当前时间\n');

  // Step 4: 模型决定调用工具 — 对应 LLM 返回 finish_reason=tool_calls
  //   在真实场景中，LLM 会生成这些 ToolCall（包括 id/name/arguments）
  //   这里手动构造以演示流程
  //   weather 插件：args+flag 风格，需要 city（必填）和 days（可选）
  final weatherCall = ToolCall(id: 'call_w', name: 'weather', arguments: '{"city":"北京","days":1}');
  //   time 插件：args+flag 风格，offset 和 format 都是可选
  final timeCall = ToolCall(id: 'call_t', name: 'time', arguments: '{"offset":8,"format":"24h"}');
  // assistantTool 消息将 tool_calls 写入对话历史
  session.add(Message.assistantTool([weatherCall, timeCall]));
  print('模型 → tool_calls: [weather, time]');

  // Step 5: 执行工具 — 对应 Agent 主循环中的 tool execution 阶段
  //   真实流程：Gate.checkPermission → ToolHooks.preUse → registry.call → ToolHooks.postUse
  for (final tc in [weatherCall, timeCall]) {
    String result;
    if (registry.has(tc.name)) {
      // registry.call：接收模型生成的原始 JSON → jsonDecode → tool.execute(args) → 返回结果
      // PluginTool.execute 内部会启动 .exe 进程，传入参数，收集 stdout
      result = await registry.call(tc.name, tc.arguments);
    } else {
      // fallback：工具未注册时用 ClockTool 代替（防止 demo 中断）
      result = await _ClockTool().execute({});
    }
    // toolResult：将工具执行结果写入对话历史，toolCallId 必须匹配
    session.add(Message.toolResult(tc.id, result, name: tc.name));
    // 截断过长输出
    final preview = result.length > 100 ? '${result.substring(0, 100)}...' : result.trimRight();
    print('  ${tc.name} 结果 → $preview');
  }

  // Step 6: 模型根据工具结果生成最终回答
  //   在真实场景中，工具结果会作为 tool 消息追加到历史，
  //   然后再次调用 LLM（带更新后的 messages），LLM 综合工具结果生成回答
  session.add(Message.assistant('北京今天晴，25°C。当前时间 14:30:00。'));
  print('\n模型最终回答: 北京今天晴，25°C。当前时间 14:30:00。');

  // Step 7: 展示完整消息历史 — 所有消息按时间顺序排列
  print('\n— 消息历史 —');
  for (final m in session.messages) {
    final label = m.isToolResult
        ? 'tool(${m.name}): ${m.content.length} chars' // 工具结果：显示名称和长度
        : m.hasToolCalls
          ? 'assistant: tool_calls=[${m.toolCalls.map((t) => t.name).join(", ")}]' // 工具调用
          : '${m.role.value}: ${m.content.length > 60 ? "${m.content.substring(0, 60)}..." : m.content}';
    print('  [$label]');
  }

  // Session 统计
  print('\n总消息: ${session.messageCount}  |  估算上下文: ${session.estimatedContextTokens} tokens');
  // 这个估算值可用于判断是否需要触发上下文压实（compact）
}

// ═══════ 15. 在线 DeepSeek API 演示 ═══════

/// # 15. 在线 DeepSeek API 演示 — 3 轮对话（含插件工具调用）
///
/// 学习目标：用本模块提供的函数（`Message`、`Registry`、`PluginBridge`、
/// `toolToSchema`）快速构建一个多轮 AI 智能体，理解 Agent 主循环的核心逻辑。
///
/// ## 为什么这一节是重点
///
/// 前面 14 个 Section 演示了各个"零件"的用法，但零件怎么拼成一辆能开的车？
/// 这一节把 `Message`（消息）→ `_callDeepSeek`（LLM 调用）→ `Registry`（工具执行）
/// 串成一个完整的多轮对话循环。理解了这里，你就理解了 Agent 的核心。
///
/// ## 多轮对话的核心数据结构：`List<Message> messages`
///
/// 整个对话过程中，**只有一个 `messages` 列表**，它贯穿全部 3 轮：
/// ```
/// messages = [
///   Message.system,       // 第 0 条：系统提示（定义 AI 行为边界）
///   // —— 第 1 轮 ——
///   Message.user,         // 用户说"你好"
///   Message.assistant,    // AI 回复
///   // —— 第 2 轮 ——
///   Message.user,         // 用户说"查天气"
///   Message.assistantTool,// AI 决定调 weather + time 工具
///   Message.toolResult,   // weather 执行结果
///   Message.toolResult,   // time 执行结果
///   Message.assistant,    // AI 综合工具结果后回答
///   // —— 第 3 轮 ——
///   Message.user,         // 用户追问
///   Message.assistant,    // AI 结合全部历史回答
/// ]
/// ```
/// 关键认知：**每一轮对话都是在之前的 messages 上追加，LLM 能看到全部历史**。
///
/// ## 三轮对话设计
/// | 轮次 | 用户输入 | 预期的 LLM 行为 | 教学点 |
/// |------|---------|----------------|--------|
/// | 第 1 轮 | "你好！请用一句话介绍你自己。" | 纯文本回答 | 最简流程：user → LLM → assistant |
/// | 第 2 轮 | "帮我查北京天气和当前时间。" | 返回 tool_calls → 执行插件 → 回传结果 → 综合回答 | ★ 工具调用完整流程 |
/// | 第 3 轮 | "谢谢！你觉得今天适合出门吗？" | 结合前 2 轮上下文，可能再调工具 | 上下文记忆 + 多轮连贯性 |
///
/// ## 工具调用流程（第 2 轮的核心）
/// ```
/// 1. user 消息 "查天气" → 追加到 messages
/// 2. _callDeepSeek(messages, tools: [weather, time]) → LLM 看到用户问天气，
///    决定调用 weather 和 time 工具，返回 tool_calls=[weather, time]
/// 3. messages.add(Message.assistantTool(toolCalls))  ← 重要！记录 AI 的调用意图
/// 4. registry.call("weather", args) → 启动 weather.exe → 获取天气数据
/// 5. messages.add(Message.toolResult(callId, 结果))  ← 把结果告诉 LLM
/// 6. 重复 4-5 执行 time 工具
/// 7. _callDeepSeek(messages, tools: [])  ← 注意！tools 传空，防止 LLM 再次调工具
///    LLM 看到 tool results，综合生成最终回答
/// 8. messages.add(Message.assistant(最终回答))
/// ```
Future<void> _demoLiveApi(String apiKey) async {
  _section('15. 在线 DeepSeek API 演示（3 轮对话）');

  // ═══════════════════════════════════════════════════════════════════
  // 初始化阶段：准备工具和 messages 列表
  // ═══════════════════════════════════════════════════════════════════

  // ── Step A：通过 PluginBridge 发现并注册插件工具 ──
  // 这是"给 Agent 配备工具"的关键步骤：
  //   1. PluginBridge.discover 扫描 example/plugins/ 目录
  //   2. 找到 4 个 .exe（weather/time/date/random） → 包装为 PluginTool
  //   3. 注册到 Registry（后续 LLM 想调工具时，从 Registry 查找并执行）
  final registry = Registry();
  final pluginsDir = Directory('example/plugins');
  // toolSchemas 是将要传给 LLM 的工具定义列表
  // 格式：[{type:"function", function:{name:"weather", description:"...", parameters:{...}}}, ...]
  // 这个格式由 toolToSchema() 生成，兼容 OpenAI/DeepSeek API
  final toolSchemas = <Map<String, dynamic>>[];

  if (pluginsDir.existsSync()) {
    // registerAll：批量注册所有发现的插件
    PluginBridge.registerAll(registry, pluginsDir);
    // 将每个插件工具转为 LLM 能理解的 function schema
    // toolToSchema(Tool) → {type:"function", function:{name, description, parameters}}
    for (final t in registry.enabled()) {
      toolSchemas.add(toolToSchema(t));
    }
  }

  // 备选方案：如果插件目录不存在（比如在其他平台），至少有一个 clock 工具可用
  registry.register(_ClockTool());
  if (toolSchemas.isEmpty) {
    toolSchemas.add(toolToSchema(_ClockTool()));
  }

  print('可用工具: ${registry.enabled().map((t) => t.name).join(", ")}');
  print('模型: deepseek-v4-flash  |  stream: true');

  // ═══════════════════════════════════════════════════════════════════
  // 核心数据结构：messages —— 贯穿全部轮次的对话历史
  // ═══════════════════════════════════════════════════════════════════
  // 这是多轮 Agent 最重要的概念：
  //   - 每一轮对话都往这个列表追加消息
  //   - 每次调用 LLM 时，把整个列表发过去（LLM 需要看到完整上下文）
  //   - system 消息放在最前面，定义 AI 的角色和行为
  //   - 工具调用时，assistantTool 和 toolResult 也按顺序插入
  //
  // 关于 system prompt：
  //   平台提供了默认的 defaultSystemPrompt（定义在 agent/compose.dart），
  //   包含了 Greenix Agent 的完整行为规范。真实 App 中通过
  //   controller.setSystemPrompt() 可以自定义替换。
  //   这里为了 demo 简洁，用一个简化的 system prompt 代替。
  final messages = <Message>[
    Message.system(
      '你是一个有用的助手。回答问题时请使用中文，保持简洁。'
      // 这一句很关键：告诉 LLM 什么情况下应该调用工具
      '当用户问天气或时间时，请调用对应的工具获取实时数据。',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════
  // 第 1 轮：纯文本对话（最简单的流程）
  // ═══════════════════════════════════════════════════════════════════
  // 流程：user 消息 → LLM → assistant 消息
  // 这是最基础的模式，不需要工具参与
  print('\n——— 第 1 轮：纯文本对话 ———\n');
  // Step 1：追加用户消息
  messages.add(Message.user('你好！请用一句话介绍你自己。'));
  print('👤 用户: ${messages.last.content}');

  // Step 2：调用 LLM
  // 虽然传了 tools，但这个问题不需要工具，LLM 会直接返回文本
  // _callDeepSeek 是我们自己封装的函数（定义在本节末尾），
  // 它处理了 HTTP 请求、SSE 流式解析、tool_calls delta 合并等底层细节
  final r1 = await _callDeepSeek(apiKey, messages, tools: toolSchemas);
  if (r1 == null) return; // API 致命错误（401/429/网络不通），终止后续轮次

  // Step 3：将 LLM 的回答追加到历史
  // 这样第 2 轮时 LLM 就知道第 1 轮说了什么——这就是"多轮记忆"的机制
  messages.add(Message.assistant(r1.content, reasoning: r1.reasoning));
  print(''); // 换行，分隔轮次输出

  // ═══════════════════════════════════════════════════════════════════
  // 第 2 轮：工具调用（最核心的流程）★
  // ═══════════════════════════════════════════════════════════════════
  // 流程：user → LLM（返回 tool_calls）→ 执行工具 → tool results →
  //       LLM（综合结果生成回答）
  //
  // 这是 Agent 区别于普通 Chatbot 的关键能力：
  //   - LLM 不只是生成文本，还能"决定"调用外部工具
  //   - 工具执行结果再喂回给 LLM，形成"思考→行动→观察→思考"的循环
  print('\n——— 第 2 轮：工具调用 ★ ———\n');

  // Step 1：用户追加新消息（注意：前一轮的对话已经在 messages 里了）
  messages.add(Message.user('帮我查一下北京现在的天气和当前时间。'));
  print('👤 用户: ${messages.last.content}\n');

  // Step 2：调用 LLM，传 tools 参数让 LLM 知道有哪些工具可用
  // LLM 看到用户问天气和时间，system prompt 里又说了"调工具获取实时数据"，
  // 所以它应该返回 finish_reason="tool_calls" 而不是纯文本
  final r2 = await _callDeepSeek(apiKey, messages, tools: toolSchemas);
  if (r2 == null) return;

  // Step 3：判断 LLM 是否决定调用工具
  //   - toolCalls 不为空 → LLM 想调工具，我们需要执行并回传结果
  //   - toolCalls 为空 → LLM 直接回答了（比如它觉得不需要工具）
  if (r2.toolCalls.isNotEmpty) {
    // ── 3a：记录 LLM 的工具调用意图 ──
    // 这行很重要！Message.assistantTool 告诉 LLM：
    //   "我在这一轮决定调用这些工具，结果稍后给你"
    // toolCalls 中每个 ToolCall 包含：
    //   - id：调用唯一标识（用于把 tool result 关联回来）
    //   - name：工具名（如 "weather"、"time"）
    //   - arguments：模型生成的 JSON 参数字符串（如 {"city":"北京","days":1}）
    messages.add(Message.assistantTool(r2.toolCalls));
    print('\n🔧 LLM 决定调用 ${r2.toolCalls.length} 个工具:');
    for (final tc in r2.toolCalls) {
      print('    ${tc.name}(${tc.arguments})');
    }

    // ── 3b：逐个执行工具 ──
    // registry.call(name, argumentsJson) 做了三件事：
    //   1. jsonDecode(arguments) — 把 LLM 生成的 JSON 字符串解析为 Map
    //   2. 查找工具 — 按 name 在 Registry 中找对应的 Tool 对象
    //   3. tool.execute(args) — 真正执行（对于插件工具 = 启动 .exe 进程）
    print('\n⚙️  执行工具:');
    for (final tc in r2.toolCalls) {
      final result = registry.has(tc.name)
          ? await registry.call(tc.name, tc.arguments)
          : '[error: tool "${tc.name}" not found]';
      // ── 3c：将工具结果追加到消息历史 ──
      // toolCallId 必须与对应的 ToolCall.id 匹配！
      // LLM 通过这个 id 知道"这个结果是哪个工具调用产生的"
      messages.add(Message.toolResult(tc.id, result, name: tc.name));
      final preview = result.length > 120 ? '${result.substring(0, 120)}...' : result.trimRight();
      print('    ${tc.name} → $preview');
    }

    // ── 3d：将 tool results 回传给 LLM，让它生成综合回答 ──
    // 注意这里 tools: [] —— 传空！
    // 为什么？因为如果继续传 tools，LLM 可能再次返回 tool_calls，
    // 形成无限循环。真实 Agent 中由 maxSteps 控制最大循环次数。
    print('\n🤖 LLM 综合工具结果后回答: ');
    final r2b = await _callDeepSeek(apiKey, messages, tools: []);
    if (r2b == null) return;
    // LLM 现在看到了完整的上下文：
    //   user:"查天气" → assistantTool:[weather,time] → toolResult:"北京晴…" → toolResult:"14:30"
    // 它能综合这些信息生成自然语言回答
    messages.add(Message.assistant(r2b.content, reasoning: r2b.reasoning));
    print('');
  } else {
    // LLM 没有调工具，直接记录了回答（兜底逻辑）
    print('🤖 LLM 直接回答（未调用工具）:');
    messages.add(Message.assistant(r2.content, reasoning: r2.reasoning));
    print('');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 第 3 轮：上下文追问（验证 LLM 记住了前两轮的信息）
  // ═══════════════════════════════════════════════════════════════════
  // 这一轮的关键：用户没有明确说"北京"，但 LLM 应该从第 2 轮的上下文中
  // 理解到用户问的是"今天在北京是否适合出门"
  print('\n——— 第 3 轮：上下文追问 ———\n');
  messages.add(Message.user('谢谢！那你觉得我今天适合出门吗？'));
  print('👤 用户: ${messages.last.content}\n');

  // 再次调用 LLM，带工具定义（LLM 可能再次调天气工具来确认当前状况）
  final r3 = await _callDeepSeek(apiKey, messages, tools: toolSchemas);
  if (r3 == null) return;

  if (r3.toolCalls.isNotEmpty) {
    // 如果 LLM 再次调用工具（比如想确认最新的天气数据），
    // 流程和第 2 轮完全一样：记录调用 → 执行 → 回传结果 → 再调用 LLM
    messages.add(Message.assistantTool(r3.toolCalls));
    print('\n🔧 LLM 再次调用工具: ${r3.toolCalls.map((t) => t.name).join(", ")}');
    for (final tc in r3.toolCalls) {
      final result = registry.has(tc.name)
          ? await registry.call(tc.name, tc.arguments)
          : '[error]';
      messages.add(Message.toolResult(tc.id, result, name: tc.name));
    }
    print('🤖 最终回答: ');
    final r3b = await _callDeepSeek(apiKey, messages, tools: []);
    if (r3b == null) return;
    messages.add(Message.assistant(r3b.content, reasoning: r3b.reasoning));
  } else {
    // LLM 觉得不需要再调工具，直接基于上下文回答
    messages.add(Message.assistant(r3.content, reasoning: r3.reasoning));
  }
  print('');

  // ═══════════════════════════════════════════════════════════════════
  // 对话历史回顾：展示 3 轮对话后 messages 的完整面貌
  // ═══════════════════════════════════════════════════════════════════
  // 通过这个列表，你可以看到多轮 Agent 的"记忆"长什么样：
  // system → user → assistant → user → assistantTool → toolResult*N → assistant → user → assistant
  print('——— 3 轮对话完成 ———');
  print('总消息数: ${messages.length}');
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final label = m.isToolResult
        ? '  tool(${m.name})' // 工具结果消息
        : m.hasToolCalls
          ? '  assistant tool_calls=[${m.toolCalls.map((t) => t.name).join(", ")}]' // AI 请求调工具
          : '  ${m.role.value}'; // system / user / assistant
    final preview = m.content.length > 80 ? '${m.content.substring(0, 80)}...' : m.content;
    print('[$i] $label${preview.isNotEmpty ? ": $preview" : ""}');
  }
  // 理解了 messages 的演变过程，就理解了 Agent 的核心运作机制
}

// ═══════ DeepSeek API 调用辅助函数 ═══════
// 以下是 Section 15 专用的底层 API 调用封装。
// 在实际项目中，这部分由 provider.dart 的 DeepSeekProvider 完成。
// 这里直接用 dart:io HttpClient 实现，是为了在无 Dio 的独立 dart 环境中也能运行。

/// 一次 DeepSeek API 调用的完整结果。
///
/// 封装了 4 种可能的返回值：
/// - content：LLM 生成的文本（必有的）
/// - reasoning：DeepSeek 的思考过程（v4 模型支持，可能为空）
/// - toolCalls：LLM 决定调用的工具列表（可能为空）
/// - usage：本次调用的 token 消耗（可能为 null，如果 API 未返回）
///
/// 调用方通过检查 toolCalls 是否为空来判断 LLM 是否想调工具。
class _DeepSeekResult {
  final String content;
  final String reasoning;
  final List<ToolCall> toolCalls;
  final TokenUsage? usage;

  const _DeepSeekResult({
    required this.content,
    this.reasoning = '',
    this.toolCalls = const [],
    this.usage,
  });
}

/// 调用 DeepSeek Chat Completions API（SSE 流式），返回完整结果。
///
/// 这是 Section 15 最底层的函数，所有 3 轮对话都通过它来调用 LLM。
/// 封装了 HTTP 请求、SSE 流式解析、tool_calls delta 合并、错误处理。
///
/// ## 参数说明
/// - [apiKey]：DeepSeek API Key（Bearer 认证用）
/// - [messages]：**完整的对话历史**（含 system prompt + 之前所有轮次的消息）
///   每次调用都会把整个列表发给 LLM，这是"多轮对话"的基础
/// - [tools]：可用的工具 schema 列表。
///   传空 `[]` 时 LLM 只能生成文本；
///   传入工具定义时 LLM 可以自主决定是否调用工具（tool_choice="auto"）
///
/// ## 返回值
/// 返回 [_DeepSeekResult] 包含 content/reasoning/toolCalls/usage。
/// 返回 null 表示 API 致命错误（401/429/网络不通），调用方应终止后续轮次。
///
/// ## 实现要点
///
/// ### 1. SSE（Server-Sent Events）协议
/// DeepSeek API 的 stream 模式使用 SSE，HTTP body 每行：
/// ```
/// data: {"choices":[{"delta":{"content":"你"},"index":0}]}
/// data: {"choices":[{"delta":{"content":"好"},"index":0}]}
/// ...
/// data: [DONE]
/// ```
/// 每行是**增量**文本（delta），需累加才能得到完整回答——这就是 `contentBuf.write()` 做的事。
///
/// ### 2. tool_calls 的 delta 合并机制（本节最复杂的部分）
/// LLM 决定调工具时，tool_calls 可能分**多次** SSE chunk 到达：
/// ```
/// chunk 1: {"delta":{"tool_calls":[{"index":0,"id":"call_xxx","function":{"name":"weather"}}]}}
/// chunk 2: {"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":"}}]}}
/// chunk 3: {"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"北京\"}"}}]}}
/// ```
/// 同一个工具调用（index=0）的 id/name/arguments 分布在多个 chunk 中。
/// 解决方案：用三个 Map 按 index 分组累积——
/// ```
/// tcIdForIndex[0] = "call_abc123"
/// tcNameForIndex[0] = "weather"
/// tcArgsForIndex[0] = StringBuffer("{\"city\":\"北京\"}")  // ← StringBuffer 拼多个片段
/// ```
/// SSE 流结束后，再把这些 Map 合并为完整的 ToolCall 列表。
///
/// ### 3. UTF-8 跨 chunk 缓冲（partialLine）
/// TCP 按字节流分割，一个 UTF-8 多字节字符（如"你"=3 字节）可能被切在两段之间。
/// `partialLine` 保存每段最后一行不完整的部分，与下一段拼接后再 split('\n')。
///
/// ### 4. 请求头说明
/// - `Content-Type: application/json` → "我发的是 JSON"
/// - `Accept: text/event-stream` → "请用 SSE 格式回复"
/// - `Authorization: Bearer <key>` → API Key 认证
Future<_DeepSeekResult?> _callDeepSeek(
  String apiKey,
  List<Message> messages, {
  List<Map<String, dynamic>> tools = const [],
}) async {
  // ── 1. 构建 API 请求体 ──
  // model: deepseek-v4-flash（快速便宜）/ deepseek-v4-pro（更强更贵）
  // messages: 完整对话历史，每条 Message.toJson() 转为 {role, content} 格式
  // stream: true → SSE 流式；false → 等全部生成完一次性返回
  // tools: 可用工具定义（OpenAI function schema 格式，由 toolToSchema() 生成）
  // tool_choice: "auto" → LLM 自主决定；"none" → 禁止调工具；"required" → 强制调工具
  final bodyMap = <String, dynamic>{
    'model': 'deepseek-v4-flash',
    'messages': messages.map((m) => m.toJson()).toList(),
    'stream': true,
    'max_tokens': 1024,
  };
  if (tools.isNotEmpty) {
    bodyMap['tools'] = tools;
    bodyMap['tool_choice'] = 'auto'; // 让 LLM 自己判断：这个问题需要调工具吗？
  }
  final body = jsonEncode(bodyMap);

  // ── 2. 使用 dart:io HttpClient 发送 POST ──
  // 不依赖 package:dio（stub 不可用），纯 dart:io 实现
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('https://api.deepseek.com/chat/completions'),
    );
    request.headers.set('Authorization', 'Bearer $apiKey');
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'text/event-stream');
    // add(utf8.encode(...)) 而非 write()：write() 默认 Latin-1 不支持中文
    request.add(utf8.encode(body));
    // close() 发送请求并返回响应流
    final response = await request.close();

    // ── 3. HTTP 状态码检查 ──
    final statusCode = response.statusCode;
    if (statusCode == 401) {
      print('❌ API Key 无效（401）— 请检查 key 是否正确');
      return null;
    }
    if (statusCode == 429) {
      print('❌ 频率限制（429），请稍后重试');
      return null;
    }
    if (statusCode != 200) {
      print('❌ HTTP $statusCode: ${response.reasonPhrase}');
      return null;
    }

    // ── 4. SSE 流式解析 ──
    // 这些变量在整个 SSE 流处理过程中持续累积
    final contentBuf = StringBuffer(); // 累积 LLM 回答文本（所有 delta 拼接）
    final reasoningBuf = StringBuffer(); // 累积思考过程（DeepSeek reasoning_content）
    TokenUsage? usage; // token 统计（通常在最后一条 chunk 返回）
    var partialLine = ''; // 跨 TCP chunk 的行缓冲（处理 UTF-8 字符被截断）

    // tool_calls delta 合并的数据结构（详见 _callDeepSeek 文档注释第 2 点）
    // 为什么用 Map<int, ...>？
    //   因为 LLM 可能同时调用多个工具（如 weather+time），每个工具有不同的 index
    // 为什么 arguments 用 StringBuffer？
    //   因为 arguments 是 JSON 字符串，可能被 TCP 切成多段到达
    final tcIdForIndex = <int, String>{}; // index → 调用 ID
    final tcNameForIndex = <int, String>{}; // index → 工具名
    final tcArgsForIndex = <int, StringBuffer>{}; // index → JSON 参数字符串（拼接过）
    bool toolCallsSeen = false; // 标记：是否在 SSE 流中看到过 tool_calls

    stdout.write('🤖 ');
    // response 是 HttpClientResponse，实现 Stream<List<int>>
    // .transform(utf8.decoder) 将字节流 → 字符串流
    await for (final chunk in response.transform(utf8.decoder)) {
      // ── 4a. TCP chunk 缓冲处理 ──
      // 将新到达的字节追加到缓冲，然后按 '\n' 分割
      partialLine += chunk;
      final lines = partialLine.split('\n');
      // removeLast() 取出最后一段不完整的行，保留到下一次循环
      // 例如："北京" 的 "北" 在 chunk A，"京" 在 chunk B → chunk A 结束时
      // partialLine="北"，等 chunk B 到达后拼接成 "北京" 再处理
      partialLine = lines.removeLast();

      for (final line in lines) {
        // SSE 行格式："data: <json>" 或 "data: [DONE]"
        if (!line.startsWith('data: ')) continue;
        // 去掉 "data: " 前缀（6 个字符）
        final data = line.substring(6).trim();
        if (data == '[DONE]') break; // SSE 流结束标记

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          // delta：增量对象，包含本轮新增的内容
          final delta = choices[0]['delta'] as Map<String, dynamic>? ?? {};

          // ── 4b. 文本 delta：逐 token 到达 ──
          // 例如 "你" → "好" → "！" → "我" → "是" → ...
          // 前端逐字追加渲染，形成"打字机"效果
          if (delta['content'] != null) {
            final t = delta['content'] as String;
            contentBuf.write(t); // 累加到完整文本（最终返回用）
            stdout.write(t); // 实时输出到终端（模拟流式 UI）
          }

          // ── 4c. 思考过程 delta（DeepSeek reasoning_content） ──
          // 在 content 之前到达，v4 模型支持
          if (delta['reasoning_content'] != null) {
            reasoningBuf.write(delta['reasoning_content'] as String);
          }

          // ── 4d. tool_calls delta：按 index 合并 ──
          // 核心难点：同一个工具调用的字段可能分布在多个 chunk 中
          if (delta['tool_calls'] != null) {
            toolCallsSeen = true;
            for (final tc in (delta['tool_calls'] as List)) {
              final idx = tc['index'] as int? ?? 0; // 工具在列表中的位置（0, 1, 2...）
              final func = tc['function'] as Map<String, dynamic>? ?? {};

              // id：工具调用的唯一标识（通常只在首次出现时携带）
              if (tc['id'] != null && (tc['id'] as String).isNotEmpty) {
                tcIdForIndex[idx] = tc['id'] as String;
              }
              // name：工具名（通常只在首次出现时携带）
              if (func['name'] != null && (func['name'] as String).isNotEmpty) {
                tcNameForIndex[idx] = func['name'] as String;
              }
              // arguments：JSON 参数字符串（最可能分多段！）
              if (func['arguments'] != null) {
                // putIfAbsent：第一次遇到这个 index 时创建 StringBuffer
                tcArgsForIndex.putIfAbsent(idx, () => StringBuffer());
                // write：追加（不覆盖）到已有内容
                tcArgsForIndex[idx]!.write(func['arguments'] as String);
              }
            }
          }

          // ── 4e. Token 用量 ──
          if (json['usage'] != null) {
            usage = TokenUsage.fromApi(json['usage'] as Map<String, dynamic>);
          }
        } catch (_) {
          // 单条 JSON 解析失败不影响整体 —— 跳过继续处理下一条
        }
      }
    }

    stdout.write('\n');

    // ── 5. 合并 tool_calls ──
    // SSE 流结束后，把按 index 分散存储的字段合并为完整的 ToolCall 列表
    final toolCalls = <ToolCall>[];
    if (toolCallsSeen) {
      // 遍历所有出现过的 index
      for (final idx in tcNameForIndex.keys) {
        toolCalls.add(ToolCall(
          // 如果 id 缺失（极端边界情况），生成一个 fallback id
          id: tcIdForIndex[idx] ?? 'call_${DateTime.now().millisecondsSinceEpoch}_$idx',
          name: tcNameForIndex[idx] ?? '',
          arguments: tcArgsForIndex[idx]?.toString() ?? '{}',
        ));
      }
      // 按 index 排序，保持 LLM 预期的调用顺序
      toolCalls.sort((a, b) {
        final ai = int.tryParse(a.id.split('_').last) ?? 0;
        final bi = int.tryParse(b.id.split('_').last) ?? 0;
        return ai.compareTo(bi);
      });
    }

    // ── 6. 返回完整结果 ──
    return _DeepSeekResult(
      content: contentBuf.toString(),
      reasoning: reasoningBuf.toString(),
      toolCalls: toolCalls,
      usage: usage,
    );
  } on SocketException catch (e) {
    // DNS 解析失败 / 连接超时 / 断网
    print('❌ 网络错误: $e');
    return null;
  } on HttpException catch (e) {
    // HTTP 协议层异常
    print('❌ HTTP 错误: $e');
    return null;
  } catch (e) {
    // 兜底异常
    print('❌ 未知错误: $e');
    return null;
  } finally {
    client.close(); // 释放 socket 资源
  }
}

// ═══════ 内部工具类 ═══════
// 以下为各个 Demo 使用的私有工具实现。
// 在真实项目中，这些应该放在单独的文件中并通过 Registry 注册。
// 放在 example 文件末尾是为了让读者能一眼看到 Demo 使用的所有工具。

/// 回声工具：返回传入的消息。演示 Tool 抽象类的基本实现模式。
///
/// 实现步骤（照着写一个新工具的模板）：
/// 1. `extends Tool` — 继承抽象类
/// 2. override `name` — 蛇形命名的唯一标识符
/// 3. override `description` — 给模型看的说明文字
/// 4. override `schema` — JSON Schema 参数定义（每个属性必须有 description）
/// 5. override `execute` — 真正执行的逻辑，接收 args Map，返回结果 String
class _EchoTool extends Tool {
  @override String get name => 'echo';
  @override String get description => '回声工具：返回你传入的消息。';
  @override Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'message': {'type': 'string', 'description': '要回声的消息'},
    },
    'required': ['message'],
  };
  @override Future<String> execute(Map<String, dynamic> args) async =>
    'echo: ${args['message']}';
}

/// 时钟工具：返回当前 ISO 8601 时间戳。
///
/// 最简单的 Tool 实现——无参数，无外部依赖。
/// schema 为空对象（无 properties），execute 直接返回 DateTime.now()。
class _ClockTool extends Tool {
  @override String get name => 'clock';
  @override String get description => '返回当前时间。';
  // 空 schema：不需要任何参数
  @override Map<String, dynamic> get schema => {'type': 'object', 'properties': {}};
  @override Future<String> execute(Map<String, dynamic> args) async =>
    DateTime.now().toIso8601String();
}

/// 写文件工具：演示 readOnly=false（写操作需串行执行）。
///
/// readOnly 的意义：
/// - true（默认）：只读工具，Agent 可在同一轮并行调用多个只读工具
/// - false：写操作，Agent 必须串行——等前一个写工具完成才能调用下一个
/// Registry.readOnlyToolNames 用于生成并行调度策略
class _WriteTool extends Tool {
  @override String get name => 'save_file';
  @override String get description => '写文件。';
  @override Map<String, dynamic> get schema => {'type': 'object', 'properties': {}};
  @override bool get readOnly => false; // ⚠️ 标记为写操作
  @override Future<String> execute(Map<String, dynamic> args) async => 'saved';
}

/// 写文件工具（带预览）：演示 `Previewer` mixin 的用法。
///
/// Previewer 的作用：
/// - 在实际执行前生成文件变更预览（ToolChange）
/// - 前端用 ToolChange 展示"批准卡片"：这个操作会改什么文件？
/// - 返回 null 表示无预览（跳过批准步骤，直接执行）
///
/// 适用场景：写文件、删除文件、执行命令等有副作用的操作。
class _PreviewWriteTool extends Tool with Previewer {
  @override String get name => 'write_file';
  @override String get description => '写文件，带预览。';
  @override Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
      'content': {'type': 'string'},
    },
  };
  @override bool get readOnly => false;
  @override Future<String> execute(Map<String, dynamic> args) async => 'saved';
  /// 生成文件变更预览。
  /// path：目标文件路径
  /// newText：即将写入的内容
  /// oldText 为 null（示例中不读取旧文件内容，真实场景应在 preview 中读取）
  @override ToolChange? preview(Map<String, dynamic> args) => ToolChange(
    path: args['path']?.toString() ?? '',
    newText: args['content']?.toString(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section 16 — 文件 I/O 与工作区工具
// ═══════════════════════════════════════════════════════════════════════════════

/// 演示 WorkspaceTool、ReadFileTool、WriteFileTool 的完整使用。
///
/// 覆盖场景：
///   - 工作区：列出文件、读取工作区文件
///   - 读文件：分段读、二进制检测
///   - 写文件：六种编辑操作（write / append / insert / replace_lines / delete_lines / replace_text）
///   - 组合流程：查看文件 → 精准编辑 → 验证结果
///
/// 运行方式：
///   dart run example/example.dart --section 16
Future<void> section16_fileAndWorkspaceTools() async {
  print('\n════════ Section 16: 文件 I/O 与工作区工具 ════════');

  // ══ 16.1 工作区环境 ══
  // 使用 example/workspace/ 作为演示工作区，内含真实的 notes.txt
  final workspaceDir = '${Directory.current.path}${Platform.pathSeparator}example${Platform.pathSeparator}workspace';
  final notesFile = '$workspaceDir${Platform.pathSeparator}notes.txt';

  // 保存原始内容，演示结束后恢复
  final originalContent = File(notesFile).readAsStringSync();
  print('\n── 16.1 工作区: $workspaceDir ──');
  print('  预置文件: notes.txt (${originalContent.length} 字节，已备份原始内容)');

  final workspace = WorkspaceTool(workspaceDir);
  final readFile = ReadFileTool(workspaceDir: workspaceDir);
  final writeFile = WriteFileTool(workspaceDir: workspaceDir);

  // ══ 16.2 列出工作区 ══
  print('\n── 16.2 workspace list ──');
  var result = await workspace.execute({'action': 'list'});
  print(result);

  // ══ 16.3 读取文件 ══
  print('\n── 16.3 workspace read notes.txt ──');
  result = await workspace.execute({'action': 'read', 'path': 'notes.txt'});
  print(result);

  // ══ 16.4 分段读取 ══
  // 只读 "待办事项" 那几行
  print('\n── 16.4 read_file 分段读 (offset=3, limit=5) ──');
  result = await readFile.execute({
    'path': notesFile,
    'offset': 3,        // 跳过标题和空行，从待办第一项开始
    'limit': 5,         // 只读 5 行
  });
  print(result);

  // ══ 16.5 插入新待办 ══
  // 在 "会议记录" 标题前插入新章节 "代码审查"
  print('\n── 16.5 write_file insert (插入新章节) ──');
  result = await writeFile.execute({
    'action': 'insert',
    'path': 'notes.txt',
    'start_line': 7,    // "## 会议记录" 在第 8 行（0-indexed: 7），插入在其前
    'content': '\n## 代码审查\n- [x] 审查 PR #42\n- [ ] 审查 PR #56\n',
  });
  print(result);

  // ══ 16.6 替换会议日期 ══
  print('\n── 16.6 write_file replace_text (更新会议日期) ──');
  result = await writeFile.execute({
    'action': 'replace_text',
    'path': 'notes.txt',
    'old_text': '2026-07-01',
    'new_text': '2026-07-02',
  });
  print(result);

  // ══ 16.7 勾选待办 ══
  print('\n── 16.7 write_file replace_text (勾选已完成) ──');
  result = await writeFile.execute({
    'action': 'replace_text',
    'path': 'notes.txt',
    'old_text': '- [ ] 完成用户认证模块',
    'new_text': '- [x] 完成用户认证模块',
  });
  print(result);

  // ══ 16.8 替换整行（更新联系人） ══
  print('\n── 16.8 write_file replace_lines (更新联系人) ──');
  result = await writeFile.execute({
    'action': 'replace_lines',
    'path': 'notes.txt',
    'start_line': 21,   // Tom 那行
    'end_line': 22,     // Jerry 那行
    'content': '- Tom  (前端) — tom@new-company.com\n- Jerry (后端) — jerry@new-company.com\n- Spike (全栈) — spike@example.com',
  });
  print(result);

  // ══ 16.9 删除过时章节 ══
  print('\n── 16.9 write_file delete_lines (删除 API 端点章节) ──');
  result = await writeFile.execute({
    'action': 'delete_lines',
    'path': 'notes.txt',
    'start_line': 14,   // "## API 端点" 标题
    'end_line': 19,     // 表格结束
  });
  print(result);

  // ══ 16.10 正则替换（统一邮箱格式） ══
  print('\n── 16.10 write_file replace_text（正则：邮箱域名迁移）──');
  result = await writeFile.execute({
    'action': 'replace_text',
    'path': 'notes.txt',
    'old_text': r'@example\.com',
    'new_text': '@new-company.com',
    'regex': true,
  });
  print(result);

  // ══ 16.11 追加新笔记 ══
  print('\n── 16.11 write_file append（追加章节）──');
  result = await writeFile.execute({
    'action': 'append',
    'path': 'notes.txt',
    'content': '\n## 下一步计划\n- 完成 2.0 插件系统\n- 部署到测试环境\n- 用户验收测试',
  });
  print(result);

  // ══ 16.12 验证最终结果 ══
  print('\n── 16.12 验证最终结果 ──');
  result = await workspace.execute({'action': 'read', 'path': 'notes.txt'});
  print(result);

  // ══ 16.13 越界保护 ══
  print('\n── 16.13 越界保护 ──');
  result = await writeFile.execute({
    'action': 'write',
    'path': '../escape.txt',
    'content': '越界',
  });
  print(result);

  // ══ 16.14 完整工作流 ══
  print('\n── 16.14 完整工作流总结 ──');
  print('''
  AI 编辑一个真实文件的典型流程：
  1. workspace list           → 看看有哪些文件
  2. workspace read notes.txt  → 读取完整内容（或 read_file 分段读大文件）
  3. write_file insert        → 在指定位置插入新章节
  4. write_file replace_text  → 更新日期、勾选待办
  5. write_file replace_lines → 替换整个联系人区块
  6. write_file delete_lines  → 删除过时的 API 表格
  7. write_file replace_text(regex) → 批量邮箱域名迁移
  8. write_file append        → 追加新内容
  9. workspace read notes.txt  → 确认所有修改生效
  ''');

  // ══ 16.15 恢复原始文件 ══
  File(notesFile).writeAsStringSync(originalContent);
  print('\n── 16.15 已恢复 notes.txt 原始内容 ──');

  print('✓ Section 16 完成\n');
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section 17 — AiUnavailableException（6 个工厂 + fromStatusCode）
// ═══════════════════════════════════════════════════════════════════════════════

/// # 17. AiUnavailableException — AI 不可用降级
///
/// 学习目标：理解 6 种工厂构造函数和 `fromStatusCode` 的用法。
///
/// 核心概念：
/// - `AiUnavailableException` 实现 `Exception`，可被 try-catch 捕获
/// - 6 个工厂覆盖常见失败场景：超时/Key无效/限流/服务器错误/余额不足/模型不支持
/// - `fromStatusCode(int)` 从 HTTP 状态码自动选择合适的异常类型
/// - `recoverable` 字段指示是否可重试
/// - `retryAfterSeconds` 给出建议等待时间
void _demoAiUnavailableException() {
  _section('17. AiUnavailableException（6 工厂 + fromStatusCode）');

  // ── 6 个工厂构造函数 ──
  final exceptions = [
    AiUnavailableException.connectionTimeout(detail: 'DNS 解析失败'),
    AiUnavailableException.invalidApiKey(),
    AiUnavailableException.rateLimited(retryAfterSeconds: 30),
    AiUnavailableException.serverError(statusCode: 503),
    AiUnavailableException.insufficientBalance(),
    AiUnavailableException.unsupportedModel('gpt-7'),
  ];

  for (final e in exceptions) {
    final recoverable = e.recoverable ? '🔄可恢复' : '🛑需人工';
    final retry = e.retryAfterSeconds != null ? ' ${e.retryAfterSeconds}s后重试' : '';
    print('  ${e.reason}: $recoverable$retry — ${e.message}');
  }

  // ── fromStatusCode：HTTP 状态码 → 异常 ──
  print('\n— fromStatusCode（HTTP 状态码 → 异常）—');
  final statusMap = {
    401: 'API Key 无效',
    402: '余额不足',
    429: '请求过于频繁',
    500: '服务器内部错误',
    502: '网关错误',
    503: '服务不可用',
  };
  for (final entry in statusMap.entries) {
    final code = entry.key;
    final desc = entry.value;
    final e = AiUnavailableException.fromStatusCode(code);
    print('  HTTP $code ($desc) → ${e.reason} (recoverable=${e.recoverable})');
  }

  // ── 使用模式：在 Provider 调用处捕获 ──
  print('\n— 使用模式 —');
  print('  try {');
  print('    await provider.chat(messages: [...]).toList();');
  print('  } on AiUnavailableException catch (e) {');
  print('    if (e.recoverable) {');
  print('      await Future.delayed(Duration(seconds: e.retryAfterSeconds ?? 5));');
  print('      // 重试...');
  print('    } else {');
  print('      showError(e.message); // 展示不可恢复的错误');
  print('    }');
  print('  }');

  print('✓ Section 17 完成\n');
}

// ═══════════════════════════════════════════════════════════════════════════════
// Section 18 — MockEventStream（全部 17 种 EventKind 模拟）
// ═══════════════════════════════════════════════════════════════════════════════

/// # 18. MockEventStream — 供渲染工程师开发 UI 的模拟事件流
///
/// 学习目标：理解 `MockEventStream.generate()` 和 `eventKindReference` 的用法。
///
/// 核心概念：
/// - `generate(delay:)` 返回覆盖全部 17 种 EventKind 的异步流
/// - `eventKindReference` 是静态参考表（List<Map<String,String>>）
/// - 渲染工程师无需真实 Agent/Provider/Registry 即可开发 UI 渲染逻辑
/// - 每个事件携带完整示例 payload（ToolEventPayload、TokenUsage、ApprovalPayload 等）
Future<void> _demoMockEventStream() async {
  _section('18. MockEventStream（模拟事件流 + 参考表）');

  // ── eventKindReference：全部 17 种参考表 ──
  print('— eventKindReference（全部 17 种）—');
  for (final entry in MockEventStream.eventKindReference) {
    print('  ${entry['kind']}: ${entry['说明']}');
  }
  print('  （共 ${MockEventStream.eventKindReference.length} 种事件类型）');

  // ── generate：订阅模拟流 ──
  print('\n— generate() 事件流订阅（delay: 0ms，非阻塞演示）—');
  var count = 0;
  final kindsSeen = <String>{};
  await for (final event in MockEventStream.generate(delay: Duration.zero)) {
    count++;
    kindsSeen.add(event.kind.name);

    // 提取关键负载信息用于展示
    final extra = switch (event.kind) {
      EventKind.toolDispatch => ' → ${event.tool?.name}(${event.tool?.arguments})',
      EventKind.toolResult => event.tool?.isError == true
          ? ' → ❌ ${event.tool?.error}'
          : ' → ✅ ${event.tool?.output?.substring(0, (event.tool!.output!.length).clamp(0, 40))}',
      EventKind.usage => ' → ${event.usage}',
      EventKind.notice => ' → [${event.noticeLevel?.name}] ${event.text}',
      EventKind.compactionDone => ' → ${event.compaction?.messagesBefore}→${event.compaction?.messagesAfter} msgs',
      EventKind.approvalRequest => ' → ${event.approval?.toolName}: ${event.approval?.subject}',
      _ => event.text?.isNotEmpty == true ? ' → "${event.text!.length > 50 ? '${event.text!.substring(0, 50)}...' : event.text}"' : '',
    };
    print('  #$count ${event.kind.name}$extra');
  }

  print('\n— 统计 —');
  print('  总事件数: $count');
  print('  覆盖 EventKind: ${kindsSeen.length}/17');
  print('  缺失: ${EventKind.values.where((k) => !kindsSeen.contains(k.name)).map((k) => k.name).join(", ")}');

  print('✓ Section 18 完成\n');
}


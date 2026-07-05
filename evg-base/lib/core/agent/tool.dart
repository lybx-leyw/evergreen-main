/// Tool 抽象、Registry、BuiltinRegistry — 完整对应 reasonix/internal/tool/。
library;

import 'dart:convert';

// ═══════ Tool ═══════

/// 模型可调用的工具。对应 Go 的 tool.Tool。
abstract class Tool {
  /// 蛇形命名，如 get_courses。
  String get name;

  /// 供模型理解用途。
  String get description;

  /// JSON Schema 参数定义。
  Map<String, dynamic> get schema;

  /// 执行工具，返回结果文本。 [args] 是模型生成的 JSON 参数。
  Future<String> execute(Map<String, dynamic> args);

  /// 只读工具可并行执行，非只读串行。
  bool get readOnly => true;
}

// ═══════ SimpleTool ═══════

/// 工具实现——用于测试和简单场景。
class SimpleTool extends Tool {
  @override
  final String name;
  @override
  final String description;
  @override
  final Map<String, dynamic> schema;
  @override
  final bool readOnly;

  final Future<String> Function(Map<String, dynamic> args) _execute;

  SimpleTool({
    required this.name,
    required this.description,
    required this.schema,
    this.readOnly = true,
    required Future<String> Function(Map<String, dynamic> args) execute,
  }) : _execute = execute;

  @override
  Future<String> execute(Map<String, dynamic> args) => _execute(args);
}

// ═══════ Previewer ═══════

/// 写工具的可选能力：预览变更而不实际执行。对应 Go 的 tool.Previewer。
mixin Previewer on Tool {
  /// 返回工具将产生的文件变更预览，用于展示批准卡片。
  ToolChange? preview(Map<String, dynamic> args);
}

// ═══════ ToolChange ═══════

/// 工具变更预览结果。
class ToolChange {
  final String? oldText;
  final String? newText;
  final String path;
  final bool binary;

  const ToolChange({
    this.oldText,
    this.newText,
    required this.path,
    this.binary = false,
  });
}

// ═══════ Schema 工具函数 ═══════

/// Tool → OpenAI function schema。
Map<String, dynamic> toolToSchema(Tool tool) {
  return {
    'type': 'function',
    'function': {
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.schema,
    },
  };
}

/// 多个 Tool → schemas 列表。
List<Map<String, dynamic>> toolsToSchemas(List<Tool> tools) {
  return tools.map(toolToSchema).toList();
}

// ═══════ Registry ═══════

/// 工具注册表。对应 Go 的 tool.Registry。
class Registry {
  final Map<String, Tool> _tools = {};
  final Set<String> _disabled = {};

  /// 注册工具。重复名称抛异常。
  void register(Tool tool) {
    final name = tool.name;
    if (_tools.containsKey(name)) {
      throw ArgumentError('Tool "$name" is already registered');
    }
    _tools[name] = tool;
  }

  void registerAll(List<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  /// 移除已注册的工具。
  void remove(String name) {
    _tools.remove(name);
    _disabled.remove(name);
  }

  void enable(String name) => _disabled.remove(name);
  void disable(String name) => _disabled.add(name);

  bool has(String name) => _tools.containsKey(name);
  bool isEnabled(String name) => _tools.containsKey(name) && !_disabled.contains(name);
  Tool? get(String name) => _tools[name];
  List<Tool> all() => _tools.values.toList();

  /// 已启用的工具列表（按名称排序）。
  List<Tool> enabled() {
    final list = _tools.values.where((t) => !_disabled.contains(t.name)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// 调用工具。[argsJson] 为模型生成的原始 JSON。不存在/禁用返回错误文本。
  Future<String> call(String name, String argsJson) async {
    final tool = _tools[name];
    if (tool == null) return '[error: tool "$name" not found]';
    if (_disabled.contains(name)) return '[error: tool "$name" is disabled]';

    try {
      final args = jsonDecode(argsJson) as Map<String, dynamic>;
      return await tool.execute(args);
    } catch (e) {
      return '[error: tool "$name" failed: $e]';
    }
  }

  /// 调用工具（参数已解析）。
  Future<String> callWithArgs(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) return '[error: tool "$name" not found]';
    if (_disabled.contains(name)) return '[error: tool "$name" is disabled]';

    try {
      return await tool.execute(args);
    } catch (e) {
      return '[error: tool "$name" failed: $e]';
    }
  }

  /// 只读工具名称集合（用于并行调度判断）。
  Set<String> get readOnlyToolNames =>
      _tools.values.where((t) => t.readOnly).map((t) => t.name).toSet();
}

// ═══════ BuiltinRegistry ═══════

/// 编译时内置工具注册表。
class BuiltinRegistry {
  static final Map<String, Tool> _builtins = {};

  /// 注册编译时内置工具。重复名称抛异常。
  static void register(Tool tool) {
    final name = tool.name;
    if (_builtins.containsKey(name)) {
      throw ArgumentError('Duplicate built-in tool: $name');
    }
    _builtins[name] = tool;
  }

  static List<Tool> all() => _builtins.values.toList();
  static Tool? get(String name) => _builtins[name];

  /// 创建包含所有内置工具的运行时 Registry。[exclude] 为排除列表。
  static Registry createRegistry({List<String> exclude = const []}) {
    final registry = Registry();
    for (final t in _builtins.values) {
      if (!exclude.contains(t.name)) registry.register(t);
    }
    return registry;
  }
}

/// Tool 抽象 + Registry — 完整对应 reasonix/internal/tool/。
///
/// Tool 是模型可以调用的能力单元。Registry 管理工具的注册、启用/禁用。
/// Previewer 是写工具的可选能力——预览变更而不实际执行。
library;

import 'dart:convert';

// ─── Tool 接口 ─────────────────────────────────────────────

/// 模型可调用的工具。
///
/// 对应 Go 的 tool.Tool。
abstract class Tool {
  /// 工具名称（蛇形命名，如 get_courses）。
  String get name;

  /// 工具描述，供模型理解用途。
  String get description;

  /// JSON Schema 格式的参数定义。
  Map<String, dynamic> get schema;

  /// 执行工具，返回结果文本供模型消费。
  /// [args] 是模型生成的 JSON 参数。
  Future<String> execute(Map<String, dynamic> args);

  /// 是否为只读工具（无副作用）。
  /// 只读工具可以并行执行；非只读工具串行执行以保证顺序。
  bool get readOnly => true;
}

/// 写工具的可选能力：预览变更而不实际执行。
///
/// 对应 Go 的 tool.Previewer。
mixin Previewer on Tool {
  /// 给定参数，返回工具将要产生的文件变更预览。
  /// 在权限门控之前调用，用于展示批准卡片。
  ToolChange? preview(Map<String, dynamic> args);
}

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

// ─── 工具定义（暴露给模型的 Schema） ─────────────────────

/// 从 Tool 接口提取 ToolSchema 定义。
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

/// 从多个工具生成 schemas 列表。
List<Map<String, dynamic>> toolsToSchemas(List<Tool> tools) {
  return tools.map(toolToSchema).toList();
}

// ─── Registry ──────────────────────────────────────────────

/// 工具注册表。
///
/// 管理全局内置工具和运行时添加的工具。
/// 对应 Go 的 tool.Registry + process-global builtins。
class Registry {
  final Map<String, Tool> _tools = {};
  final Set<String> _disabled = {};

  /// 注册一个工具。重复名称会抛出异常。
  void register(Tool tool) {
    final name = tool.name;
    if (_tools.containsKey(name)) {
      throw ArgumentError('Tool "$name" is already registered');
    }
    _tools[name] = tool;
  }

  /// 批量注册。
  void registerAll(List<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  /// 启用一个之前禁用的工具。
  void enable(String name) {
    _disabled.remove(name);
  }

  /// 禁用一个已注册的工具（不删除注册）。
  void disable(String name) {
    _disabled.add(name);
  }

  /// 工具是否已注册。
  bool has(String name) => _tools.containsKey(name);

  /// 工具是否已启用（已注册且未被禁用）。
  bool isEnabled(String name) => _tools.containsKey(name) && !_disabled.contains(name);

  /// 获取已注册的工具（不论是否启用）。
  Tool? get(String name) => _tools[name];

  /// 所有已注册的工具列表。
  List<Tool> all() => _tools.values.toList();

  /// 所有已启用的工具列表（按名称排序）。
  List<Tool> enabled() {
    final list = _tools.values.where((t) => !_disabled.contains(t.name)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// 调用一个已启用的工具。
  ///
  /// [argsJson] 是模型生成的原始 JSON 字符串。
  /// 返回执行结果文本。如果工具不存在或被禁用，返回错误信息（非抛出）。
  Future<String> call(String name, String argsJson) async {
    final tool = _tools[name];
    if (tool == null) {
      return '[error: tool "$name" not found]';
    }
    if (_disabled.contains(name)) {
      return '[error: tool "$name" is disabled]';
    }

    try {
      final args = jsonDecode(argsJson) as Map<String, dynamic>;
      return await tool.execute(args);
    } catch (e) {
      return '[error: tool "$name" failed: $e]';
    }
  }

  /// 调用一个已启用的工具（参数已解析）。
  Future<String> callWithArgs(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return '[error: tool "$name" not found]';
    }
    if (_disabled.contains(name)) {
      return '[error: tool "$name" is disabled]';
    }

    try {
      return await tool.execute(args);
    } catch (e) {
      return '[error: tool "$name" failed: $e]';
    }
  }

  /// 所有只读工具的名称集合（用于并行调度判断）。
  Set<String> get readOnlyToolNames =>
      _tools.values.where((t) => t.readOnly).map((t) => t.name).toSet();
}

// ─── 内置工具注册表 ───────────────────────────────────────

/// 全局内置工具注册表。
///
/// 工具通过 BuiltinRegistry.register() 在库初始化时注册。
/// Agent 通过 Registry(enabled) 获取运行时可用的子集。
class BuiltinRegistry {
  static final Map<String, Tool> _builtins = {};

  /// 注册一个编译时内置工具。重复名称会抛出异常。
  static void register(Tool tool) {
    final name = tool.name;
    if (_builtins.containsKey(name)) {
      throw ArgumentError('Duplicate built-in tool: $name');
    }
    _builtins[name] = tool;
  }

  /// 获取所有已注册的内置工具。
  static List<Tool> all() => _builtins.values.toList();

  /// 按名称获取内置工具。
  static Tool? get(String name) => _builtins[name];

  /// 创建包含所有内置工具的运行时 Registry。
  /// [exclude] 是要排除的工具名称列表。
  static Registry createRegistry({List<String> exclude = const []}) {
    final registry = Registry();
    for (final t in _builtins.values) {
      if (!exclude.contains(t.name)) {
        registry.register(t);
      }
    }
    return registry;
  }
}

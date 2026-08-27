/// Agent 内置工具：后台常驻进程的查看（list_processes）与结束（kill_process）。
///
/// Task 三决策 3.2：配合 [AgentProcessRegistry] 管理 `lifetime:"resident"`
/// 的插件工具进程。两者均经注册表操作，与 UI（后台 N 个 tool 进程按钮，
/// 属批次 2 A6 渲染层任务）无关。
///
/// 三处工具注册点（app_bootstrap / agent_runtime / agent_factory）须同步注册；
/// 缺省使用全局单例 [agentProcessRegistry]，也可注入实例（测试用）。
library;

import '../tool.dart';
import 'agent_process_registry.dart';

/// 列出后台常驻 tool 进程：名称、状态（运行中/已退出）、启动时间、累积输出摘要。
///
/// 只读工具（可并行）；输出单进程截断 2000 字符，避免撑爆上下文。
class ListProcessesTool extends Tool {
  final AgentProcessRegistry _registry;

  ListProcessesTool({AgentProcessRegistry? registry})
      : _registry = registry ?? agentProcessRegistry;

  @override
  String get name => 'list_processes';

  @override
  String get description =>
      '列出所有后台常驻（resident）tool 进程：名称、状态（运行中/已退出）、'
      '启动时间与累积输出摘要（单进程最多 2000 字符）。'
      '需要查看后台进程状态或确认输出时调用本工具；'
      '结束后台进程请用 kill_process。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {},
        'required': [],
      };

  @override
  bool get readOnly => true;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final entries = _registry.entries;
    if (entries.isEmpty) {
      return '当前没有后台常驻的 tool 进程。'
          '（提示：manifest 声明 lifetime:"resident" 的插件工具被调用后才会出现在这里；'
          '一次性工具不经过后台注册表。）';
    }
    final buf = StringBuffer();
    buf.writeln('## 后台 tool 进程（共 ${entries.length} 个）\n');
    for (final e in entries) {
      final status = e.isRunning ? '运行中' : '已退出(exit=${e.exitCode})';
      buf.writeln('- **${e.name}** ｜ $status ｜ 启动于 '
          '${e.startedAt.toIso8601String()}');
      final output = e.output;
      final summary = output.length > 2000
          ? '${output.substring(0, 2000)}\n…（截断，共 ${output.length} 字符）'
          : (output.isEmpty ? '（暂无输出）' : output);
      buf.writeln('  ```');
      buf.writeln(summary);
      buf.writeln('  ```');
    }
    buf.writeln();
    buf.writeln('使用 kill_process 结束指定进程（参数 name）。');
    return buf.toString();
  }
}

/// 结束指定的后台常驻进程。
///
/// 写工具（串行执行）；参数 `name` 必填，为 list_processes 列出的进程名称。
class KillProcessTool extends Tool {
  final AgentProcessRegistry _registry;

  KillProcessTool({AgentProcessRegistry? registry})
      : _registry = registry ?? agentProcessRegistry;

  @override
  String get name => 'kill_process';

  @override
  String get description =>
      '结束指定的后台常驻（resident）tool 进程。'
      '参数 name 为 list_processes 列出的进程名称（即工具名）。'
      '结束后该进程从后台注册表移除，其累积输出不再可查。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '要结束的后台进程名称（list_processes 可查）。',
          },
        },
        'required': ['name'],
      };

  @override
  bool get readOnly => false;

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final name = args['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      return '[error: kill_process: 参数 name 必填。'
          '先调用 list_processes 查看后台进程名称。]';
    }
    return _registry.kill(name);
  }
}

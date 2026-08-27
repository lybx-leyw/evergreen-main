/// Agent 工具后台进程注册表 — 常驻（resident）tool 进程的统一管理。
///
/// Task 三决策 3.2：`PluginManifest.lifetime == "resident"` 的插件工具被 AI
/// 调用后，进程在此登记并持续运行，AI 可经内置工具 `list_processes` 查看、
/// `kill_process` 结束；app 退出 / Controller dispose 时经 [disposeAll] 清理。
///
/// ## 设计
/// - 顶层单例 [agentProcessRegistry]：三处工具注册点（app_bootstrap /
///   agent_runtime / agent_factory）与 [PluginTool] 共享同一实例，保证
///   list_processes / kill_process 看到同一份状态（历史教训：注册表不同步
///   会令工具成摆设）。
/// - [startResident] 幂等：同 key 已有**运行中**进程则直接复用，不重复启动。
/// - 进程自然退出后条目标记 [ResidentProcessEntry.isRunning] == false 并保留
///   累积输出（供 list_processes 展示「已退出」状态与最终输出，符合
///   「输出自动回填」语义）；主动清理路径：`kill` / 同 key 重启替换 /
///   [disposeAll]。已退出条目不会阻塞幂等重启。
/// - 终止走阶梯：SIGTERM → 2s → SIGKILL（对齐 `core/plugin/python_session.dart`
///   close 的信号段）。
/// - 仅依赖 `dart:io`（[Process.start]），无 Flutter Widget、零新 pub 依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 单个常驻进程条目。
class ResidentProcessEntry {
  /// 注册表 key（工具名 / 插件名）。
  final String name;

  /// 原生进程句柄（安卓为 [ChaquopyLongProcess] 的 [Process] 包装）。
  final Process process;

  /// 启动时间。
  final DateTime startedAt;

  /// 累积 stdout 输出（逐行追加，utf-8 解码）。
  final StringBuffer stdoutBuffer = StringBuffer();

  /// 累积 stderr 输出（逐行追加，诊断用）。
  final StringBuffer stderrBuffer = StringBuffer();

  /// 退出码 future——进程存活期间未完成。
  late final Future<int> exitCodeFuture;

  bool _exited = false;
  int? _exitCode;

  ResidentProcessEntry({
    required this.name,
    required this.process,
    required this.startedAt,
  }) {
    exitCodeFuture = process.exitCode;
    exitCodeFuture.then((code) {
      _exitCode = code;
      _exited = true;
    }, onError: (_) {
      // exitCode 异常完成（如信号中断）同样视为已退出。
      _exited = true;
    });
  }

  /// 是否仍在运行。
  bool get isRunning => !_exited;

  /// 退出码（未退出为 null）。
  int? get exitCode => _exitCode;

  /// 累积 stdout 全文。
  String get output => stdoutBuffer.toString();
}

/// Agent 工具后台进程注册表。
///
/// 全部 API 幂等可重入；除 [startResident] / [kill] / [disposeAll] 外不抛异常
/// （未命中 key 一律返回空 / false / 说明文本，供工具层直接回显给 AI）。
class AgentProcessRegistry {
  final Map<String, ResidentProcessEntry> _entries = {};

  /// 是否已有同名**运行中**进程。
  bool isRunning(String name) {
    final e = _entries[name];
    return e != null && e.isRunning;
  }

  /// 条目总数（含已退出但未清理的）。
  int get count => _entries.length;

  /// 全部条目（含已退出），供 list_processes 展示。
  List<ResidentProcessEntry> get entries => _entries.values.toList();

  /// 活动（运行中）进程名列表。
  List<String> activeNames() =>
      _entries.values.where((e) => e.isRunning).map((e) => e.name).toList();

  /// 取条目（含已退出）；未登记返回 null。
  ResidentProcessEntry? entry(String name) => _entries[name];

  /// 启动常驻进程并登记。**幂等**：同 key 已有运行中进程则直接复用
  /// （不重复启动、不覆盖）；同 key 已退出的旧条目被替换为新进程。
  ///
  /// [cmd] 首元素为可执行文件路径，其余为参数；[env] / [workingDir] 可选。
  Future<void> startResident(
    String name,
    List<String> cmd, {
    Map<String, String>? env,
    String? workingDir,
  }) async {
    if (isRunning(name)) return;
    if (cmd.isEmpty) {
      throw ArgumentError('AgentProcessRegistry.startResident: cmd 不能为空');
    }
    final process = await Process.start(
      cmd.first,
      cmd.skip(1).toList(),
      environment: env,
      workingDirectory: workingDir,
    );
    attach(name, process);
  }

  /// 登记一个已由外部（如 [PluginRunner.startLong]）启动的进程。
  ///
  /// 同步登记：立即接管 stdout/stderr 累积，并挂进程退出回调
  /// （标记已退出；条目保留在 map 供读取，见类注释）。
  void attach(String name, Process process) {
    _entries.remove(name);
    final entry = ResidentProcessEntry(
      name: name,
      process: process,
      startedAt: DateTime.now(),
    );
    _entries[name] = entry;
    _pumpOutput(entry);
  }

  /// 返回累积 stdout 输出（未登记返回空串）。
  Future<String> readOutput(String name) async {
    final e = _entries[name];
    if (e == null) return '';
    return e.output;
  }

  /// 结束指定后台进程：阶梯终止 SIGTERM → 2s → SIGKILL。
  ///
  /// 返回给 AI 的结果文本；未登记 / 已退出也返回说明（不抛异常）。
  Future<String> kill(String name) async {
    final entry = _entries[name];
    if (entry == null) {
      return '未找到后台进程 "$name"（可能从未启动、已退出或已被清理）。'
          '可用 list_processes 查看当前后台进程。';
    }
    final proc = entry.process;
    if (!entry.isRunning) {
      _entries.remove(name);
      return '后台进程 "$name" 已退出（exit=${entry.exitCode}），已从注册表移除。';
    }
    _signal(proc, ProcessSignal.sigterm);
    if (await _waitExit(proc, const Duration(seconds: 2))) {
      _entries.remove(name);
      return '已终止后台进程 "$name"。';
    }
    _signal(proc, ProcessSignal.sigkill);
    await _waitExit(proc, const Duration(seconds: 1));
    _entries.remove(name);
    return '已强制终止后台进程 "$name"（SIGTERM 超时后升级 SIGKILL）。';
  }

  /// 清理全部常驻进程（供 app 退出 / Controller dispose 调用）。幂等。
  Future<void> disposeAll() async {
    final names = _entries.keys.toList();
    for (final name in names) {
      try {
        await kill(name);
      } catch (_) {
        // 单进程清理失败不阻塞其余清理。
      }
    }
    _entries.clear();
  }

  // ═══════ 内部 ═══════

  /// stdout/stderr 逐行追加到条目 buffer。
  void _pumpOutput(ResidentProcessEntry entry) {
    entry.process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      entry.stdoutBuffer.writeln(line);
    });
    entry.process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      entry.stderrBuffer.writeln(line);
    });
  }

  Future<bool> _waitExit(Process proc, Duration timeout) async {
    try {
      await proc.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      // exitCode 异常完成（进程已死 / 通道断开）视为已退出。
      return true;
    }
  }

  void _signal(Process proc, ProcessSignal signal) {
    try {
      proc.kill(signal);
    } catch (_) {
      // 已退出 / 安卓占位 kill 返回 false，均忽略。
    }
  }
}

/// 全局共享注册表实例——app_bootstrap / agent_runtime / agent_factory 三处
/// 注册点与 [PluginTool] 共用，保证后台进程状态全局唯一可见。
final AgentProcessRegistry agentProcessRegistry = AgentProcessRegistry();

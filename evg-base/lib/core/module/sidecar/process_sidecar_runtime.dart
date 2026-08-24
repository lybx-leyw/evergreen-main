/// [SidecarRuntime] 的 dart:io 实现（M1-7）。
///
/// 把「真实启动进程」接到 dart:io 的 [Process.start]，Python 入口自动套解释器。
/// 与现有 [sharedPluginRunner] 同构，但接口面向 [SidecarProcess] 抽象。
library;

import 'dart:async';
import 'dart:io';

import 'sidecar_controller.dart';

/// 基于 dart:io 的 sidecar 运行时实现。
class ProcessSidecarRuntime implements SidecarRuntime {
  /// Python 解释器路径；为 null 时 Python sidecar 在 [startProcess] 仍尝试
  /// 系统 `python`，但调用方通常已 fail-closed 在更上层拦截。
  final String? pythonExe;

  const ProcessSidecarRuntime({this.pythonExe});

  @override
  Future<SidecarProcess> startProcess(
    List<String> command,
    String workingDirectory, {
    Map<String, String> environment = const {},
  }) async {
    final process = await Process.start(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment: environment.isEmpty ? null : environment,
    );
    return _IoSidecarProcess(process);
  }
}

/// dart:io [Process] 的 [SidecarProcess] 适配。
class _IoSidecarProcess implements SidecarProcess {
  final Process _p;
  _IoSidecarProcess(this._p);

  @override
  int get pid => _p.pid;

  @override
  Stream<List<int>> get stdout => _p.stdout;

  @override
  Stream<List<int>> get stderr => _p.stderr;

  @override
  Future<int> kill([String signal = 'SIGTERM']) {
    final sig = _toSignal(signal);
    _p.kill(sig);
    return _p.exitCode;
  }

  @override
  Future<int> get exitCode => _p.exitCode;
}

/// 把字符串信号名映射到 [ProcessSignal]（dart:io 不支持运行时动态构造，
/// 仅支持常见三者）。
ProcessSignal _toSignal(String signal) {
  switch (signal) {
    case 'SIGKILL':
      return ProcessSignal.sigkill;
    case 'SIGINT':
      return ProcessSignal.sigint;
    case 'SIGTERM':
    default:
      return ProcessSignal.sigterm;
  }
}

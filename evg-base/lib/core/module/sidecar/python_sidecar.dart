/// Python sidecar 控制器实现（M1-4）。
library;

import '../runtime.dart';
import 'command.dart';
import 'sidecar_controller.dart';

/// Python 侧车控制器。
///
/// [pythonExe] 为解释器路径；为 null 时 [start] fail-closed。
class PythonSidecarController implements SidecarController {
  @override
  final RuntimeKind kind = RuntimeKind.python;

  final RuntimeDescriptor _descriptor;
  final SidecarRuntime _runtime;
  final String? pythonExe;

  @override
  int? port;

  @override
  bool isHealthy = false;

  SidecarProcess? _process;

  @override
  String get entry => _descriptor.entry;

  @override
  RuntimeCapabilities get capabilities => _descriptor.capabilities;

  PythonSidecarController(
    this._descriptor,
    this._runtime, {
    this.pythonExe,
  });

  @override
  Future<void> start() async {
    final resolvedPort = resolveSidecarPort(_descriptor.port, {});
    port = resolvedPort;
    final cmd = buildPythonCommand(
      _descriptor,
      '.',
      resolvedPort,
      pythonExe: pythonExe,
    );
    _process = await _runtime.startProcess(
      cmd.argv,
      cmd.workingDirectory,
      environment: cmd.environment,
    );
    isHealthy = _process != null;
  }

  @override
  Future<void> stop() async {
    if (_process == null) return;
    _process!.kill('SIGTERM');
    final timeout = gracefulKillTimeoutMs(_descriptor.gracefulTimeoutMs);
    final exited = await _process!.exitCode
        .timeout(Duration(milliseconds: timeout))
        .then((_) => true)
        .catchError((_) => false);
    if (!exited) _process!.kill('SIGKILL');
    isHealthy = false;
    port = null;
    _process = null;
  }

  @override
  void kill() {
    _process?.kill('SIGKILL');
    isHealthy = false;
    port = null;
    _process = null;
  }
}

/// Deno sidecar 控制器实现（M1-5，占位 + 校验）。
library;

import '../runtime.dart';
import 'command.dart';
import 'sidecar_controller.dart';

/// Deno 侧车控制器。
///
/// Deno 默认安全（无 --allow-* 即零权限），授权按 capabilities 收窄注入。
/// [denoExe] 为 deno 可执行路径；为 null 时 [start] fail-closed。
class DenoSidecarController implements SidecarController {
  @override
  final RuntimeKind kind = RuntimeKind.deno;

  final RuntimeDescriptor _descriptor;
  final SidecarRuntime _runtime;
  final String? denoExe;

  @override
  int? port;

  @override
  bool isHealthy = false;

  SidecarProcess? _process;

  @override
  String get entry => _descriptor.entry;

  @override
  RuntimeCapabilities get capabilities => _descriptor.capabilities;

  DenoSidecarController(
    this._descriptor,
    this._runtime, {
    this.denoExe,
  });

  @override
  Future<void> start() async {
    final resolvedPort = resolveSidecarPort(_descriptor.port, {});
    port = resolvedPort;
    // denoExe 为 null → buildDenoCommand 抛 StateError（fail-closed）。
    final cmd = buildDenoCommand(
      _descriptor,
      '.',
      resolvedPort,
      denoExe: denoExe,
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

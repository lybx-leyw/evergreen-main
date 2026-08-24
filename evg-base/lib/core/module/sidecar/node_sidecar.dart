/// Node sidecar 控制器实现（M1-3）。
///
/// 复用 [SidecarRuntime]（真实启动由宿主注入）与 [buildNodeCommand] 拼装命令。
library;

import 'dart:io';
import '../runtime.dart';
import 'command.dart';
import 'sidecar_controller.dart';

/// Node.js 侧车控制器。
class NodeSidecarController implements SidecarController {
  @override
  final RuntimeKind kind = RuntimeKind.node;

  final RuntimeDescriptor _descriptor;
  final SidecarRuntime _runtime;

  /// 健康探测注入点（默认真实 HTTP GET /health）。测试可替换。
  final Future<bool> Function(int port)? healthProbe;

  /// 等待 PORT: 行的最长时限（默认 10s）。测试可缩短。
  final Duration portReadTimeout;

  @override
  int? port;

  @override
  bool isHealthy = false;

  SidecarProcess? _process;

  NodeSidecarController(
    this._descriptor,
    this._runtime, {
    this.healthProbe,
    this.portReadTimeout = const Duration(seconds: 10),
  });

  @override
  String get entry => _descriptor.entry;

  @override
  RuntimeCapabilities get capabilities => _descriptor.capabilities;

  @override
  Future<void> start() async {
    final resolvedPort = resolveSidecarPort(_descriptor.port, {});
    final cmd = buildNodeCommand(_descriptor, '.', resolvedPort);
    _process = await _runtime.startProcess(
      cmd.argv,
      cmd.workingDirectory,
      environment: cmd.environment,
    );
    if (_process == null) {
      isHealthy = false;
      return;
    }

    // 1) 从 stdout 读取 PORT: 行（超时未出现则判失败）。
    port = await _readPortFromStdout(_process!)
        .timeout(portReadTimeout, onTimeout: () => null);
    if (port == null) {
      isHealthy = false;
      kill();
      return;
    }

    // 2) 健康探测：GET /health 期望 200。
    final probe = healthProbe ?? _defaultProbe;
    isHealthy = await probe(port!);
    if (!isHealthy) kill();
  }

  /// 监听 stdout 直到出现 PORT: 行，返回真实端口（已含宿主自动分配结果）。
  /// 流结束仍未匹配到 PORT 行则返回 null（视为启动失败）。
  static Future<int?> _readPortFromStdout(SidecarProcess p) async {
    await for (final bytes in p.stdout) {
      final line = String.fromCharCodes(bytes);
      final parsed = parsePortLine(line);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// 默认健康探测：HTTP GET /health → 200。
  ///
  /// 用 [InternetAddress.loopback] 避免 `localhost` 在子进程/DNS 环境下
  /// 解析挂起；整体 5s 超时保护，失败即判不健康（fail-closed）。
  static Future<bool> _defaultProbe(int port) async {
    final client = HttpClient();
    try {
      final req = await client
          .get('localhost', port, '/health')
          .timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
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
    _process = null;
  }
}

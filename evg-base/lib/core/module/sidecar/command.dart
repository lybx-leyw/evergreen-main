/// sidecar 命令拼装（M1-3/4/5）。
///
/// 把 [RuntimeDescriptor] 翻译成「语言运行时可执行 + 入口 + 参数 + 环境」，
/// 与具体进程启动机制解耦。真实启动时由 [SidecarRuntime.startProcess] 注入。
library;

import '../runtime.dart';
import 'sidecar_controller.dart';

/// 拼装出的启动指令（纯数据，便于单测断言）。
class SidecarCommand {
  /// 完整命令行（executable + args）。
  final List<String> argv;

  /// 工作目录（插件根）。
  final String workingDirectory;

  /// 注入给子进程的环境变量（含端口与能力约束）。
  final Map<String, String> environment;

  const SidecarCommand({
    required this.argv,
    required this.workingDirectory,
    required this.environment,
  });
}

/// 把能力约束注入子进程环境（M1-9，纯逻辑）。
///
/// 最小可行版：把 deny-all 原则落到子进程可见的环境变量，
/// 让 sidecar 自身也能按契约收窄行为（宿主代理出口才是完全版）。
Map<String, String> buildCapabilityEnv(RuntimeCapabilities caps, int port) {
  final env = <String, String>{
    'EVERGREEN_SIDECAR_PORT': port.toString(),
    'EVERGREEN_FS_SCOPE': caps.fsScope.name,
    'EVERGREEN_NET_ALLOW': caps.netAllow.join(','),
    'EVERGREEN_SPAWN_ALLOW': caps.spawnAllow.join(','),
    // 显式声明 deny-all，便于 sidecar 自检。
    'EVERGREEN_DENY_ALL': caps.isDenyAll ? '1' : '0',
  };
  return env;
}

/// Node 命令拼装：[node <entry> --port <p>]（M1-3）。
SidecarCommand buildNodeCommand(
  RuntimeDescriptor d,
  String workingDirectory,
  int port,
) {
  final argv = ['node', d.entry, '--port', port.toString()];
  return SidecarCommand(
    argv: argv,
    workingDirectory: workingDirectory,
    environment: buildCapabilityEnv(d.capabilities, port),
  );
}

/// Python 命令拼装：[python <entry> --port <p>]（M1-4）。
///
/// [pythonExe] 为解释器路径；为 null 时 fail-closed（运行时校验阶段会抛）。
SidecarCommand buildPythonCommand(
  RuntimeDescriptor d,
  String workingDirectory,
  int port, {
  String? pythonExe,
}) {
  if (pythonExe == null) {
    throw StateError('Python 解释器不可用，无法启动 sidecar ${d.entry}');
  }
  final argv = [pythonExe, d.entry, '--port', port.toString()];
  return SidecarCommand(
    argv: argv,
    workingDirectory: workingDirectory,
    environment: buildCapabilityEnv(d.capabilities, port),
  );
}

/// Deno 命令拼装（M1-5）。
///
/// Deno 需要 `--allow-net`/`--allow-read`/`--allow-run` 显式授权，
/// 这里按 capabilities 收窄授权范围（deny-all 则不给任何 allow flag）。
SidecarCommand buildDenoCommand(
  RuntimeDescriptor d,
  String workingDirectory,
  int port, {
  String? denoExe,
}) {
  if (denoExe == null) {
    throw StateError('Deno 不可用，无法启动 sidecar ${d.entry}');
  }
  final args = <String>['run'];

  // 网络授权：deny-all 不给 --allow-net；否则逐条白名单。
  if (d.capabilities.netAllow.isNotEmpty) {
    args.add('--allow-net=${d.capabilities.netAllow.join(',')}');
  }
  // 文件授权：plugin-dir / app-data 给 --allow-read；none 不给。
  if (d.capabilities.fsScope != FileScope.none) {
    args.add('--allow-read');
  }
  // 子进程授权：空白名单不给 --allow-run。
  if (d.capabilities.spawnAllow.isNotEmpty) {
    args.add('--allow-run=${d.capabilities.spawnAllow.join(',')}');
  }

  args.add(d.entry);
  args.addAll(['--port', port.toString()]);

  return SidecarCommand(
    argv: [denoExe, ...args],
    workingDirectory: workingDirectory,
    environment: buildCapabilityEnv(d.capabilities, port),
  );
}

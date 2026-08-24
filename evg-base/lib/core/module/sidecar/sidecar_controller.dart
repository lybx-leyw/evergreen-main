/// sidecar 一等公民控制器（M1 · 3.1）。
///
/// 把「语言运行时」从 [ModuleLoader] 的特判改成统一接口：Node/Python/Deno 是三个实现。
/// 生命周期：install → 校验 runtime 存在 → 起进程 → 健康检查 → 注册端口 → 事件流 → 切走/卸载时优雅停 + 强杀兜底。
///
/// 本文件只定义抽象接口与**纯逻辑**辅助（端口分配、超时阈值、工厂选择），
/// 进程启动依赖 [SidecarRuntime] 抽象由具体实现注入，便于单测不触真实子进程。
library;

import '../runtime.dart';

/// sidecar 控制器抽象——定义生命周期契约。
///
/// 具体实现（Node/Python/Deno）负责真正启动/停止子进程。
abstract class SidecarController {
  /// 语言运行时种类。
  RuntimeKind get kind;

  /// 插件入口相对路径（manifest.runtime.entry）。
  String get entry;

  /// 能力申请（deny-all 默认）。
  RuntimeCapabilities get capabilities;

  /// 当前监听端口（启动完成前为 null）。
  int? get port;

  /// 是否健康（健康检查通过）。
  bool get isHealthy;

  /// 启动子进程（实现负责拼装命令 + 调用运行时 + 端口检测 + 健康探测）。
  Future<void> start();

  /// 优雅停机：先 SIGTERM，超时 [RuntimeDescriptor.gracefulTimeoutMs] 后强杀。
  Future<void> stop();

  /// 强制杀死（兜底）。
  void kill();
}

/// sidecar 运行时元信息（纯数据，供 HTTP 端点序列化）。
class SidecarMeta {
  final RuntimeKind kind;
  final String entry;
  final int? port;
  final bool healthy;
  final RuntimeCapabilities capabilities;

  const SidecarMeta({
    required this.kind,
    required this.entry,
    required this.port,
    required this.healthy,
    required this.capabilities,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'entry': entry,
        if (port != null) 'port': port,
        'healthy': healthy,
        'capabilities': capabilities.toJson(),
      };
}

/// 从任意 [SidecarController] 抽取运行时元信息（供 /module/sidecars 序列化）。
SidecarMeta sidecarMetaOf(SidecarController c) => SidecarMeta(
      kind: c.kind,
      entry: c.entry,
      port: c.port,
      healthy: c.isHealthy,
      capabilities: c.capabilities,
    );

/// 端口分配策略（纯函数）。
///
/// [preferred] 为 0 时由宿主从 [pool] 中分配一个未占用端口；否则原样返回。
int resolveSidecarPort(int preferred, Set<int> occupied) {
  if (preferred > 0) {
    if (occupied.contains(preferred)) {
      throw StateError('请求端口 $preferred 已被占用');
    }
    return preferred;
  }
  // 自动分配：从 0x4000(16384) 起避开常用段，选第一个未占用。
  for (var p = 16384; p < 65535; p++) {
    if (!occupied.contains(p)) return p;
  }
  throw StateError('无可用端口（端口池耗尽）');
}

/// 优雅停机超时阈值（纯函数）。
///
/// 返回强杀兜底前的最大等待毫秒。来自 [RuntimeDescriptor.gracefulTimeoutMs]，
/// 下限保护 1000ms，避免误配 0 导致瞬间强杀无优雅窗口。
int gracefulKillTimeoutMs(int configured) =>
    configured < 1000 ? 1000 : configured;

/// 控制器构造器签名：给定 [RuntimeDescriptor] + 运行时抽象，产出控制器。
typedef SidecarControllerFactory = SidecarController Function(
  RuntimeDescriptor descriptor,
  SidecarRuntime runtime,
);

/// 运行时抽象——具体实现注入真实进程启动能力（M1-3/4/5 实现）。
///
/// 抽离出 [startProcess] 让纯逻辑可测；真实实现调用 [sharedPluginRunner]。
abstract class SidecarRuntime {
  /// 启动进程，返回进程句柄。
  Future<SidecarProcess> startProcess(
    List<String> command,
    String workingDirectory, {
    Map<String, String> environment,
  });
}

/// 进程句柄抽象（屏蔽 dart:io Process 细节，便于测试替身）。
abstract class SidecarProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> kill([String signal]);
  Future<int> get exitCode;
}

/// 从一行 stdout 解析 `PORT:` 声明（纯函数，可单测）。
///
/// 形如 `PORT:3000` 或 `listening on PORT:3000`。找不到返回 null。
int? parsePortLine(String line) {
  final m = RegExp(r'PORT:(\d+)').firstMatch(line);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// sidecar 控制器工厂（M1-6）。
///
/// 按 [RuntimeKind] 选择对应实现构造器。集中在独立文件以避免
/// `sidecar_controller.dart` 与各实现间的循环依赖。
library;

import '../runtime.dart';
import 'node_sidecar.dart';
import 'python_sidecar.dart';
import 'deno_sidecar.dart';
import 'sidecar_controller.dart';

/// 按 [RuntimeKind] 选择对应实现构造器（工厂入口）。
///
/// 返回构造器闭包，由调用方注入 [SidecarRuntime]（真正启动进程的抽象）。
/// 这样纯逻辑（kind→实现映射）可单测，无需真实运行时。
SidecarControllerFactory sidecarFactoryFor(RuntimeKind kind) {
  switch (kind) {
    case RuntimeKind.node:
      return (descriptor, runtime) => NodeSidecarController(descriptor, runtime);
    case RuntimeKind.python:
      return (descriptor, runtime) =>
          PythonSidecarController(descriptor, runtime);
    case RuntimeKind.deno:
      return (descriptor, runtime) => DenoSidecarController(descriptor, runtime);
  }
}

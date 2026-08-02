/// Flutter services stub for agent package（纯 Dart 测试隔离）。
///
/// 副本 — 覆盖 plugin_runner（ChaquopyRunner / ChaquopyLongProcess）实际用到的
/// MethodChannel / EventChannel 最小签名。测试环境中这些 channel 不会收到
/// 原生响应，invokeMethod 返回 null、EventChannel 流为空。
library services;

/// 方法通道（镜像 flutter services.MethodChannel）。
class MethodChannel {
  final String name;
  const MethodChannel(this.name);

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async => null;
}

/// 事件通道（镜像 flutter services.EventChannel）。
class EventChannel {
  final String name;
  const EventChannel(this.name);

  Stream<dynamic> receiveBroadcastStream({dynamic arguments}) =>
      const Stream<dynamic>.empty();
}

/// Stub 包——替代真实 flutter_riverpod，避免 Flutter SDK 依赖。
///
/// 仅提供 provider.dart 所需的类型签名。

// ignore_for_file: unused_field

/// [FutureProvider] — 异步 Provider。
class FutureProvider<T> {
  final Future<T> Function(dynamic ref) _create;

  FutureProvider(this._create);
}

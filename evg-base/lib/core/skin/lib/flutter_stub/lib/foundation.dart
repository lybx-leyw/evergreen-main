/// Flutter foundation stub — 提供 [ChangeNotifier]。
///
/// 实际使用时由主项目的 Flutter SDK 覆盖。

/// 可监听变更的通知器。
/// 对齐真实 Flutter 行为：dispose 后 addListener/notifyListeners 触发 assert。
class ChangeNotifier {
  final List<void Function()> _listeners = [];
  bool _disposed = false;

  /// 注册监听回调。
  void addListener(void Function() listener) {
    assert(!_disposed, 'A ChangeNotifier was used after being disposed.');
    _listeners.add(listener);
  }

  /// 移除监听回调。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// 通知全部监听者。
  void notifyListeners() {
    assert(!_disposed, 'A ChangeNotifier was used after being disposed.');
    for (final l in _listeners) {
      l();
    }
  }

  /// 清空全部监听者。
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// Flutter foundation stub — 提供 [ChangeNotifier]。
///
/// 实际使用时由主项目的 Flutter SDK 覆盖。

/// 可监听变更的通知器。
class ChangeNotifier {
  final List<void Function()> _listeners = [];

  /// 注册监听回调。
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// 移除监听回调。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// 通知全部监听者。
  void notifyListeners() {
    for (final l in _listeners) {
      l();
    }
  }

  /// 清空全部监听者。
  void dispose() {
    _listeners.clear();
  }
}

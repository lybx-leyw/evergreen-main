/// Minimal flutter/foundation.dart stub for core module isolation.
library foundation;

// kReleaseMode constant used by log.dart
const bool kReleaseMode = false;

/// 调试打印（镜像 flutter foundation.debugPrint 签名）。
/// 供 core 根 log.dart 的安卓 logcat 镜像分支使用。
void debugPrint(String? message, {int? wrapWidth}) {
  // ignore: avoid_print
  print(message ?? '');
}

/// 可见性注解（镜像 flutter foundation.visibleForTesting）。
/// 供 core 根 greenix_path.dart 等使用。
const visibleForTesting = _VisibleForTesting();

class _VisibleForTesting {
  const _VisibleForTesting();
}

/// Minimal ChangeNotifier for ThemeStore (theme/).
class ChangeNotifier {
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notifyListeners() {
    for (final l in _listeners) { l(); }
  }
  void dispose() => _listeners.clear();
}

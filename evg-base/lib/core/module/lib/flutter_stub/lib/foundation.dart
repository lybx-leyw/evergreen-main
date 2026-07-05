/// Minimal flutter/foundation.dart stub for core module isolation.
library foundation;

// kReleaseMode constant used by log.dart
const bool kReleaseMode = false;

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

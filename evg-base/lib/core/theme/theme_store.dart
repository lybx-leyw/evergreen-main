/// 主题存储器——收集 [ThemeDescriptor] + 响应式活跃主题切换。
///
/// # [ThemeStore] — 响应式主题容器
///
/// | 方法 / getter | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `register(t)` | `ThemeDescriptor` | `void` | 注册主题；同 id 后者覆盖 |
/// | `all` | — | `List<ThemeDescriptor>` | 全部已注册主题 |
/// | `findById(id)` | `String` | `ThemeDescriptor?` | 按 id 查找 |
/// | `activeTheme` | — | `ThemeDescriptor?` | 当前活跃主题 |
/// | `activeTheme=` | `ThemeDescriptor?` | `void` | 设置活跃主题→通知监听者 |
/// | `setActiveById(id)` | `String` | `bool` | 按 id 切换；不存在返回 false |
/// | `activeOrFirst` | — | `ThemeDescriptor?` | 活跃主题或第一个已注册主题 |
library;

import 'package:flutter/foundation.dart';
import 'theme_descriptor.dart';

/// 响应式主题存储器。
///
/// 继承 [ChangeNotifier]：设置 [activeTheme] 时触发 [notifyListeners]。
class ThemeStore extends ChangeNotifier {
  final Map<String, ThemeDescriptor> _themes = {};
  ThemeDescriptor? _active;

  // ═══════ 注册 ═══════

  /// 注册主题。同 id 则覆盖（后者优先）。
  void register(ThemeDescriptor theme) {
    _themes[theme.id] = theme;
  }

  /// 全部已注册主题。
  List<ThemeDescriptor> get all => List.unmodifiable(_themes.values);

  /// 按 id 查找。
  ThemeDescriptor? findById(String id) => _themes[id];

  // ═══════ 活跃主题 ═══════

  /// 当前活跃主题。未设置返回 null。
  ThemeDescriptor? get activeTheme => _active;

  /// 设置活跃主题并通知全部监听者。
  set activeTheme(ThemeDescriptor? theme) {
    if (_active?.id == theme?.id) return; // 同主题不重复通知
    _active = theme;
    notifyListeners();
  }

  /// 按 id 切换活跃主题。成功返回 true，不存在返回 false。
  bool setActiveById(String id) {
    final t = _themes[id];
    if (t == null) return false;
    activeTheme = t;
    return true;
  }

  /// 活跃主题；未设置时返回第一个已注册主题。
  ThemeDescriptor? get activeOrFirst {
    if (_active != null) return _active;
    if (_themes.isNotEmpty) return _themes.values.first;
    return null;
  }
}

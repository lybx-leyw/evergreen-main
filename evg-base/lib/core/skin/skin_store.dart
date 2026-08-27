/// 皮肤包存储器——收集 [SkinDescriptor] + 响应式活跃皮肤切换。
///
/// # [SkinStore] — 响应式皮肤包容器
///
/// | 方法 / getter | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `register(s)` | `SkinDescriptor` | `void` | 注册皮肤包；同 id 后者覆盖 |
/// | `all` | — | `List<SkinDescriptor>` | 全部已注册皮肤包 |
/// | `findById(id)` | `String` | `SkinDescriptor?` | 按 id 查找 |
/// | `activeSkin` | — | `SkinDescriptor?` | 当前活跃皮肤包 |
/// | `activeSkin=` | `SkinDescriptor?` | `void` | 设置活跃皮肤包→通知监听者 |
/// | `setActiveById(id)` | `String` | `bool` | 按 id 切换；不存在返回 false |
/// | `activeOrFirst` | — | `SkinDescriptor?` | 活跃皮肤包或第一个已注册皮肤包 |
///
/// 逐行镜像 [ThemeStore]（core/theme），使皮肤切换与主题切换共享同一套
/// ChangeNotifier 响应式链路（设置面板切换 → provider 通知 → AI 视图重建）。
library;

import 'package:flutter/foundation.dart';
import 'skin_descriptor.dart';

/// 响应式皮肤包存储器。
///
/// 继承 [ChangeNotifier]：设置 [activeSkin] 时触发 [notifyListeners]。
class SkinStore extends ChangeNotifier {
  final Map<String, SkinDescriptor> _skins = {};
  SkinDescriptor? _active;

  // ═══════ 注册 ═══════

  /// 注册皮肤包。同 id 则覆盖（后者优先）。
  void register(SkinDescriptor skin) {
    _skins[skin.id] = skin;
  }

  /// 全部已注册皮肤包。
  List<SkinDescriptor> get all => List.unmodifiable(_skins.values);

  /// 按 id 查找。
  SkinDescriptor? findById(String id) => _skins[id];

  // ═══════ 活跃皮肤包 ═══════

  /// 当前活跃皮肤包。未设置返回 null。
  SkinDescriptor? get activeSkin => _active;

  /// 设置活跃皮肤包并通知全部监听者。
  set activeSkin(SkinDescriptor? skin) {
    if (_active?.id == skin?.id) return; // 同皮肤包不重复通知
    _active = skin;
    notifyListeners();
  }

  /// 按 id 切换活跃皮肤包。成功返回 true，不存在返回 false。
  bool setActiveById(String id) {
    final s = _skins[id];
    if (s == null) return false;
    activeSkin = s;
    return true;
  }

  /// 活跃皮肤包；未设置时返回第一个已注册皮肤包。
  SkinDescriptor? get activeOrFirst {
    if (_active != null) return _active;
    if (_skins.isNotEmpty) return _skins.values.first;
    return null;
  }
}

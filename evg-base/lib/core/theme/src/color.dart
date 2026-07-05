/// 主题颜色值对象——封装 ARGB int value，与 Flutter `dart:ui` Color 保持 value 语义兼容。
///
/// # [ThemeColor] — 颜色
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ThemeColor(value)` | `int` | `ThemeColor` | 0xAARRGGBB 格式 |
/// | `ThemeColor.fromHex(hex)` | `String` | `ThemeColor` | `#1677FF` 或 `#FF1677FF` |
/// | `tryParse(hex)` | `String` | `ThemeColor?` | 解析失败返回 null |
/// | `toHex()` | — | `String` | 转为 `#AARRGGBB` |
library;

/// 主题颜色——ARGB 32 位值对象。
class ThemeColor {
  /// 32 位 ARGB 颜色值（0xAARRGGBB）。
  final int value;

  /// 0xAARRGGBB 格式构造。
  const ThemeColor(this.value);

  // ═══ hex ═══

  /// 从 hex 字符串创建（`#1677FF` → `0xFF1677FF`，`#FF1677FF` → `0xFF1677FF`）。
  ///
  /// 支持格式：`#RGB` / `#RRGGBB` / `#AARRGGBB`。
  factory ThemeColor.fromHex(String hex) {
    final c = tryParse(hex);
    if (c == null) throw FormatException('非法颜色格式: $hex');
    return c;
  }

  /// 安全解析 hex 字符串。格式不符返回 null。
  static ThemeColor? tryParse(String hex) {
    if (hex.isEmpty || hex[0] != '#') return null;

    var h = hex.substring(1);
    final len = h.length;

    int r, g, b, a = 0xFF;

    try {
      if (len == 3) {
        // #RGB → #FFRRGGBB
        r = int.parse('${h[0]}${h[0]}', radix: 16);
        g = int.parse('${h[1]}${h[1]}', radix: 16);
        b = int.parse('${h[2]}${h[2]}', radix: 16);
      } else if (len == 6) {
        r = int.parse(h.substring(0, 2), radix: 16);
        g = int.parse(h.substring(2, 4), radix: 16);
        b = int.parse(h.substring(4, 6), radix: 16);
      } else if (len == 8) {
        a = int.parse(h.substring(0, 2), radix: 16);
        r = int.parse(h.substring(2, 4), radix: 16);
        g = int.parse(h.substring(4, 6), radix: 16);
        b = int.parse(h.substring(6, 8), radix: 16);
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }

    return ThemeColor((a << 24) | (r << 16) | (g << 8) | b);
  }

  /// 转为 `#AARRGGBB` 格式。
  String toHex({bool withAlpha = true}) {
    final a = (value >> 24) & 0xFF;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    if (withAlpha) {
      return '#${_h(a)}${_h(r)}${_h(g)}${_h(b)}';
    }
    return '#${_h(r)}${_h(g)}${_h(b)}';
  }

  static String _h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  // ═══ Object ═══

  @override
  bool operator ==(Object other) =>
      other is ThemeColor && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ThemeColor(${toHex()})';
}

/// Flutter widgets stub — 提供 [IconData]、[Color]。
///
/// 实际使用时由主项目的 Flutter SDK 覆盖。

/// 图标标识（codepoint + 可选字体族）。
class IconData {
  final int codePoint;
  final String? fontFamily;

  const IconData(this.codePoint, {this.fontFamily});
}

/// ARGB 颜色值。
class Color {
  final int value;
  const Color(this.value);

  @override
  bool operator ==(Object other) =>
      other is Color && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Color(0x${value.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

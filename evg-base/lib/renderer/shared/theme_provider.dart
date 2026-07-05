/// 主题解析——将 [ThemeDescriptor] 转换为 Material [ThemeData] + 组件 Token 扩展。
///
/// 公开类：[ComponentTokens]、[ThemeTokensExtension]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'renderer_providers.dart';

/// 组件级 Token 存储——按组件名 + key 查找颜色覆盖。
///
/// 由 [ThemeDescriptor.componentTokens] 填充，在 widget build 时通过
/// [ThemeTokensExtension.componentColor] 访问。
class ComponentTokens {
  const ComponentTokens._(this._data);

  final Map<String, Map<String, String>> _data;

  /// 空 tokens（无任何覆盖）。
  static const empty = ComponentTokens._({});

  /// 从 [ThemeDescriptor.componentTokens] 构建。
  factory ComponentTokens.fromDescriptor(ThemeDescriptor descriptor) {
    return ComponentTokens._(descriptor.componentTokens);
  }

  /// 获取指定组件的颜色 token。未找到返回 null。
  Color? color(String component, String key, {required BuildContext context}) {
    final hex = _data[component]?[key];
    if (hex == null) return null;
    return _hexToColor(hex);
  }

  /// 将 hex 字符串（如 "#1677FF"）转换为 [Color]。
  static Color _hexToColor(String hex) {
    final sanitized = hex.replaceFirst('#', '');
    final intVal = int.parse(
      sanitized.length == 6 ? 'FF$sanitized' : sanitized,
      radix: 16,
    );
    return Color(intVal);
  }
}

/// 为主题描述符中的语义 token 生成 [ThemeData]。
///
/// 语义 token：primary, secondary, background, surface, error,
/// success, warning, text, textSecondary, border, shadow, overlay。
ThemeData buildThemeFromDescriptor(ThemeDescriptor descriptor) {
  final s = descriptor.semanticTokens;
  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _parseHex(s['primary'] ?? '#1677FF'),
    onPrimary: _parseHex(s['onPrimary'] ?? '#FFFFFF'),
    secondary: _parseHex(s['secondary'] ?? '#52C41A'),
    onSecondary: _parseHex(s['onSecondary'] ?? '#FFFFFF'),
    error: _parseHex(s['error'] ?? '#CF222E'),
    onError: _parseHex(s['onError'] ?? '#FFFFFF'),
    surface: _parseHex(s['surface'] ?? '#FFFFFF'),
    onSurface: _parseHex(s['text'] ?? '#1A1D21'),
    outline: _parseHex(s['border'] ?? '#D0D5DD'),
    shadow: _parseHex(s['shadow'] ?? '#000000'),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: _parseHex(s['background'] ?? '#F5F5F5'),
    // 扩展 Token（非标准 ColorScheme 字段，通过 ThemeData 扩展传播）
    extensions: [
      _EvergreenColors(
        textSecondary: _parseHex(s['textSecondary'] ?? '#6B7280'),
        overlay: _parseHex(s['overlay'] ?? '#000000'),
        success: _parseHex(s['success'] ?? '#2DA44E'),
        warning: _parseHex(s['warning'] ?? '#FA8C16'),
      ),
    ],
  );
}

/// 非标准语义 Token——通过 ThemeData.extensions 下发。
class _EvergreenColors extends ThemeExtension<_EvergreenColors> {
  final Color textSecondary;
  final Color overlay;
  final Color success;
  final Color warning;

  const _EvergreenColors({
    required this.textSecondary,
    required this.overlay,
    required this.success,
    required this.warning,
  });

  @override
  _EvergreenColors copyWith({
    Color? textSecondary,
    Color? overlay,
    Color? success,
    Color? warning,
  }) {
    return _EvergreenColors(
      textSecondary: textSecondary ?? this.textSecondary,
      overlay: overlay ?? this.overlay,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  _EvergreenColors lerp(covariant _EvergreenColors? other, double t) {
    if (other == null) return this;
    return _EvergreenColors(
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

/// 从 [ThemeData] 读取非标准语义 Token。
extension EvergreenColorsX on ThemeData {
  Color get evergreenTextSecondary =>
      extension<_EvergreenColors>()?.textSecondary ?? const Color(0xFF6B7280);
  Color get evergreenOverlay =>
      extension<_EvergreenColors>()?.overlay ?? const Color(0x80000000);
  Color get evergreenSuccess =>
      extension<_EvergreenColors>()?.success ?? const Color(0xFF2DA44E);
  Color get evergreenWarning =>
      extension<_EvergreenColors>()?.warning ?? const Color(0xFFFA8C16);
}

/// 解析 hex 字符串为 [Color]。格式 "#RRGGBB" 或 "#AARRGGBB"。
Color _parseHex(String hex) {
  final sanitized = hex.replaceFirst('#', '');
  final intVal = int.parse(
    sanitized.length == 6 ? 'FF$sanitized' : sanitized,
    radix: 16,
  );
  return Color(intVal);
}

// ═══════ ThemeTokensExtension ═══════

/// [BuildContext] 扩展——便捷访问组件级 Token 颜色。
extension ThemeTokensExtension on BuildContext {
  /// 获取指定组件的 Token 颜色。未找到返回 null。
  Color? componentColor(String component, String key) {
    final tokens = _ComponentTokensScope.of(this);
    return tokens?.color(component, key, context: this);
  }
}

// ═══════ _ComponentTokensScope ═══════

/// 通过 [InheritedWidget] 下发 [ComponentTokens]。
class _ComponentTokensScope extends InheritedWidget {
  const _ComponentTokensScope({
    required this.tokens,
    required super.child,
  });

  final ComponentTokens? tokens;

  static ComponentTokens? of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_ComponentTokensScope>();
    return scope?.tokens;
  }

  @override
  bool updateShouldNotify(covariant _ComponentTokensScope oldWidget) {
    return tokens != oldWidget.tokens;
  }
}

/// 向子树注入 [ComponentTokens]。
Widget wrapWithComponentTokens({
  required ComponentTokens tokens,
  required Widget child,
}) {
  return _ComponentTokensScope(tokens: tokens, child: child);
}

/// 主题解析——五层画布 → Material [ThemeData] + 分层 InheritedWidget 下发。
///
/// 公开类：[LayerThemeData], [LayerThemeScope], [LayerThemeExtension]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'renderer_providers.dart';

// ═══════ LayerThemeData ═══════

/// 单层画布的解析后颜色数据。
///
/// 将 [LayerTokens] (Map<String, Map<String, String>>) 解析为
/// 组件名 → 子 token → [Color] 的嵌套结构，供渲染层直接查询。
class LayerThemeData {
  /// 组件名 → 子 token → Color。
  final Map<String, Map<String, Color>> components;

  const LayerThemeData._(this.components);

  /// 空主题。
  static const empty = LayerThemeData._({});

  /// 从 [LayerTokens] 构建。
  factory LayerThemeData.fromTokens(LayerTokens? tokens) {
    if (tokens == null) return empty;
    final components = <String, Map<String, Color>>{};
    for (final entry in tokens.entries) {
      final subMap = <String, Color>{};
      for (final se in entry.value.entries) {
        final color = _parseHex(se.value);
        if (color != null) subMap[se.key] = color;
      }
      if (subMap.isNotEmpty) components[entry.key] = subMap;
    }
    return LayerThemeData._(components);
  }

  /// 获取指定组件的子 token 颜色。未找到返回 null。
  Color? color(String component, String subToken) {
    return components[component]?[subToken];
  }

  /// 合并覆盖——[override_] 中的值覆盖本级。
  LayerThemeData merge(LayerTokens? override_) {
    if (override_ == null || override_.isEmpty) return this;
    final merged = <String, Map<String, Color>>{};
    // 复制原有
    for (final e in components.entries) {
      merged[e.key] = Map<String, Color>.from(e.value);
    }
    // 覆盖
    for (final e in override_.entries) {
      final compName = e.key;
      final compColors = merged.putIfAbsent(compName, () => <String, Color>{});
      for (final se in e.value.entries) {
        final color = _parseHex(se.value);
        if (color != null) compColors[se.key] = color;
      }
    }
    return LayerThemeData._(merged);
  }

  @override
  String toString() => 'LayerThemeData(${components.length} components)';
}

// ═══════ 五层 ThemeData 构建 ═══════

/// 从 [ThemeDescriptor] 构建 App 壳层 [ThemeData]。
///
/// 此主题用于 MaterialApp.router 的 `theme`/`darkTheme` 参数。
/// 包含基本的 Material colorScheme（从 app 层 sidebar + header 推导）。
ThemeData buildAppThemeFromDescriptor(ThemeDescriptor descriptor,
    {Brightness brightness = Brightness.light}) {
  final sidebar = descriptor.app['sidebar'] ?? {};
  final blank = descriptor.app['blank'] ?? {};

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: _hex(sidebar['active'] ?? '#1677FF'),
    onPrimary: _hex('#FFFFFF'),
    secondary: _hex('#52C41A'),
    onSecondary: _hex('#FFFFFF'),
    error: _hex('#CF222E'),
    onError: _hex('#FFFFFF'),
    surface: _hex(brightness == Brightness.dark ? '#161B22' : '#FFFFFF'),
    onSurface: _hex(brightness == Brightness.dark ? '#E6EDF3' : '#1A1D21'),
    outline: _hex(brightness == Brightness.dark ? '#30363D' : '#D0D5DD'),
    shadow: _hex('#000000'),
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor:
        _hex(blank['bg'] ?? (brightness == Brightness.dark ? '#0D1117' : '#F5F5F5')),
  );
}

// ═══════ 分层 InheritedWidget ═══════

/// 向子树注入单层 [LayerThemeData]。
class LayerThemeScope extends InheritedWidget {
  final String layerName;
  final LayerThemeData data;

  const LayerThemeScope({
    super.key,
    required this.layerName,
    required this.data,
    required super.child,
  });

  /// 从 context 读取指定层的 [LayerThemeData]。
  static LayerThemeData? of(BuildContext context, String layerName) {
    final scope = _findScope(context, layerName);
    return scope?.data;
  }

  static LayerThemeScope? _findScope(BuildContext context, String layerName) {
    LayerThemeScope? result;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is LayerThemeScope && widget.layerName == layerName) {
        result = widget;
        return false; // stop
      }
      return true;
    });
    return result;
  }

  @override
  bool updateShouldNotify(LayerThemeScope old) {
    return layerName != old.layerName || data != old.data;
  }
}

// ═══════ LayerTheme 构建者 ═══════

/// 从 [ThemeDescriptor] + 可选覆盖构建完整的五层 LayerThemeData。
class LayerThemeBuilder {
  final ThemeDescriptor descriptor;

  /// 模块级覆盖（来自 manifest.json module.theme）。
  final Map<String, Map<String, String>>? moduleOverride;

  /// 页面级覆盖（来自 manifest.json page.theme）。
  final Map<String, Map<String, String>>? pageOverride;

  /// Slot 级覆盖（来自 manifest.json slot.theme）。
  final Map<String, Map<String, String>>? slotOverride;

  /// 组件级覆盖（来自 manifest.json component.theme）。
  final Map<String, Map<String, String>>? componentOverride;

  const LayerThemeBuilder({
    required this.descriptor,
    this.moduleOverride,
    this.pageOverride,
    this.slotOverride,
    this.componentOverride,
  });

  LayerThemeData get appLayer =>
      LayerThemeData.fromTokens(descriptor.app);

  LayerThemeData get moduleLayer =>
      LayerThemeData.fromTokens(descriptor.module).merge(moduleOverride);

  LayerThemeData get pageLayer =>
      LayerThemeData.fromTokens(descriptor.page).merge(pageOverride);

  LayerThemeData get slotLayer =>
      LayerThemeData.fromTokens(descriptor.slot).merge(slotOverride);

  LayerThemeData get componentsLayer =>
      LayerThemeData.fromTokens(descriptor.components).merge(componentOverride);
}

// ═══════ BuildContext 扩展 ═══════

/// [BuildContext] 便捷访问分层主题颜色。
extension LayerThemeExtension on BuildContext {
  /// 获取 App 层指定组件的子 token 颜色。
  Color? appColor(String component, String subToken) {
    return LayerThemeScope.of(this, 'app')?.color(component, subToken);
  }

  /// 获取 Module 层指定组件的子 token 颜色。
  Color? moduleColor(String component, String subToken) {
    return LayerThemeScope.of(this, 'module')?.color(component, subToken);
  }

  /// 获取 Page 层指定组件的子 token 颜色。
  Color? pageColor(String component, String subToken) {
    return LayerThemeScope.of(this, 'page')?.color(component, subToken);
  }

  /// 获取 Slot 层指定组件的子 token 颜色。
  Color? slotColor(String component, String subToken) {
    return LayerThemeScope.of(this, 'slot')?.color(component, subToken);
  }

  /// 获取 Component 层指定组件的子 token 颜色。
  Color? componentColor(String component, String subToken) {
    return LayerThemeScope.of(this, 'components')?.color(component, subToken);
  }
}

// ═══════ 辅助 ═══════

/// 安全解析 hex 颜色字符串，失败返回 null。
///
/// 能处理标准 hex 格式 (#RGB / #RRGGBB / #AARRGGBB)。
/// 对于非单色值（如 chart.colors 逗号分隔列表）安全返回 null。
Color? _parseHex(String hex) {
  try {
    final sanitized = hex.replaceFirst('#', '');
    // 拒绝多值 token（如 chart.colors 的逗号分隔列表）
    if (sanitized.contains(',')) return null;
    final intVal = int.parse(
      sanitized.length == 6 ? 'FF$sanitized' : sanitized,
      radix: 16,
    );
    return Color(intVal);
  } catch (_) {
    return null;
  }
}

/// 严格解析 hex 颜色——非法输入直接抛 [FormatException]。
///
/// 用于 [buildAppThemeFromDescriptor] 等必须提供合法颜色的场景。
Color _parseHexOrThrow(String hex) {
  final sanitized = hex.replaceFirst('#', '');
  if (sanitized.contains(',')) {
    throw FormatException('Not a single hex color: "$hex"');
  }
  final intVal = int.parse(
    sanitized.length == 6 ? 'FF$sanitized' : sanitized,
    radix: 16,
  );
  return Color(intVal);
}

Color? _parseHexNullable(String hex) {
  try {
    return _parseHexOrThrow(hex);
  } catch (_) {
    return null;
  }
}

Color _hex(String hex) => _parseHexOrThrow(hex);

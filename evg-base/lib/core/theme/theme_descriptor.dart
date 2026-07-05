/// 主题描述符——从 theme.json 解析。
///
/// # [ThemeDescriptor] — 主题声明
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ThemeDescriptor(...)` | 各字段 | `ThemeDescriptor` | const 构造 |
/// | `ThemeDescriptor.fromJson(json)` | `Map<String,dynamic>` | `ThemeDescriptor` | theme.json 解析；校验 `type=="theme"` |
/// | `ThemeDescriptor.fromJsonString(str)` | `String` | `ThemeDescriptor` | JSON 字符串解析 |
/// | `toJson()` | — | `Map<String,dynamic>` | 序列化回 JSON |
/// | `semantic(key)` | `String` | `String?` | 获取语义 token 原始 hex |
/// | `component(name)` | `String` | `Map<String,String>?` | 获取组件 token 映射 |
/// | `semanticColor(key)` | `String` | `ThemeColor?` | 语义 token → 颜色对象 |
/// | `componentColor(c,t)` | `String`,`String` | `ThemeColor?` | 组件 token → 颜色对象 |
/// | `parseHex(hex)` | `String` | `ThemeColor?` | hex 字符串 → 颜色对象 |
library;

import 'dart:convert';
import 'dart:io' show stderr;
import 'src/color.dart';
import 'src/tokens.dart';

/// 主题描述符——全局配色方案。
///
/// 语义 token 定义通用颜色角色（20 个）。组件 token 覆盖特定 UI 组件（54 个）。
/// 下游渲染层按 token 名将颜色应用到对应位置。
class ThemeDescriptor {
  /// 唯一标识，如 "ocean_blue"。
  final String id;

  /// 展示名称，如 "海洋蓝"。
  final String name;

  /// 语义 token——20 个通用颜色角色。
  final Map<String, String> semanticTokens;

  /// 组件 token——54 个组件的子 token 颜色映射。
  final Map<String, Map<String, String>> componentTokens;

  const ThemeDescriptor({
    required this.id,
    required this.name,
    this.semanticTokens = const {},
    this.componentTokens = const {},
  });

  // ═══════ 字符串查询 ═══════

  /// 获取语义 token 原始 hex 字符串。未声明则返回 null。
  String? semantic(String key) => semanticTokens[key];

  /// 获取组件 token 的颜色映射。未声明则返回 null。
  Map<String, String>? component(String name) => componentTokens[name];

  // ═══════ 颜色对象查询 ═══════

  /// 获取语义 token 的 [ThemeColor]。未声明或格式非法返回 null。
  ThemeColor? semanticColor(String key) {
    final hex = semanticTokens[key];
    if (hex == null) return null;
    return ThemeColor.tryParse(hex);
  }

  /// 获取语义 token 的 [ThemeColor]，未命中则返回 [fallback]。
  ThemeColor semanticColorOr(String key, ThemeColor fallback) {
    return semanticColor(key) ?? fallback;
  }

  /// 获取组件 token 的 [ThemeColor]。未声明或格式非法返回 null。
  ThemeColor? componentColor(String componentName, String token) {
    final map = componentTokens[componentName];
    if (map == null) return null;
    final hex = map[token];
    if (hex == null) return null;
    return ThemeColor.tryParse(hex);
  }

  /// 获取组件 token 的 [ThemeColor]，未命中则返回 [fallback]。
  ThemeColor componentColorOr(String componentName, String token, ThemeColor fallback) {
    return componentColor(componentName, token) ?? fallback;
  }

  /// hex 字符串 → [ThemeColor]。格式非法返回 null。
  static ThemeColor? parseHex(String hex) => ThemeColor.tryParse(hex);

  // ═══════ JSON ═══════

  factory ThemeDescriptor.fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String?;
    if (t != 'theme') throw FormatException('type 必须为 "theme"，实际 "$t"');

    final colors = json['colors'] as Map<String, dynamic>? ?? {};

    // 语义 token：字符串值
    final semantic = <String, String>{};
    // 组件 token：嵌套对象值
    final components = <String, Map<String, String>>{};

    for (final entry in colors.entries) {
      if (entry.value is String) {
        semantic[entry.key] = entry.value as String;
      } else if (entry.value is Map<String, dynamic>) {
        components[entry.key] =
            (entry.value as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
      }
    }

    // ── 校验（非阻断：仅 stderr 警告） ──
    _warnUnknown(semantic, components, json['id'] as String? ?? '?');
    _warnBadColors(semantic, components, json['id'] as String? ?? '?');

    return ThemeDescriptor(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      semanticTokens: semantic,
      componentTokens: components,
    );
  }

  factory ThemeDescriptor.fromJsonString(String str) =>
      ThemeDescriptor.fromJson(jsonDecode(str) as Map<String, dynamic>);

  Map<String, dynamic> toJson() {
    final colors = <String, dynamic>{};
    colors.addAll(semanticTokens);
    colors.addAll(componentTokens);
    return {
      'type': 'theme',
      'id': id,
      'name': name,
      'colors': colors,
    };
  }

  // ═══════ 校验 ═══════

  /// 返回语义 token 中不在 20 规范列表中的未知 key。
  List<String> get unknownSemanticKeys {
    return semanticTokens.keys
        .where((k) => !SemanticTokens.allowedKeys.contains(k))
        .toList();
  }

  /// 返回组件 token 中不在 54 规范列表中的未知 key。
  List<String> get unknownComponentKeys {
    return componentTokens.keys
        .where((k) => !ComponentTokens.allowedKeys.contains(k))
        .toList();
  }

  /// 返回颜色值格式非法的条目 (key, hex)。
  ///
  /// 语义 token 全部视为颜色；组件 token 中已知的非颜色子 token（如
  /// `divider.thickness`、`chart.colors`）会被跳过。
  List<MapEntry<String, String>> get invalidColors {
    final bad = <MapEntry<String, String>>[];
    for (final e in semanticTokens.entries) {
      if (!isValidHexColor(e.value)) bad.add(e);
    }
    for (final e in componentTokens.entries) {
      final nonColor = _nonColorSubTokens(e.key);
      for (final se in e.value.entries) {
        if (nonColor.contains(se.key)) continue;
        if (!isValidHexColor(se.value)) bad.add(MapEntry('${e.key}.${se.key}', se.value));
      }
    }
    return bad;
  }

  @override
  String toString() => 'ThemeDescriptor($id, $name)';
}

// ═══════ 内部校验（non‑blocking warnings） ═══════

/// 对语义/组件 token 中不在白名单的 key 输出 stderr 警告。
void _warnUnknown(
  Map<String, String> semantic,
  Map<String, Map<String, String>> components,
  String themeId,
) {
  for (final k in semantic.keys) {
    if (!SemanticTokens.allowedKeys.contains(k) && !ComponentTokens.allowedKeys.contains(k)) {
      stderr.writeln('[theme] "$themeId": 未知 key "$k"（语义 token）——拼写错误？');
    }
  }
  for (final k in components.keys) {
    if (!ComponentTokens.allowedKeys.contains(k) && !SemanticTokens.allowedKeys.contains(k)) {
      stderr.writeln('[theme] "$themeId": 未知 key "$k"（组件 token）——拼写错误？');
    }
  }
}

/// 对颜色值格式非法的条目输出 stderr 警告（跳过已知非颜色子 token，如 thickness）。
void _warnBadColors(
  Map<String, String> semantic,
  Map<String, Map<String, String>> components,
  String themeId,
) {
  // 语义 token 必须全部为合法颜色
  for (final e in semantic.entries) {
    if (!isValidHexColor(e.value)) {
      stderr.writeln('[theme] "$themeId": 语义 token "${e.key}"="${e.value}" 颜色格式非法');
    }
  }
  // 组件 token：跳过已知非颜色子 token
  for (final e in components.entries) {
    final nonColorSubs = _nonColorSubTokens(e.key);
    for (final se in e.value.entries) {
      if (nonColorSubs.contains(se.key)) continue;
      if (!isValidHexColor(se.value)) {
        stderr.writeln('[theme] "$themeId": 组件 token "${e.key}.${se.key}"="${se.value}" 颜色格式非法');
      }
    }
  }
}

/// 返回指定组件中已知存储非颜色值（尺寸、数组、布尔等）的子 token。
Set<String> _nonColorSubTokens(String component) {
  const map = <String, Set<String>>{
    'divider': {'thickness'},
    'chart': {'colors'}, // 数组型 palette，非单一 hex
  };
  return map[component] ?? const <String>{};
}

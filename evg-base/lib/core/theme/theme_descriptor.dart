/// 主题描述符——五层画布架构。
///
/// # [ThemeDescriptor] —— 主题声明（V2 五层模型）
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ThemeDescriptor(...)` | 各字段 | `ThemeDescriptor` | const 构造 |
/// | `ThemeDescriptor.fromJson(json)` | `Map<String,dynamic>` | `ThemeDescriptor` | theme.json 解析；校验 `type=="theme"` |
/// | `ThemeDescriptor.fromJsonString(str)` | `String` | `ThemeDescriptor` | JSON 字符串解析 |
/// | `toJson()` | — | `Map<String,dynamic>` | 序列化回 JSON |
///
/// # 五层画布
///
/// | 层 | JSON key | 说明 |
/// |----|----------|------|
/// | App 壳 | `"app"` | sidebar, header, footer, blank, commandPalette |
/// | Module 壳 | `"module"` | chrome |
/// | Page 级 | `"page"` | tabBar, background |
/// | Slot 框 | `"slot"` | header, background, border |
/// | 组件 | `"components"` | 54 组件 |
///
/// # 层 Token 数据
///
/// 所有层数据统一为 `Map<String, Map<String, String>>` 结构：
/// - 外层 key = 组件名（如 `"sidebar"`, `"button"`）
/// - 内层 key = 子 token（如 `"bg"`, `"text"`）
/// - 值 = hex 颜色字符串（如 `"#1677FF"`）
library;

import 'dart:convert';
import 'dart:io' show stderr;
import 'src/color.dart';
import 'src/tokens.dart' as t;

// ═══════ 层 Token 类型 ═══════

/// 层 Token Map：组件名 → 子 token Map。
typedef LayerTokens = Map<String, Map<String, String>>;

// ═══════ ThemeDescriptor ═══════

/// 主题描述符——五层画布配色方案。
///
/// 每层独立声明自己画布区域的颜色。各层正交，互不覆盖：
/// - App 层画 sidebar/header/footer/blank/commandPalette
/// - Module 层画模块 chrome
/// - Page 层画 tabBar/background
/// - Slot 层画 slot 框 header/background/border
/// - Components 层画 54 个组件内部内容
class ThemeDescriptor {
  /// 唯一标识，如 `"dark"`。
  final String id;

  /// 展示名称，如 `"深色"`。
  final String name;

  // ═══ 五层画布 ═══

  /// App 壳层 Token。
  final LayerTokens app;

  /// Module 壳层 Token。
  final LayerTokens module;

  /// Page 层 Token。
  final LayerTokens page;

  /// Slot 框层 Token。
  final LayerTokens slot;

  /// 54 组件 Token。
  final LayerTokens components;

  const ThemeDescriptor({
    required this.id,
    required this.name,
    required this.app,
    required this.module,
    required this.page,
    required this.slot,
    required this.components,
  });

  // ═══════ 查询 ═══════

  /// 获取某层某组件的子 token hex 值。未找到返回 null。
  String? tokenValue(LayerTokens layer, String component, String subToken) {
    return layer[component]?[subToken];
  }

  /// 获取某层某组件的子 token [ThemeColor]。未找到返回 null。
  ThemeColor? tokenColor(LayerTokens layer, String component, String subToken) {
    final hex = tokenValue(layer, component, subToken);
    if (hex == null) return null;
    return ThemeColor.tryParse(hex);
  }

  /// hex 字符串 → [ThemeColor]。
  static ThemeColor? parseHex(String hex) => ThemeColor.tryParse(hex);

  // ═══════ JSON ═══════

  factory ThemeDescriptor.fromJson(Map<String, dynamic> json) {
    final t_ = json['type'] as String?;
    if (t_ != 'theme') {
      throw FormatException('type 必须为 "theme"，实际 "$t_"');
    }

    final app = _parseLayer(json, 'app', t.AppTokens.allowedKeys);
    final module = _parseLayer(json, 'module', t.ModuleTokens.allowedKeys);
    final page = _parseLayer(json, 'page', t.PageTokens.allowedKeys);
    final slot = _parseLayer(json, 'slot', t.SlotTokens.allowedKeys);
    final components = _parseLayer(json, 'components', t.ComponentTokens.allowedKeys);

    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    // 校验：每层必须完整声明
    _validateLayer(app, 'app', t.AppTokens.subTokens, id);
    _validateLayer(module, 'module', t.ModuleTokens.subTokens, id);
    _validateLayer(page, 'page', t.PageTokens.subTokens, id);
    _validateLayer(slot, 'slot', t.SlotTokens.subTokens, id);
    _validateLayer(components, 'components', t.ComponentTokens.subTokens, id);

    return ThemeDescriptor(
      id: id,
      name: name,
      app: app,
      module: module,
      page: page,
      slot: slot,
      components: components,
    );
  }

  factory ThemeDescriptor.fromJsonString(String str) =>
      ThemeDescriptor.fromJson(jsonDecode(str) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
    'type': 'theme',
    'id': id,
    'name': name,
    'app': _layerToJson(app),
    'module': _layerToJson(module),
    'page': _layerToJson(page),
    'slot': _layerToJson(slot),
    'components': _layerToJson(components),
  };

  @override
  String toString() => 'ThemeDescriptor($id, $name)';
}

// ═══════ 解析辅助 ═══════

/// 解析 JSON 中指定 layer 的组件 Token Map。
///
/// 要求 [json] 中 `layerKey` 字段必须存在且为 Map。
LayerTokens _parseLayer(
  Map<String, dynamic> json,
  String layerKey,
  Set<String> allowedKeys,
) {
  final raw = json[layerKey];
  if (raw == null) {
    throw FormatException('缺少必填层 "$layerKey"');
  }
  if (raw is! Map<String, dynamic>) {
    throw FormatException('层 "$layerKey" 必须是对象');
  }

  final result = <String, Map<String, String>>{};
  for (final entry in raw.entries) {
    final componentKey = entry.key.toString();
    if (entry.value is Map) {
      final subMap = <String, String>{};
      for (final se in (entry.value as Map).entries) {
        subMap[se.key.toString()] = se.value.toString();
      }
      result[componentKey] = subMap;
    } else {
      throw FormatException(
        '层 "$layerKey" 中 "$componentKey" 必须是对象（子 token Map）',
      );
    }
  }

  return result;
}

/// 将 [LayerTokens] 序列化为 JSON 友好结构。
Map<String, dynamic> _layerToJson(LayerTokens layer) {
  return layer.map((k, v) => MapEntry(k, v));
}

// ═══════ 校验 ═══════

/// 校验某层是否完整声明所有必要组件和子 token。
///
/// 规则：
/// 1. 层必须存在所有规范组件 key
/// 2. 每个组件必须含有所有规范子 token
/// 3. 颜色值必须合法
void _validateLayer(
  LayerTokens layer,
  String layerKey,
  Map<String, Set<String>> requiredSubTokens,
  String themeId,
) {
  for (final entry in requiredSubTokens.entries) {
    final componentKey = entry.key;
    final requiredTokens = entry.value;

    final component = layer[componentKey];
    if (component == null) {
      throw FormatException(
        '主题 "$themeId" 层 "$layerKey" 缺少必填组件 "$componentKey"',
      );
    }

    for (final subToken in requiredTokens) {
      final value = component[subToken];
      if (value == null) {
        throw FormatException(
          '主题 "$themeId" 层 "$layerKey" 组件 "$componentKey" '
          '缺少必填子 token "$subToken"',
        );
      }
      // 检查颜色格式（跳过非颜色子 token）
      if (!_isNonColorToken(componentKey, subToken) && !isValidHexColor(value)) {
        stderr.writeln(
          '[theme] "$themeId": 层 "$layerKey" 组件 '
          '"$componentKey.$subToken"="$value" 颜色格式非法',
        );
      }
    }
  }
}

/// 判断是否为非颜色子 token（如 `thickness`、`width` 等尺寸值）。
bool _isNonColorToken(String component, String subToken) {
  const nonColor = <String, Set<String>>{
    'divider': {'thickness', 'width'},
    'border': {'width'},
    'chart': {'colors'}, // 数组型 palette
  };
  return nonColor[component]?.contains(subToken) ?? false;
}

// ═══════ 导出 hex 校验 ═══════

/// 校验 hex 颜色字符串格式。
bool isValidHexColor(String? value) {
  if (value == null || value.isEmpty) return false;
  return RegExp(
    r'^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$',
  ).hasMatch(value);
}

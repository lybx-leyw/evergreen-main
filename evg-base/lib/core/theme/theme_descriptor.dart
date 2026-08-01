/// 主题描述符——扁平语义色板（8 字段）。
///
/// # [ThemeDescriptor] —— 主题声明（扁平语义色板）
///
/// | 工厂 / 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ThemeDescriptor(...)` | `id`, `name`, `colors` | `ThemeDescriptor` | const 构造 |
/// | `ThemeDescriptor.fromJson(json)` | `Map<String,dynamic>` | `ThemeDescriptor` | 解析；校验 `type=="theme"` 与 8 必填色 |
/// | `ThemeDescriptor.fromJsonString(str)` | `String` | `ThemeDescriptor` | JSON 字符串解析 |
/// | `toJson()` | — | `Map<String,dynamic>` | 序列化回 JSON |
///
/// # 8 个语义字段
///
/// | 字段 | 含义 | 映射到 ColorScheme |
/// |------|------|---------------------|
/// | `background`    | 页面主背景（scaffold） | scaffoldBackgroundColor |
/// | `surface`       | 卡片/面板底色 | surface |
/// | `border`        | 默认边框/分隔线 | outline |
/// | `text`          | 主文字 | onSurface |
/// | `textSecondary` | 次级/弱化文字 | onSurfaceVariant |
/// | `accent`        | 强调/品牌色 | primary |
/// | `error`         | 错误态 | error |
/// | `others`        | 其余所有非共用组件杂色 | secondary |
///
/// 字段范围由真实共享组件（57 个 `components/shared`）颜色消费文件覆盖数决定；
/// `secondary`/`tertiary`/`inverseSurface` 等无人消费的色统一归入 `others`。
library;

import 'dart:convert';
import 'src/color.dart';

// ═══════ 语义色板字段 ═══════

/// 扁平语义色板的字段名集合与兼容别名。
class ThemeColorKeys {
  ThemeColorKeys._();

  /// 页面主背景（scaffold）。
  static const background = 'background';

  /// 卡片/面板底色。
  static const surface = 'surface';

  /// 默认边框/分隔线。
  static const border = 'border';

  /// 主文字。
  static const text = 'text';

  /// 次级/弱化文字。
  static const textSecondary = 'textSecondary';

  /// 强调/品牌色。
  static const accent = 'accent';

  /// 错误态。
  static const error = 'error';

  /// 其余所有非共用组件杂色（单一字段渲染其余所有）。
  static const others = 'others';

  /// 全部必填字段。
  static const required = <String>{
    background,
    surface,
    border,
    text,
    textSecondary,
    accent,
    error,
    others,
  };

  /// 旧 theme.json 键名 → 新语义字段的兼容别名。
  static const alias = <String, String>{
    'primary': accent,
    'secondary': others,
  };
}

// ═══════ ThemeDescriptor ═══════

/// 主题描述符——扁平语义色板（8 字段）。
///
/// 单一 `colors` Map 描述整套配色，无五层/组件级嵌套。
class ThemeDescriptor {
  /// 唯一标识，如 `"dark"`。
  final String id;

  /// 展示名称，如 `"深色"`。
  final String name;

  /// 扁平语义色板：8 个固定 key → hex 颜色字符串。
  final Map<String, String> colors;

  const ThemeDescriptor({
    required this.id,
    required this.name,
    required this.colors,
  });

  // ═══════ 查询 ═══════

  /// 获取某语义字段的 hex 值。未找到返回 null。
  String? color(String key) => colors[key];

  /// hex 字符串 → [ThemeColor]。
  static ThemeColor? parseHex(String hex) => ThemeColor.tryParse(hex);

  // ═══════ JSON ═══════

  factory ThemeDescriptor.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type != 'theme') {
      throw FormatException('type 必须为 "theme"，实际 "$type"');
    }

    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    final raw = json['colors'];
    if (raw is! Map<String, dynamic>) {
      throw FormatException('缺少必填字段 "colors"（应为扁平颜色 Map）');
    }

    final colors = <String, String>{};
    for (final key in ThemeColorKeys.required) {
      // 先尝试本名，再尝试兼容别名（primary/secondary）
      final aliasKey = ThemeColorKeys.alias.entries
          .firstWhere(
            (e) => e.value == key,
            orElse: () => const MapEntry('', ''),
          )
          .key;
      final dynamic value =
          raw[key] ?? (aliasKey.isNotEmpty ? raw[aliasKey] : null);

      if (value == null) {
        throw FormatException('主题 "$id" 缺少必填颜色 "$key"');
      }
      final hex = value.toString();
      if (!isValidHexColor(hex)) {
        throw FormatException('主题 "$id" 颜色 "$key"="$hex" 格式非法');
      }
      colors[key] = hex;
    }

    return ThemeDescriptor(id: id, name: name, colors: colors);
  }

  factory ThemeDescriptor.fromJsonString(String str) =>
      ThemeDescriptor.fromJson(jsonDecode(str) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'type': 'theme',
        'id': id,
        'name': name,
        'colors': colors,
      };

  @override
  String toString() => 'ThemeDescriptor($id, $name)';
}

// ═══════ hex 校验 ═══════

/// 校验 hex 颜色字符串格式（#RGB / #RRGGBB / #AARRGGBB）。
bool isValidHexColor(String? value) {
  if (value == null || value.isEmpty) return false;
  return RegExp(
    r'^#[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$',
  ).hasMatch(value);
}

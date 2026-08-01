/// 主题草稿——扁平 8 色主题的可编辑模型。
///
/// 与 [ThemeDescriptor]（不可变）不同：草稿在创作中心内被就地编辑，
/// 校验通过后可导出为主题插件或转换为预览用 [ThemeDescriptor]。
library;

import 'package:evergreen_base/core/theme/theme_descriptor.dart';

/// 8 个语义色键（与 ThemeColorKeys.required 一致，独立声明避免耦合导入）。
const List<String> kThemeColorKeys = [
  'background',
  'surface',
  'border',
  'text',
  'textSecondary',
  'accent',
  'error',
  'others',
];

/// 语义键 → 中文名（编辑区标签）。
const Map<String, String> kThemeColorLabels = {
  'background': '页面背景',
  'surface': '卡片/面板底色',
  'border': '边框/分隔线',
  'text': '主文字',
  'textSecondary': '次级文字',
  'accent': '强调/品牌色',
  'error': '错误态',
  'others': '其余杂色',
};

/// 每个语义键的预设色板（快速取色）。
const Map<String, List<String>> kThemeColorPresets = {
  'background': ['#0D1117', '#FFFFFF', '#F6F8FA', '#0E1713', '#F0F4F8', '#1E1E2E'],
  'surface': ['#161B22', '#F6F8FA', '#FFFFFF', '#15231D', '#FFFFFF', '#2A2A3C'],
  'border': ['#30363D', '#D0D7DE', '#E5E7EB', '#2C4238', '#BBDEFB', '#3A3A4E'],
  'text': ['#C9D1D9', '#1F2328', '#111827', '#DCE8E1', '#1A2332', '#CDD6F4'],
  'textSecondary': ['#8B949E', '#656D76', '#6B7280', '#8FA99C', '#78909C', '#A6ADC8'],
  'accent': ['#58A6FF', '#0969DA', '#2563EB', '#3FB950', '#0D47A1', '#C792EA'],
  'error': ['#FF7B72', '#CF222E', '#EF4444', '#F85149', '#E53935', '#F38BA8'],
  'others': ['#8B949E', '#57606A', '#64748B', '#56D364', '#42A5F5', '#94E2D5'],
};

/// 主题草稿。
class ThemeDraft {
  /// 插件 id（snake_case，导出目录名）。
  String id;

  /// 展示名称。
  String name;

  /// 8 个语义键 → hex 颜色。
  Map<String, String> colors;

  ThemeDraft({
    required this.id,
    required this.name,
    Map<String, String>? colors,
  }) : colors = colors ?? {for (final k in kThemeColorKeys) k: '#000000'};

  /// 从 [ThemeDescriptor] 复制起点（内置主题起步）。
  factory ThemeDraft.fromDescriptor(ThemeDescriptor t) => ThemeDraft(
        id: '${t.id}_copy',
        name: '${t.name} 副本',
        colors: Map.of(t.colors),
      );

  /// 全部语义键是否已填。
  bool get hasAllColors =>
      kThemeColorKeys.every((k) => colors.containsKey(k) && colors[k]!.isNotEmpty);

  /// 全部颜色值是否为合法 hex。
  bool get allColorsValid =>
      hasAllColors && colors.values.every((v) => isValidHexColor(v));

  /// id 是否合法（snake_case 且不与内置主题冲突）。
  bool get idValid =>
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id) &&
      !const {'dark', 'light', 'default', 'evergreen'}.contains(id);

  /// 是否可导出（id 合法 + 8 色齐全合法）。
  bool get canExport => idValid && allColorsValid;

  /// 转为只读描述符（预览 / 导出共用）。
  ThemeDescriptor toDescriptor() => ThemeDescriptor(
        id: id,
        name: name,
        colors: Map.of(colors),
      );

  /// 草稿文件 JSON（id/name/colors）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colors': colors,
      };

  /// 从草稿 JSON 恢复。
  factory ThemeDraft.fromJson(Map<String, dynamic> json) => ThemeDraft(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        colors: (json['colors'] as Map?)?.cast<String, String>() ?? {},
      );

  @override
  String toString() => 'ThemeDraft($id, $name)';
}

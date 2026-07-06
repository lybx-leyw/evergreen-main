/// 插件清单——搜索结果中返回的轻量模型。
///
/// 与 [PluginDetail]（详情页完整信息）不同，[PluginManifest] 仅包含
/// 列表/搜索结果所需的摘要字段，体积更小、解析更快。
///
/// # 对应接口
///
/// - I10: [ModuleRegistry.search] 返回 `List<PluginManifest>`
library;

import 'capability.dart';

/// 插件清单——搜索/列表结果中的摘要信息。
///
/// 由 [ModuleRegistry.search] 返回，供渲染层市场搜索使用。
/// V2: icon 使用 int (codePoint)，不再依赖 Flutter IconData。
class PluginManifest {
  /// 全局唯一标识。
  final String id;

  /// 展示名称。
  final String name;

  /// 简短描述。
  final String description;

  /// 图标 codePoint。
  final int? icon;

  /// 具备的能力维度列表。
  final List<CapabilityDimension> dimensions;

  /// 分类标签（对应 sidebar section 或自定义分类）。
  final String category;

  /// 语义版本号（如 "1.0.0"）。
  final String version;

  const PluginManifest({
    required this.id,
    required this.name,
    this.description = '',
    this.icon,
    this.dimensions = const [],
    this.category = '',
    this.version = '0.0.0',
  });

  /// 从 [Map] 反序列化。
  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as int?,
      dimensions: (json['dimensions'] as List?)
              ?.map((d) => parseCapabilityDimension(d.toString()))
              .whereType<CapabilityDimension>()
              .toList() ??
          [],
      category: json['category'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
    );
  }

  /// 序列化为 [Map]。
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'name': name,
    };
    if (description.isNotEmpty) m['description'] = description;
    if (icon != null) m['icon'] = icon;
    if (dimensions.isNotEmpty) {
      m['dimensions'] = dimensions.map((d) => d.name).toList();
    }
    if (category.isNotEmpty) m['category'] = category;
    m['version'] = version;
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is PluginManifest && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PluginManifest($id, $name, v$version)';
}

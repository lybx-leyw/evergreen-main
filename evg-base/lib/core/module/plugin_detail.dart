/// 插件详情——详情页完整信息模型。
///
/// 相比 [PluginManifest]（搜索结果摘要），[PluginDetail] 包含截图、权限、
/// 开发者等详情页专属字段。
///
/// # 对应需求
///
/// - M-S2-3: 详情页数据模型（名称/描述/版本/截图/权限/维度/开发者）
library;

import 'capability.dart';

/// 插件详情——详情页展示的完整信息。
///
/// 用于 Marketplace 详情页渲染，包含安装决策所需的全部元数据。
class PluginDetail {
  /// 全局唯一标识。
  final String id;

  /// 展示名称。
  final String name;

  /// 详细描述（支持多段落）。
  final String description;

  /// 语义版本号（如 "1.2.3"）。
  final String version;

  /// 截图路径列表（相对插件目录）。
  final List<String> screenshots;

  /// 所需权限列表（如 "network"、"file_access"、"camera"）。
  final List<String> permissions;

  /// 具备的能力维度。
  final List<CapabilityDimension> dimensions;

  /// 开发者/组织名称。
  final String developer;

  /// 开发者联系方式（邮箱或 URL）。
  final String developerContact;

  /// 插件主页 URL。
  final String homepage;

  const PluginDetail({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '0.0.0',
    this.screenshots = const [],
    this.permissions = const [],
    this.dimensions = const [],
    this.developer = '',
    this.developerContact = '',
    this.homepage = '',
  });

  /// 从 [Map] 反序列化。
  factory PluginDetail.fromJson(Map<String, dynamic> json) {
    return PluginDetail(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      screenshots: (json['screenshots'] as List?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      permissions: (json['permissions'] as List?)
              ?.map((p) => p.toString())
              .toList() ??
          [],
      dimensions: (json['dimensions'] as List?)
              ?.map((d) => parseCapabilityDimension(d.toString()))
              .whereType<CapabilityDimension>()
              .toList() ??
          [],
      developer: json['developer'] as String? ?? '',
      developerContact: json['developerContact'] as String? ?? '',
      homepage: json['homepage'] as String? ?? '',
    );
  }

  /// 序列化为 [Map]。
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'name': name,
    };
    if (description.isNotEmpty) m['description'] = description;
    m['version'] = version;
    if (screenshots.isNotEmpty) m['screenshots'] = screenshots;
    if (permissions.isNotEmpty) m['permissions'] = permissions;
    if (dimensions.isNotEmpty) {
      m['dimensions'] = dimensions.map((d) => d.name).toList();
    }
    if (developer.isNotEmpty) m['developer'] = developer;
    if (developerContact.isNotEmpty) m['developerContact'] = developerContact;
    if (homepage.isNotEmpty) m['homepage'] = homepage;
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is PluginDetail && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PluginDetail($id, $name, v$version)';
}

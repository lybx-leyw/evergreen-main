/// HTML 插件项目模型 —— html-creator 的核心数据结构。
library;

/// 一个 HTML 插件项目。
class HtmlProject {
  /// 插件唯一标识（如 "my-dashboard"）。
  String pluginId;

  /// 插件显示名称。
  String pluginName;

  /// 图标标识（Material Icons 名称）。
  String? icon;

  /// 插件描述。
  String? description;

  /// HTML 源码内容。
  String htmlContent;

  /// 侧边栏导航分組。
  String navSection;

  /// 是否已修改（未保存标记）。
  bool dirty;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  DateTime updatedAt;

  HtmlProject({
    this.pluginId = '',
    this.pluginName = '未命名插件',
    this.icon,
    this.description,
    this.htmlContent = '',
    this.navSection = '自定义',
    this.dirty = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory HtmlProject.fromJson(Map<String, dynamic> json) => HtmlProject(
        pluginId: json['pluginId'] as String? ?? '',
        pluginName: json['pluginName'] as String? ?? '未命名插件',
        icon: json['icon'] as String?,
        description: json['description'] as String?,
        htmlContent: json['htmlContent'] as String? ?? '',
        navSection: json['navSection'] as String? ?? '自定义',
        dirty: json['dirty'] as bool? ?? false,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'pluginId': pluginId,
        'pluginName': pluginName,
        if (icon != null) 'icon': icon,
        if (description != null) 'description': description,
        'htmlContent': htmlContent,
        'navSection': navSection,
        'dirty': dirty,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  HtmlProject copyWith({
    String? pluginId,
    String? pluginName,
    String? icon,
    String? description,
    String? htmlContent,
    String? navSection,
  }) {
    return HtmlProject(
      pluginId: pluginId ?? this.pluginId,
      pluginName: pluginName ?? this.pluginName,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      htmlContent: htmlContent ?? this.htmlContent,
      navSection: navSection ?? this.navSection,
      dirty: true,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// 数据中枢中一个数据源的预览信息。
class DataSourcePreview {
  final String name;
  final String displayName;
  final String freshnessLabel;
  final bool connected;
  final dynamic cachedData;

  const DataSourcePreview({
    required this.name,
    required this.displayName,
    required this.freshnessLabel,
    required this.connected,
    this.cachedData,
  });
}

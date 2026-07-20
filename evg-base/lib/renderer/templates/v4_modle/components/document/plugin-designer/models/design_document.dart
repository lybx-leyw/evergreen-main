/// 编排文档模型 —— 插件设计器的核心数据结构。
///
/// 树形结构：DesignDocument → DesignPage[] → DesignSlot[] → DesignComponent
library;

import 'design_page.dart';

/// 侧边栏导航配置（对应 manifest 的 nav.sidebar）。
class DesignNav {
  /// 所属侧边栏分组（如 "通用"、"展示"）。
  final String section;

  /// 分组内排序权重。
  final int sectionOrder;

  /// 分组内的排序序号。
  final int order;

  /// 是否显示角标。
  final bool badge;

  const DesignNav({
    this.section = '通用',
    this.sectionOrder = 50,
    this.order = 50,
    this.badge = false,
  });

  factory DesignNav.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DesignNav();
    return DesignNav(
      section: json['section'] as String? ?? '通用',
      sectionOrder: json['sectionOrder'] as int? ?? 50,
      order: json['order'] as int? ?? 50,
      badge: json['badge'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'section': section,
        'sectionOrder': sectionOrder,
        'order': order,
        'badge': badge,
      };
}

/// 后端进程配置（对应 manifest 的 process[i]）。
class DesignProcess {
  /// 可执行文件路径（相对 module 目录）。
  final String exe;

  /// 通信协议（默认 http）。
  final String protocol;

  const DesignProcess({required this.exe, this.protocol = 'http'});

  factory DesignProcess.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DesignProcess(exe: '');
    return DesignProcess(
      exe: json['exe'] as String? ?? '',
      protocol: json['protocol'] as String? ?? 'http',
    );
  }

  Map<String, dynamic> toJson() => {
        'exe': exe,
        'protocol': protocol,
      };
}

/// 插件编排文档 —— 完整描述一个插件的页面/Slot/组件结构。
class DesignDocument {
  /// 插件唯一标识（如 "my-custom-plugin"）。
  final String pluginId;

  /// 插件显示名称。
  String pluginName;

  /// 图标标识（Material Icons 名称或自定义路径）。
  String? icon;

  /// 插件描述。
  String? description;

  /// 导航路由。
  String? route;

  /// 插件版本号（manifest V2 的 version 字段）。
  String version;

  /// 依赖的模块 ID 列表（manifest V2 的 dependencies 字段）。
  List<String> dependencies;

  /// 侧边栏导航配置（manifest V2 的 nav.sidebar）。
  DesignNav nav;

  /// 后端进程列表（manifest V2 的 process 字段）。
  List<DesignProcess> process;

  /// 页面列表。
  final List<DesignPage> pages;

  /// 元数据（版本、作者、依赖等）。
  final Map<String, dynamic> metadata;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  DateTime updatedAt;

  DesignDocument({
    required this.pluginId,
    this.pluginName = '未命名插件',
    this.icon,
    this.description,
    this.route,
    this.version = '1.0.0',
    List<String>? dependencies,
    DesignNav? nav,
    List<DesignProcess>? process,
    List<DesignPage>? pages,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : dependencies = dependencies ?? [],
        nav = nav ?? const DesignNav(),
        process = process ?? [],
        pages = pages ?? [],
        metadata = metadata ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory DesignDocument.fromJson(Map<String, dynamic> json) {
    return DesignDocument(
      pluginId: json['plugin_id'] as String? ?? '',
      pluginName: json['plugin_name'] as String? ?? '未命名插件',
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      route: json['route'] as String?,
      version: json['version'] as String? ?? '1.0.0',
      dependencies: (json['dependencies'] as List?)
              ?.map((d) => d.toString())
              .toList() ??
          [],
      nav: DesignNav.fromJson(json['nav'] as Map<String, dynamic>?),
      process: (json['process'] as List?)
              ?.map((p) =>
                  DesignProcess.fromJson(p as Map<String, dynamic>?))
              .toList() ??
          [],
      pages: (json['pages'] as List?)
              ?.map(
                  (e) => DesignPage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      metadata: _asMap(json['metadata']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'plugin_id': pluginId,
        'plugin_name': pluginName,
        if (icon != null) 'icon': icon,
        if (description != null) 'description': description,
        if (route != null) 'route': route,
        'version': version,
        if (dependencies.isNotEmpty) 'dependencies': dependencies,
        'nav': nav.toJson(),
        if (process.isNotEmpty)
          'process': process.map((p) => p.toJson()).toList(),
        'pages': pages.map((p) => p.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  DesignDocument copyWith({
    String? pluginId,
    String? pluginName,
    String? icon,
    String? description,
    String? route,
    String? version,
    List<String>? dependencies,
    DesignNav? nav,
    List<DesignProcess>? process,
    List<DesignPage>? pages,
    Map<String, dynamic>? metadata,
  }) {
    return DesignDocument(
      pluginId: pluginId ?? this.pluginId,
      pluginName: pluginName ?? this.pluginName,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      route: route ?? this.route,
      version: version ?? this.version,
      dependencies: dependencies ?? List<String>.from(this.dependencies),
      nav: nav ?? this.nav,
      process: process ?? List<DesignProcess>.from(this.process),
      pages: pages ?? List<DesignPage>.from(this.pages),
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
      createdAt: createdAt,
    );
  }

  /// 添加页面。
  void addPage(DesignPage page) => pages.add(page);

  /// 按 id 删除页面。
  void removePage(String pageId) => pages.removeWhere((p) => p.id == pageId);

  /// 查找页面。
  DesignPage? findPage(String pageId) {
    try {
      return pages.firstWhere((p) => p.id == pageId);
    } catch (_) {
      return null;
    }
  }

  /// 页面总数。
  int get pageCount => pages.length;

  /// Slot 总数。
  int get slotCount =>
      pages.fold(0, (sum, page) => sum + page.slots.length);

  /// 触摸更新（修改时同时更新 updatedAt）。
  void touch() => updatedAt = DateTime.now();

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return {};
  }
}

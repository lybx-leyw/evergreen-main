/// 组件能力声明 — v5P Phase 5。
///
/// 每个组件附带可查询的元数据（分类、标签、数据形状、交互性等），
/// 供 plugin-designer 的 ComponentPicker 和 AI Agent 自动发现。
library;

import 'package:evergreen_base/renderer/templates/v4_modle/data/normalized_data.dart';

/// 可访问性信息。
class AccessibilityInfo {
  final String role;
  final String? labelFrom;
  final bool keyboardNavigable;

  const AccessibilityInfo({this.role = 'group', this.labelFrom, this.keyboardNavigable = false});
}

/// 组件能力元数据。
class ComponentCapability {
  final String type;
  final String displayName;
  final String? iconCode;
  final String category;
  final String description;
  final List<String> tags;
  final List<DataShape> supportedDataShapes;
  final bool interactive;
  final bool supportsDataSource;
  final bool resizable;
  final double? minWidth;
  final double? minHeight;
  final AccessibilityInfo? accessibility;

  const ComponentCapability({
    required this.type,
    required this.displayName,
    this.iconCode,
    required this.category,
    this.description = '',
    this.tags = const [],
    this.supportedDataShapes = const [],
    this.interactive = false,
    this.supportsDataSource = false,
    this.resizable = true,
    this.minWidth,
    this.minHeight,
    this.accessibility,
  });

  static final _registry = <String, ComponentCapability>{};

  static void register(ComponentCapability cap) => _registry[cap.type] = cap;
  static ComponentCapability? lookup(String type) => _registry[type];
  static Set<String> get registeredTypes => _registry.keys.toSet();
  static int get count => _registry.length;

  static List<ComponentCapability> filter({
    String? category,
    List<String>? tags,
    bool? supportsDataSource,
    bool? interactive,
  }) {
    var list = _registry.values.toList();
    if (category != null) list = list.where((c) => c.category == category).toList();
    if (tags != null && tags.isNotEmpty) {
      list = list.where((c) => tags.every((t) => c.tags.contains(t))).toList();
    }
    if (supportsDataSource != null) {
      list = list.where((c) => c.supportsDataSource == supportsDataSource).toList();
    }
    if (interactive != null) {
      list = list.where((c) => c.interactive == interactive).toList();
    }
    return list;
  }

  static Map<String, List<ComponentCapability>> get groupedByCategory {
    final grouped = <String, List<ComponentCapability>>{};
    for (final cap in _registry.values) {
      grouped.putIfAbsent(cap.category, () => []).add(cap);
    }
    return grouped;
  }
}

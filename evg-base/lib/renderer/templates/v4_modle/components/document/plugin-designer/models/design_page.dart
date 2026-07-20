/// 设计页面模型 —— 描述一个插件的单个页面布局。
library;

import 'design_slot.dart';

/// 布局预设（对应 manifest.json 中的 layout.type）。
enum DesignPageLayout {
  fullscreen,
  grid,
  dock,
  flex,
  absolute;

  static DesignPageLayout fromString(String? s) {
    return DesignPageLayout.values.firstWhere(
      (p) => p.name == s,
      orElse: () => DesignPageLayout.grid,
    );
  }
}

/// 设计页面 —— 包含若干 Slot。
class DesignPage {
  /// 页面唯一标识（如 "page_0"）。
  final String id;

  /// 页面标签（Tab 栏显示）。
  String label;

  /// 布局预设。
  DesignPageLayout layoutPreset;

  // ── Flex 布局参数（仅 layoutPreset == flex 时生效）──

  /// 弹性布局方向："row" / "column"（默认 "column"）。
  String flexDirection;

  /// 弹性布局间距（px）。
  double flexGap;

  /// 弹性布局主轴对齐："start" / "center" / "end" / "between" / "around" / "evenly"。
  String flexJustify;

  /// 弹性布局交叉轴对齐："start" / "center" / "end" / "stretch"。
  String flexAlign;

  /// 弹性布局是否换行。
  bool flexWrap;

  // ── Grid 布局参数 ──

  /// 网格列数。
  int gridColumns;

  /// 网格间距（px）。
  double gridGap;

  // ── Dock 布局参数 ──

  /// Dock 各区域比例配置 {top: 0.2, left: 0.25, right: 0.25, bottom: 0.15}。
  /// 不提供时使用默认比例。
  Map<String, double>? dockRegions;

  /// 页面中的 Slot 列表。
  final List<DesignSlot> slots;

  /// 是否为默认页（首次进入插件时展示）。对应 manifest 的 `default`。
  bool isDefault;

  /// 是否隐藏 Tab 栏（封面/全屏页常用）。对应 manifest 的 `hideTab`。
  bool hideTab;

  DesignPage({
    required this.id,
    this.label = '新页面',
    this.layoutPreset = DesignPageLayout.grid,
    this.flexDirection = 'column',
    this.flexGap = 8.0,
    this.flexJustify = 'start',
    this.flexAlign = 'start',
    this.flexWrap = false,
    this.gridColumns = 1,
    this.gridGap = 16.0,
    this.dockRegions,
    List<DesignSlot>? slots,
    this.isDefault = false,
    this.hideTab = false,
  }) : slots = slots ?? [];

  factory DesignPage.fromJson(Map<String, dynamic> json) {
    return DesignPage(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '新页面',
      layoutPreset: DesignPageLayout.fromString(json['layout_preset'] as String?),
      flexDirection: json['flex_direction'] as String? ?? 'column',
      flexGap: (json['flex_gap'] as num?)?.toDouble() ?? 8.0,
      flexJustify: json['flex_justify'] as String? ?? 'start',
      flexAlign: json['flex_align'] as String? ?? 'start',
      flexWrap: json['flex_wrap'] as bool? ?? false,
      gridColumns: json['grid_columns'] as int? ?? 1,
      gridGap: (json['grid_gap'] as num?)?.toDouble() ?? 16.0,
      dockRegions: (json['dock_regions'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      slots: (json['slots'] as List?)
              ?.map((e) =>
                  DesignSlot.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isDefault: json['default'] as bool? ?? false,
      hideTab: json['hideTab'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'layout_preset': layoutPreset.name,
        'flex_direction': flexDirection,
        'flex_gap': flexGap,
        'flex_justify': flexJustify,
        'flex_align': flexAlign,
        'flex_wrap': flexWrap,
        'grid_columns': gridColumns,
        'grid_gap': gridGap,
        if (dockRegions != null) 'dock_regions': dockRegions,
        'default': isDefault,
        'hideTab': hideTab,
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  DesignPage copyWith({
    String? id,
    String? label,
    DesignPageLayout? layoutPreset,
    String? flexDirection,
    double? flexGap,
    String? flexJustify,
    String? flexAlign,
    bool? flexWrap,
    int? gridColumns,
    double? gridGap,
    Map<String, double>? dockRegions,
    List<DesignSlot>? slots,
    bool? isDefault,
    bool? hideTab,
  }) {
    return DesignPage(
      id: id ?? this.id,
      label: label ?? this.label,
      layoutPreset: layoutPreset ?? this.layoutPreset,
      flexDirection: flexDirection ?? this.flexDirection,
      flexGap: flexGap ?? this.flexGap,
      flexJustify: flexJustify ?? this.flexJustify,
      flexAlign: flexAlign ?? this.flexAlign,
      flexWrap: flexWrap ?? this.flexWrap,
      gridColumns: gridColumns ?? this.gridColumns,
      gridGap: gridGap ?? this.gridGap,
      dockRegions: dockRegions ?? this.dockRegions,
      slots: slots ?? List<DesignSlot>.from(this.slots),
      isDefault: isDefault ?? this.isDefault,
      hideTab: hideTab ?? this.hideTab,
    );
  }

  /// 添加 Slot。
  void addSlot(DesignSlot slot) => slots.add(slot);

  /// 按 id 删除 Slot。
  void removeSlot(String slotId) => slots.removeWhere((s) => s.id == slotId);

  /// 查找 Slot。
  DesignSlot? findSlot(String slotId) {
    try {
      return slots.firstWhere((s) => s.id == slotId);
    } catch (_) {
      return null;
    }
  }
}

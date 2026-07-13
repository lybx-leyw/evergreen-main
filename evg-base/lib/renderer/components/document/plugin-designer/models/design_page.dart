/// 设计页面模型 —— 描述一个插件的单个页面布局。
library;

import 'design_slot.dart';

/// 布局预设（对应 manifest.json 中的 layout.type）。
enum LayoutPreset {
  fullscreen,
  grid,
  dock,
  flex;

  static LayoutPreset fromString(String? s) {
    return LayoutPreset.values.firstWhere(
      (p) => p.name == s,
      orElse: () => LayoutPreset.grid,
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
  LayoutPreset layoutPreset;

  /// 页面中的 Slot 列表。
  final List<DesignSlot> slots;

  DesignPage({
    required this.id,
    this.label = '新页面',
    this.layoutPreset = LayoutPreset.grid,
    List<DesignSlot>? slots,
  }) : slots = slots ?? [];

  factory DesignPage.fromJson(Map<String, dynamic> json) {
    return DesignPage(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '新页面',
      layoutPreset: LayoutPreset.fromString(json['layout_preset'] as String?),
      slots: (json['slots'] as List?)
              ?.map((e) =>
                  DesignSlot.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'layout_preset': layoutPreset.name,
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  DesignPage copyWith({
    String? id,
    String? label,
    LayoutPreset? layoutPreset,
    List<DesignSlot>? slots,
  }) {
    return DesignPage(
      id: id ?? this.id,
      label: label ?? this.label,
      layoutPreset: layoutPreset ?? this.layoutPreset,
      slots: slots ?? List<DesignSlot>.from(this.slots),
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

/// 设计插槽模型 —— 描述画布上框选的 Slot 区域及绑定的组件。
library;

import 'design_component.dart';

/// Slot 在画布上的定位区域。
enum SlotRegion {
  top,
  left,
  center,
  right,
  bottom;

  static SlotRegion fromString(String? s) {
    return SlotRegion.values.firstWhere(
      (r) => r.name == s,
      orElse: () => SlotRegion.center,
    );
  }
}

/// 画布上框选的 Slot 描述。
class DesignSlot {
  /// 唯一标识（如 "slot_0", "slot_1"）。
  final String id;

  /// 在页面中的定位区域。
  SlotRegion region;

  /// 画布中的像素坐标 [x, y, width, height]。
  List<double> rect;

  /// 绑定的组件（可为 null，表示未绑定）。
  DesignComponent? component;

  /// 显示标签（自动生成或用户自定义）。
  String label;

  DesignSlot({
    required this.id,
    this.region = SlotRegion.center,
    List<double>? rect,
    this.component,
    String? label,
  })  : rect = rect ?? [0, 0, 300, 200],
        label = label ?? '';

  factory DesignSlot.fromJson(Map<String, dynamic> json) {
    return DesignSlot(
      id: json['id'] as String? ?? '',
      region: SlotRegion.fromString(json['region'] as String?),
      rect: (json['rect'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
          [0, 0, 300, 200],
      component: json['component'] != null
          ? DesignComponent.fromJson(
              json['component'] as Map<String, dynamic>)
          : null,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'region': region.name,
        'rect': rect,
        if (component != null) 'component': component!.toJson(),
        if (label.isNotEmpty) 'label': label,
      };

  DesignSlot copyWith({
    String? id,
    SlotRegion? region,
    List<double>? rect,
    DesignComponent? component,
    String? label,
    bool clearComponent = false,
  }) {
    return DesignSlot(
      id: id ?? this.id,
      region: region ?? this.region,
      rect: rect ?? List<double>.from(this.rect),
      component: clearComponent ? null : (component ?? this.component),
      label: label ?? this.label,
    );
  }
}

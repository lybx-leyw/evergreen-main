/// 设计组件模型 —— 描述 Slot 中绑定的组件类型和配置。
library;

import 'package:flutter/material.dart';

/// 画布上拖入到 Slot 的组件描述。
///
/// 对应 manifest.json 中的 [ComponentDescriptor]。
class DesignComponent {
  /// 组件类型标识（如 "chart", "data-table", "markdown" 等）。
  final String type;

  /// 组件级配置（字段 → 值）。
  final Map<String, dynamic> config;

  /// 编辑器画布中 Slot 的默认宽高提示（仅编辑器 UI 用，不进 manifest）。
  final Size? sizeHint;

  DesignComponent({
    required this.type,
    Map<String, dynamic>? config,
    this.sizeHint,
  }) : config = config ?? {};

  factory DesignComponent.fromJson(Map<String, dynamic> json) {
    final size = json['sizeHint'];
    Size? parsedSize;
    if (size is Map && size['w'] is num && size['h'] is num) {
      parsedSize = Size(
        (size['w'] as num).toDouble(),
        (size['h'] as num).toDouble(),
      );
    }
    return DesignComponent(
      type: json['type'] as String? ?? '',
      config: _asMap(json['config']),
      sizeHint: parsedSize,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (config.isNotEmpty) 'config': config,
      };

  DesignComponent copyWith({
    String? type,
    Map<String, dynamic>? config,
    Size? sizeHint,
  }) {
    return DesignComponent(
      type: type ?? this.type,
      config: config ?? Map<String, dynamic>.from(this.config),
      sizeHint: sizeHint ?? this.sizeHint,
    );
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return {};
  }
}

/// 设计组件模型 —— 描述 Slot 中绑定的组件类型和配置。
library;

/// 画布上拖入到 Slot 的组件描述。
///
/// 对应 manifest.json 中的 [ComponentDescriptor]。
class DesignComponent {
  /// 组件类型标识（如 "chart", "data-table", "markdown" 等）。
  final String type;

  /// 组件级配置（字段 → 值）。
  final Map<String, dynamic> config;

  DesignComponent({
    required this.type,
    Map<String, dynamic>? config,
  }) : config = config ?? {};

  factory DesignComponent.fromJson(Map<String, dynamic> json) {
    return DesignComponent(
      type: json['type'] as String? ?? '',
      config: _asMap(json['config']),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (config.isNotEmpty) 'config': config,
      };

  DesignComponent copyWith({
    String? type,
    Map<String, dynamic>? config,
  }) {
    return DesignComponent(
      type: type ?? this.type,
      config: config ?? Map<String, dynamic>.from(this.config),
    );
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return {};
  }
}

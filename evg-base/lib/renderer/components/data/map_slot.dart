/// 地图 slot——委托 [MapPanel] 渲染。
/// 支持 M2 dataSource 注入：拉取到的 `{center, zoom, markers}` 合并进 config
/// （或经 `map` 子键提供），再由 [MapDescriptor.fromJson] 读取真实字段。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/data/data_source_slot.dart';
import '../shared/widgets/map_panel.dart';

class MapSlot extends DataSourceSlot {
  const MapSlot({super.key, required super.config});

  @override
  DataSourceSlotState<MapSlot> createState() => _MapSlotState();
}

class _MapSlotState extends DataSourceSlotState<MapSlot> {
  @override
  Map<String, dynamic> mergeData(Map<String, dynamic> base, dynamic resolved) {
    final merged = <String, dynamic>{...base};
    if (resolved is Map<String, dynamic>) {
      // 数据源可返回嵌套 `map` 子键，或直接扁平的 center/zoom/markers。
      final inner = resolved['map'];
      if (inner is Map<String, dynamic>) {
        merged.addAll(inner);
      } else {
        merged.addAll(resolved);
      }
    }
    return merged;
  }

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    final map = MapDescriptor.fromJson(cfg);
    return MapPanel(map: map);
  }
}

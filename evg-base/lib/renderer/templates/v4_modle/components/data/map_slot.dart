/// 地图 slot——委托 [MapPanel] 渲染。
/// 支持 M2 dataSource 注入：拉取到的 `{center, zoom, markers}` 合并进 config
/// （或经 `map` 子键提供），再由 [MapDescriptor.fromJson] 读取真实字段。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/slot/data_source_slot.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/map_panel.dart';

class MapSlot extends DataSourceSlot {
  const MapSlot({super.key, required super.config});

  // Phase 2: 声明式数据绑定 — 嵌套 map 键由 buildStatic 自行解包
  @override
  DataMapping get dataMapping => const DataMapping(targetKey: 'map');

  @override
  DataSourceSlotState<MapSlot> createState() => _MapSlotState();
}

class _MapSlotState extends DataSourceSlotState<MapSlot> {

  @override
  Widget buildStatic(Map<String, dynamic> cfg) {
    // manifest 可能把地图配置包在 `config.map` 下，也可能直接扁平提供
    final inner = cfg['map'] as Map<String, dynamic>?;
    final map = MapDescriptor.fromJson(inner ?? cfg);
    return MapPanel(map: map);
  }
}



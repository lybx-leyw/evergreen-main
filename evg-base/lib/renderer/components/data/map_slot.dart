/// 地图 slot——委托 [MapPanel] 渲染。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../shared/widgets/map_panel.dart';

class MapSlot extends StatelessWidget {
  final ComponentDescriptor config;
  const MapSlot({required this.config});

  @override
  Widget build(BuildContext context) {
    final map = MapDescriptor.fromJson(config.config);
    return MapPanel(map: map);
  }
}

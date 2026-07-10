/// 地图面板——根据 [MapDescriptor] 渲染地图视图。
///
/// 公开类：[MapPanel]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 地图渲染组件。
///
/// 读取 [MapDescriptor] 配置中心点、缩放级别、标记点等。
/// 基础实现——占位地图，后续可接入 flutter_map / google_maps_flutter。
class MapPanel extends StatelessWidget {
  final MapDescriptor map;

  const MapPanel({super.key, required this.map});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 地图占位区域
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  '地图 (${map.centerLat}, ${map.centerLng})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (map.markers)
                  const Text(
                    '含标记点',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),

        // 搜索栏
        if (map.search)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索地点...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
          ),
      ],
    );
  }
}

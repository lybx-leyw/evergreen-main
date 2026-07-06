/// 布局引擎——根据 [LayoutDescriptor] 将子组件按序包裹布局层。
///
/// V2: type/preset/features 替代 V1 的 grid/zoom/panels/search/mode。
///
/// 公开类：[LayoutEngine]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'grid_layout.dart';
import 'drawer_host.dart';
import '../widgets/search_bar.dart';

/// 布局引擎——根据 [LayoutDescriptor] 包装子组件。
///
/// 处理顺序（从外到内）：
/// 1. drawers（Drawer/BottomSheet）
/// 2. search（搜索栏）
/// 3. zoom（InteractiveViewer）
/// 4. grid（type=='grid' + preset.columns）
class LayoutEngine extends StatelessWidget {
  final LayoutDescriptor layout;
  final Widget child;

  const LayoutEngine({
    super.key,
    required this.layout,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // 4. 网格布局 — V2: type=='grid' && preset.columns != null
    if (layout.type == 'grid' && layout.preset.columns != null) {
      result = GridLayout(preset: layout.preset, children: [result]);
    }

    // 3. 缩放 — V2: features.zoom
    final zoom = layout.features.zoom;
    if (zoom != null && zoom.enabled) {
      result = InteractiveViewer(
        minScale: zoom.min,
        maxScale: zoom.max,
        child: result,
      );
    }

    // 2. 搜索栏 — V2: features.search
    final search = layout.features.search;
    if (search != null && search.enabled) {
      result = Column(
        children: [
          EvergreenSearchBar(searchConfig: search),
          Expanded(child: result),
        ],
      );
    }

    // 1. 抽屉 — V2: features.drawers
    if (layout.features.drawers.isNotEmpty) {
      result = DrawerHost(drawers: layout.features.drawers, child: result);
    }

    return result;
  }
}

/// 布局引擎——根据 [LayoutDescriptor] 将子组件按序包裹布局层。
///
/// 公开类：[LayoutEngine]
///
/// | 构造函数 | 参数 | 说明 |
/// |---------|------|------|
/// | `LayoutEngine({layout, child})` | LayoutDescriptor?, Widget | 构建布局树 |
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../docs/render_rules.dart';
import 'grid_layout.dart';
import 'panel_layout.dart';
import 'drawer_host.dart';
import '../widgets/search_bar.dart';

/// 布局引擎——根据 [LayoutDescriptor] 包装子组件。
///
/// 处理顺序（从外到内）：
/// 1. drawers（Drawer/BottomSheet）
/// 2. search（搜索栏）
/// 3. panels（TabBar + TabBarView）
/// 4. zoom（InteractiveViewer）
/// 5. grid（GridView）
/// 6. mode（scroll/fit）
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

    // 6. 滚动模式
    result = _applyMode(result);

    // 5. 网格布局
    if (layout.grid != null) {
      result = GridLayout(options: layout.grid!, children: [result]);
    }

    // 4. 缩放（硬编码范围）
    if (layout.zoom.enabled) {
      result = InteractiveViewer(
        minScale: ZoomRules.minScale,
        maxScale: ZoomRules.maxScale,
        child: result,
      );
    }

    // 3. 多面板
    if (layout.panels.isNotEmpty) {
      result = PanelLayout(panels: layout.panels, child: result);
    }

    // 2. 搜索栏
    if (layout.search != null && layout.search!.enabled) {
      result = Column(
        children: [
          EvergreenSearchBar(searchConfig: layout.search),
          Expanded(child: result),
        ],
      );
    }

    // 1. 抽屉
    if (layout.drawers.isNotEmpty) {
      result = DrawerHost(drawers: layout.drawers, child: result);
    }

    return result;
  }

  /// 应用滚动模式。
  ///
  /// - `scroll`：将子组件放入可滚动视口（[SingleChildScrollView]），
  ///   配合 [LayoutBuilder] 填充可用高度。
  /// - `fit`：使用 [FittedBox] 将子组件等比缩放至可用空间。
  /// - 其他值（含空字符串）：无任何包装，直接返回。
  Widget _applyMode(Widget child) {
    return switch (layout.mode) {
      'scroll' => LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: child,
              ),
            );
          },
        ),
      'fit' => LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
                  child: child,
                ),
              ),
            );
          },
        ),
      _ => child, // 未知模式静默忽略
    };
  }
}

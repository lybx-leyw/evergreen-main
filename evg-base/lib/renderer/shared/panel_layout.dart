/// 多面板布局——根据 [PanelDescriptor] 列表生成 TabBar + TabBarView。
///
/// 公开类：[PanelLayout]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 多 Tab 面板布局。
///
/// 读取 [PanelDescriptor] 列表，生成带 TabBar 的面板容器。
/// 默认选中 [PanelDescriptor.isDefault] 的面板。
class PanelLayout extends StatefulWidget {
  final List<PanelDescriptor> panels;
  final Widget child;

  const PanelLayout({
    super.key,
    required this.panels,
    required this.child,
  });

  @override
  State<PanelLayout> createState() => _PanelLayoutState();
}

class _PanelLayoutState extends State<PanelLayout>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final defaultIndex =
        widget.panels.indexWhere((p) => p.isDefault).clamp(0, widget.panels.length - 1);
    _tabController = TabController(
      length: widget.panels.length,
      vsync: this,
      initialIndex: defaultIndex >= 0 ? defaultIndex : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panels.isEmpty) return widget.child;

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: widget.panels.length > 3,
          tabs: widget.panels
              .map((p) => Tab(text: p.label))
              .toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: widget.panels.map((_) => widget.child).toList(),
          ),
        ),
      ],
    );
  }
}

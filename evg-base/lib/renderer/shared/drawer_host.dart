/// 抽屉宿主——根据 [LayoutDescriptor.drawers] 生成 Drawer/BottomSheet。
///
/// 公开类：[DrawerHost]
import 'package:flutter/material.dart';

/// 抽屉宿主组件。
///
/// 读取 drawers 列表（"left", "right", "top", "bottom"），
/// 为每个方向创建对应的 Drawer 或 BottomSheet 容器。
class DrawerHost extends StatelessWidget {
  final List<String> drawers;
  final Widget child;

  const DrawerHost({
    super.key,
    required this.drawers,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    // 左侧抽屉
    if (drawers.contains('left')) {
      result = Scaffold(
        drawer: const _PlaceholderDrawer(side: '左侧'),
        body: result,
      );
    }

    // 右侧抽屉
    if (drawers.contains('right')) {
      result = Scaffold(
        endDrawer: const _PlaceholderDrawer(side: '右侧'),
        body: result,
      );
    }

    return result;
  }
}

/// 占位抽屉——渲染层提供容器，内容由模块自行填充。
class _PlaceholderDrawer extends StatelessWidget {
  final String side;
  const _PlaceholderDrawer({required this.side});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Center(
          child: Text(
            '$side面板',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

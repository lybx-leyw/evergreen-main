/// 数据列表渲染——根据 [DataBindingDescriptor(display=list)] 渲染列表。
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'empty_state.dart';

/// 回调类型——列表项被点击。
typedef ItemTapCallback = void Function(int index, Map<String, dynamic> item);

/// 数据列表视图。
///
/// 支持点击/长按/侧滑手势（通过 [actions] 配置）。
class DataList extends StatelessWidget {
  final DataBindingDescriptor binding;
  final ActionDescriptor? actions;
  final List<Map<String, dynamic>> items;
  final ItemTapCallback? onItemTap;
  final ItemTapCallback? onItemLongPress;
  final void Function(int index)? onItemSwipe;

  const DataList({
    super.key,
    required this.binding,
    this.actions,
    this.items = const [],
    this.onItemTap,
    this.onItemLongPress,
    this.onItemSwipe,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.list_alt_outlined,
        title: '暂无数据',
      );
    }

    final tapBehavior = actions?.itemTap ?? 'detail';
    final longPressBehavior = actions?.itemLongPress;
    final swipeBehavior = actions?.itemSwipe;

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        Widget tile = _buildTile(context, item, index);

        // 侧滑处理
        if (swipeBehavior != null && swipeBehavior != 'none') {
          tile = Dismissible(
            key: ValueKey('item_$index'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Theme.of(context).colorScheme.error,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => onItemSwipe?.call(index),
            child: tile,
          );
        }

        return tile;
      },
    );
  }

  Widget _buildTile(
      BuildContext context, Map<String, dynamic> item, int index) {
    // 从 item 提取标题和副标题
    final title = item['title']?.toString() ??
        item['name']?.toString() ??
        item['label']?.toString() ??
        item.values.firstOrNull?.toString() ??
        '';
    final subtitle = item['subtitle']?.toString() ??
        item['description']?.toString() ??
        item['detail']?.toString();

    return ListTile(
      leading: item['icon'] != null
          ? Icon(
              _parseIcon(item['icon']?.toString()),
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      onTap: () => onItemTap?.call(index, item),
      onLongPress: () => onItemLongPress?.call(index, item),
    );
  }

  /// 解析图标名称为 [IconData]。
  IconData _parseIcon(String? name) {
    return switch (name?.toLowerCase()) {
      'person' || 'user' => Icons.person,
      'settings' => Icons.settings,
      'folder' => Icons.folder,
      'file' || 'document' => Icons.insert_drive_file,
      'image' || 'photo' => Icons.image,
      'video' => Icons.videocam,
      'audio' || 'music' => Icons.audiotrack,
      'link' || 'url' => Icons.link,
      'calendar' || 'date' => Icons.calendar_today,
      'chart' || 'graph' => Icons.show_chart,
      'map' || 'location' => Icons.map,
      'mail' || 'email' => Icons.mail,
      'chat' || 'message' => Icons.chat,
      'check' || 'done' => Icons.check_circle,
      'star' || 'favorite' => Icons.star,
      _ => Icons.circle,
    };
  }
}

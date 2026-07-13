/// 插件图标选择器 —— Material Icons 网格对话框。
///
/// 用于在模块配置阶段选择插件图标，
/// 返回 Material Icons 名称字符串（如 "star"、"home"、"settings"）。
library;

import 'package:flutter/material.dart';

/// 打开图标选择对话框，返回选中的图标名称（Material Icons 名，不含 `Icons.` 前缀）。
///
/// 若用户取消选择，返回 `null`。
Future<String?> showPluginIconPicker(BuildContext context,
    {String? currentIcon}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _PluginIconPickerDialog(currentIcon: currentIcon),
  );
}

class _PluginIconPickerDialog extends StatefulWidget {
  final String? currentIcon;
  const _PluginIconPickerDialog({this.currentIcon});

  @override
  State<_PluginIconPickerDialog> createState() =>
      _PluginIconPickerDialogState();
}

class _PluginIconPickerDialogState extends State<_PluginIconPickerDialog> {
  String _query = '';
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentIcon;
  }

  // 按类别组织的常用 Material Icons（名称 → IconData）。
  static const _allIcons = <String, IconData>{
    // 导航
    'home': Icons.home,
    'dashboard': Icons.dashboard,
    'explore': Icons.explore,
    'map': Icons.map,
    'language': Icons.language,
    'public': Icons.public,
    'travel_explore': Icons.travel_explore,
    // 通信
    'chat': Icons.chat,
    'email': Icons.email,
    'forum': Icons.forum,
    'message': Icons.message,
    'alternate_email': Icons.alternate_email,
    // 工具
    'settings': Icons.settings,
    'build': Icons.build,
    'construction': Icons.construction,
    'handyman': Icons.handyman,
    'tune': Icons.tune,
    // 文档
    'description': Icons.description,
    'article': Icons.article,
    'note': Icons.note,
    'edit_note': Icons.edit_note,
    'assignment': Icons.assignment,
    'book': Icons.book,
    'menu_book': Icons.menu_book,
    'library_books': Icons.library_books,
    // 数据
    'bar_chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart,
    'table_chart': Icons.table_chart,
    'show_chart': Icons.show_chart,
    'analytics': Icons.analytics,
    'insights': Icons.insights,
    'data_exploration': Icons.data_exploration,
    'query_stats': Icons.query_stats,
    // 媒体
    'play_circle': Icons.play_circle,
    'music_note': Icons.music_note,
    'headphones': Icons.headphones,
    'videocam': Icons.videocam,
    'camera': Icons.camera,
    'image': Icons.image,
    'photo_library': Icons.photo_library,
    // 创造
    'brush': Icons.brush,
    'palette': Icons.palette,
    'draw': Icons.draw,
    'gesture': Icons.gesture,
    'create': Icons.create,
    'edit': Icons.edit,
    // 学习
    'school': Icons.school,
    'psychology': Icons.psychology,
    'science': Icons.science,
    'lightbulb': Icons.lightbulb,
    'emoji_objects': Icons.emoji_objects,
    // 系统
    'computer': Icons.computer,
    'phone_android': Icons.phone_android,
    'devices': Icons.devices,
    'cloud': Icons.cloud,
    'storage': Icons.storage,
    'folder': Icons.folder,
    'folder_open': Icons.folder_open,
    // 动作
    'favorite': Icons.favorite,
    'star': Icons.star,
    'thumb_up': Icons.thumb_up,
    'auto_awesome': Icons.auto_awesome,
    'bolt': Icons.bolt,
    'rocket_launch': Icons.rocket_launch,
    'extension': Icons.extension,
    // 状态
    'check_circle': Icons.check_circle,
    'info': Icons.info,
    'warning': Icons.warning,
    'error': Icons.error,
    'notifications': Icons.notifications,
    // 社交
    'people': Icons.people,
    'group': Icons.group,
    'person': Icons.person,
    'badge': Icons.badge,
    // 时间
    'schedule': Icons.schedule,
    'calendar_month': Icons.calendar_month,
    'timer': Icons.timer,
    'history': Icons.history,
    'update': Icons.update,
    // 商店/市场
    'store': Icons.store,
    'shopping_cart': Icons.shopping_cart,
    'card_giftcard': Icons.card_giftcard,
    // 其它
    'widgets': Icons.widgets,
    'view_kanban': Icons.view_kanban,
    'grid_view': Icons.grid_view,
    'view_list': Icons.view_list,
    'code': Icons.code,
    'terminal': Icons.terminal,
    'memory': Icons.memory,
  };

  List<MapEntry<String, IconData>> get _filtered {
    if (_query.isEmpty) return _allIcons.entries.toList();
    final q = _query.toLowerCase();
    return _allIcons.entries
        .where((e) => e.key.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: const Text('选择图标'),
      content: SizedBox(
        width: 460,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索图标名称...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('无匹配图标',
                          style: TextStyle(color: Colors.grey)))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        final isSelected = _selected == entry.key;
                        return Tooltip(
                          message: entry.key,
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selected = entry.key),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                entry.value,
                                size: 28,
                                color: isSelected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('已选: ',
                      style: TextStyle(color: Colors.grey)),
                  Text(_selected!,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (_selectedIcon != null) Icon(_selectedIcon, size: 20),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_selected != null)
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: const Text('清除'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_selected ?? widget.currentIcon),
          child: const Text('确定'),
        ),
      ],
    );
  }

  IconData? get _selectedIcon => _selected != null ? _allIcons[_selected] : null;
}

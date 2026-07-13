/// 组件选择面板 —— 按域分组展示 49 种可用组件，支持拖拽/点击添加到画布。
///
/// P2 实现：完整分组列表 + 搜索过滤 + LongPressDraggable 拖拽支持。
library;

import 'package:flutter/material.dart';

import '../models/design_component.dart';

/// 组件元数据。
class ComponentMeta {
  final String type;
  final String label;
  final IconData icon;
  final String group;

  const ComponentMeta({
    required this.type,
    required this.label,
    required this.icon,
    required this.group,
  });
}

/// 所有可用组件（按 SlotDispatch 注册表）。
const _allComponents = <ComponentMeta>[
  // 对话与交互
  ComponentMeta(type: 'ai-assistant', label: 'AI 助手', icon: Icons.smart_toy, group: '对话与交互'),
  ComponentMeta(type: 'chat', label: '聊天', icon: Icons.chat_bubble, group: '对话与交互'),
  ComponentMeta(type: 'form', label: '表单', icon: Icons.dynamic_form, group: '对话与交互'),
  ComponentMeta(type: 'settings', label: '设置', icon: Icons.settings, group: '对话与交互'),
  // 数据展示
  ComponentMeta(type: 'data-dashboard', label: '数据仪表盘', icon: Icons.dashboard, group: '数据展示'),
  ComponentMeta(type: 'data-table', label: '数据表格', icon: Icons.table_chart, group: '数据展示'),
  ComponentMeta(type: 'card-list', label: '卡片列表', icon: Icons.view_list, group: '数据展示'),
  ComponentMeta(type: 'chart', label: '图表', icon: Icons.bar_chart, group: '数据展示'),
  ComponentMeta(type: 'stat-tile', label: '统计卡片', icon: Icons.score, group: '数据展示'),
  ComponentMeta(type: 'kanban', label: '看板', icon: Icons.view_kanban, group: '数据展示'),
  ComponentMeta(type: 'tree', label: '树形视图', icon: Icons.account_tree, group: '数据展示'),
  ComponentMeta(type: 'timeline', label: '时间线', icon: Icons.timeline, group: '数据展示'),
  ComponentMeta(type: 'map', label: '地图', icon: Icons.map, group: '数据展示'),
  ComponentMeta(type: 'calendar', label: '日历', icon: Icons.calendar_month, group: '数据展示'),
  ComponentMeta(type: 'timetable', label: '课表', icon: Icons.table_rows, group: '数据展示'),
  // 文档与媒体
  ComponentMeta(type: 'code-editor', label: '代码编辑器', icon: Icons.code, group: '文档与媒体'),
  ComponentMeta(type: 'prompt-builder', label: '提示词构建器', icon: Icons.auto_awesome, group: '文档与媒体'),
  ComponentMeta(type: 'doc-viewer', label: '文档查看器', icon: Icons.description, group: '文档与媒体'),
  ComponentMeta(type: 'video-player', label: '视频播放器', icon: Icons.videocam, group: '文档与媒体'),
  ComponentMeta(type: 'audio-player', label: '音频播放器', icon: Icons.headphones, group: '文档与媒体'),
  ComponentMeta(type: 'image-gallery', label: '图片画廊', icon: Icons.photo_library, group: '文档与媒体'),
  ComponentMeta(type: 'presentation', label: '演示文稿', icon: Icons.slideshow, group: '文档与媒体'),
  ComponentMeta(type: 'markdown', label: 'Markdown', icon: Icons.article, group: '文档与媒体'),
  ComponentMeta(type: 'pdf-viewer', label: 'PDF 查看器', icon: Icons.picture_as_pdf, group: '文档与媒体'),
  ComponentMeta(type: 'scanner', label: '扫码器', icon: Icons.qr_code_scanner, group: '文档与媒体'),
  // 创意工具
  ComponentMeta(type: 'spreadsheet', label: '电子表格', icon: Icons.table_chart_outlined, group: '创意工具'),
  ComponentMeta(type: 'notepad', label: '记事本', icon: Icons.note, group: '创意工具'),
  ComponentMeta(type: 'whiteboard', label: '白板', icon: Icons.draw, group: '创意工具'),
  ComponentMeta(type: 'mindmap', label: '思维导图', icon: Icons.hub, group: '创意工具'),
  ComponentMeta(type: 'diff-viewer', label: '差异对比', icon: Icons.difference, group: '创意工具'),
  // 终端/工具
  ComponentMeta(type: 'terminal', label: '终端', icon: Icons.terminal, group: '工具'),
  ComponentMeta(type: 'tech-planner', label: '技术规划', icon: Icons.architecture, group: '工具'),
  // 学习
  ComponentMeta(type: 'type-check', label: '类型检查', icon: Icons.checklist, group: '学习'),
  ComponentMeta(type: 'flashcards', label: '闪卡', icon: Icons.style, group: '学习'),
  ComponentMeta(type: 'quiz', label: '测验', icon: Icons.quiz, group: '学习'),
  ComponentMeta(type: 'crossword', label: '填字游戏', icon: Icons.grid_3x3, group: '学习'),
  ComponentMeta(type: 'pronunciation', label: '发音练习', icon: Icons.record_voice_over, group: '学习'),
  // 控件
  ComponentMeta(type: 'custom', label: '自定义', icon: Icons.widgets, group: '控件'),
  ComponentMeta(type: 'webview', label: '网页视图', icon: Icons.language, group: '控件'),
  ComponentMeta(type: 'divider', label: '分隔线', icon: Icons.horizontal_rule, group: '控件'),
  ComponentMeta(type: 'lottery-wheel', label: '转盘抽奖', icon: Icons.casino, group: '控件'),
  ComponentMeta(type: 'nav-button', label: '导航按钮', icon: Icons.open_in_new, group: '控件'),
  ComponentMeta(type: 'button', label: '按钮栏', icon: Icons.smart_button, group: '控件'),
  // 其他
  ComponentMeta(type: 'scraper-generator', label: '爬虫生成器', icon: Icons.webhook, group: '其他'),
  // 市场
  ComponentMeta(type: 'marketplace', label: '插件市场', icon: Icons.store, group: '市场'),
];

/// 组件选择面板 —— 左侧栏内容。
///
/// 功能：
/// - 顶部搜索栏过滤
/// - 按域分组折叠列表
/// - 每个组件项可拖拽（LongPressDraggable）到画布
/// - 点击组件项 → 触发 [onComponentSelected] 回调
class ComponentPicker extends StatefulWidget {
  /// 选中组件回调（type 字符串）。
  final ValueChanged<String>? onComponentSelected;

  const ComponentPicker({super.key, this.onComponentSelected});

  @override
  State<ComponentPicker> createState() => _ComponentPickerState();
}

class _ComponentPickerState extends State<ComponentPicker> {
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _expandedGroups = {};

  List<ComponentMeta> get _filtered {
    if (_searchQuery.isEmpty) return _allComponents;
    final q = _searchQuery.toLowerCase();
    return _allComponents.where((c) =>
        c.label.toLowerCase().contains(q) ||
        c.type.toLowerCase().contains(q)).toList();
  }

  Map<String, List<ComponentMeta>> get _grouped {
    final map = <String, List<ComponentMeta>>{};
    for (final c in _filtered) {
      map.putIfAbsent(c.group, () => []).add(c);
    }
    return map;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped;
    final isSearching = _searchQuery.isNotEmpty;

    return Column(
      children: [
        // 搜索栏
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索组件...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        // 组件列表
        Expanded(
          child: isSearching
              ? _buildFlatList(groups.values.expand((l) => l).toList())
              : _buildGroupedList(groups),
        ),
      ],
    );
  }

  Widget _buildFlatList(List<ComponentMeta> items) {
    if (items.isEmpty) {
      return const Center(child: Text('未找到匹配组件', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemBuilder: (_, i) => _buildItem(items[i]),
    );
  }

  Widget _buildGroupedList(Map<String, List<ComponentMeta>> groups) {
    final entries = groups.entries.toList();
    return ListView.builder(
      itemCount: entries.length,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemBuilder: (_, i) {
        final group = entries[i];
        final isExpanded = _expandedGroups.contains(group.key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分组标题行（可折叠）
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedGroups.remove(group.key);
                  } else {
                    _expandedGroups.add(group.key);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      group.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${group.value.length})',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              ...group.value.map((c) => _buildItem(c)),
            if (!isExpanded)
              const SizedBox(height: 2),
          ],
        );
      },
    );
  }

  Widget _buildItem(ComponentMeta meta) {
    return LongPressDraggable<String>(
      data: meta.type,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon, size: 18),
              const SizedBox(width: 6),
              Text(meta.label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildItemTile(meta),
      ),
      child: _buildItemTile(meta),
    );
  }

  Widget _buildItemTile(ComponentMeta meta) {
    return InkWell(
      onTap: () => widget.onComponentSelected?.call(meta.type),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(meta.icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                meta.label,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              meta.type,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

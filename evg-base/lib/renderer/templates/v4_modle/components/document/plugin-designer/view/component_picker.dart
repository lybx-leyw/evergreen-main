/// 组件选择面板 —— 按域分组展示可用组件，支持搜索和点击选择。
///
/// v3 简化：移除拖拽支持，纯点击式组件选择（按钮式设计器）。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_component.dart';

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
  ComponentMeta(type: 'data-list', label: '数据列表', icon: Icons.format_list_bulleted, group: '数据展示'),
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
  ComponentMeta(type: 'doc-editor', label: '文档编辑器', icon: Icons.edit_note, group: '文档与媒体'),
  ComponentMeta(type: 'document', label: '文档', icon: Icons.article, group: '文档与媒体'),
  ComponentMeta(type: 'video', label: '视频(原始)', icon: Icons.video_file, group: '文档与媒体'),
  // 创意工具
  ComponentMeta(type: 'spreadsheet', label: '电子表格', icon: Icons.table_chart_outlined, group: '创意工具'),
  ComponentMeta(type: 'notepad', label: '记事本', icon: Icons.note, group: '创意工具'),
  ComponentMeta(type: 'whiteboard', label: '白板', icon: Icons.draw, group: '创意工具'),
  ComponentMeta(type: 'mindmap', label: '思维导图', icon: Icons.hub, group: '创意工具'),
  ComponentMeta(type: 'diff-viewer', label: '差异对比', icon: Icons.difference, group: '创意工具'),
  // 终端/工具
  ComponentMeta(type: 'terminal', label: '终端', icon: Icons.terminal, group: '工具'),
  ComponentMeta(type: 'tech-planner', label: '技术规划', icon: Icons.architecture, group: '工具'),
  ComponentMeta(type: 'plugin-designer', label: '插件设计器', icon: Icons.extension, group: '工具'),
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

/// 预留扩展占位组件（placeholder-01~20）。
const _placeholderComponents = <ComponentMeta>[
  ComponentMeta(type: 'placeholder-01', label: '预留-01', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-02', label: '预留-02', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-03', label: '预留-03', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-04', label: '预留-04', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-05', label: '预留-05', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-06', label: '预留-06', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-07', label: '预留-07', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-08', label: '预留-08', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-09', label: '预留-09', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-10', label: '预留-10', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-11', label: '预留-11', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-12', label: '预留-12', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-13', label: '预留-13', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-14', label: '预留-14', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-15', label: '预留-15', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-16', label: '预留-16', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-17', label: '预留-17', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-18', label: '预留-18', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-19', label: '预留-19', icon: Icons.add_box_outlined, group: '预留扩展'),
  ComponentMeta(type: 'placeholder-20', label: '预留-20', icon: Icons.add_box_outlined, group: '预留扩展'),
];

/// 全部可用组件（具名 + 预留扩展）。
const allDesignerComponents = <ComponentMeta>[
  ..._allComponents,
  ..._placeholderComponents,
];

/// 权威组件类型集合。
class ComponentRegistry {
  static const Set<String> knownTypes = {
    'ai-assistant', 'chat', 'form', 'settings', 'data-dashboard',
    'code-editor', 'prompt-builder', 'data-table', 'card-list', 'data-list', 'chart',
    'stat-tile', 'kanban', 'tree', 'timeline', 'map', 'doc-viewer',
    'doc-editor', 'document', 'video-player', 'video', 'audio-player',
    'image-gallery', 'presentation', 'nav-button', 'button', 'timetable',
    'markdown', 'spreadsheet', 'notepad', 'whiteboard', 'mindmap',
    'diff-viewer', 'terminal', 'type-check', 'flashcards', 'quiz',
    'crossword', 'pronunciation', 'custom', 'webview', 'divider',
    'lottery-wheel', 'calendar', 'scraper-generator', 'tech-planner',
    'plugin-designer', 'pdf-viewer', 'scanner', 'marketplace',
    'placeholder-01', 'placeholder-02', 'placeholder-03', 'placeholder-04',
    'placeholder-05', 'placeholder-06', 'placeholder-07', 'placeholder-08',
    'placeholder-09', 'placeholder-10', 'placeholder-11', 'placeholder-12',
    'placeholder-13', 'placeholder-14', 'placeholder-15', 'placeholder-16',
    'placeholder-17', 'placeholder-18', 'placeholder-19', 'placeholder-20',
  };

  static bool isKnownType(String type) => knownTypes.contains(type);
}

/// 组件选择面板 —— 点击式组件列表（v3 无拖拽）。
///
/// 用于下拉选择器或内联列表。
class ComponentPicker extends StatefulWidget {
  /// 选中组件回调。
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
    if (_searchQuery.isEmpty) return allDesignerComponents;
    final q = _searchQuery.toLowerCase();
    return allDesignerComponents.where((c) =>
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

  /// v3：纯点击选择，无拖拽。
  Widget _buildItem(ComponentMeta meta) {
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

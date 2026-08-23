/// 顶部工具栏 —— 画布管理 + 插件导出 + AI 生成。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/canvas_manager.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/widgets/platform_status_indicator.dart';

class HtmlToolbar extends StatelessWidget {
  final HtmlProject project;
  final List<CanvasMeta> canvases;
  final String? currentCanvasId;
  final ValueChanged<String> onPluginIdChanged;
  final ValueChanged<String> onPluginNameChanged;
  /// 侧边栏分组变更回调（重新导出后覆盖 manifest 的 nav.sidebar.section）。
  final ValueChanged<String> onNavSectionChanged;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback onNewCanvas;
  final ValueChanged<String> onLoadCanvas;
  final VoidCallback onDeleteCanvas;
  final ValueChanged<String> onRenameCanvas;
  final VoidCallback onPreviewRefresh;
  final VoidCallback onAIGenerate;

  const HtmlToolbar({
    super.key,
    required this.project,
    required this.canvases,
    required this.currentCanvasId,
    required this.onPluginIdChanged,
    required this.onPluginNameChanged,
    required this.onNavSectionChanged,
    required this.onSave,
    required this.onExport,
    required this.onNewCanvas,
    required this.onLoadCanvas,
    required this.onDeleteCanvas,
    required this.onRenameCanvas,
    required this.onPreviewRefresh,
    required this.onAIGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final currentMeta = canvases.where((c) => c.id == currentCanvasId).firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      // 内容较多时自动换行，避免安卓窄屏下导出等按钮被横向滚动藏到屏幕外。
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.code, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 6),
          const Text('HTML 创作中心', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 16),

          // ── 画布选择器 ──
          _CanvasSelector(
            canvases: canvases,
            currentId: currentCanvasId,
            onSelect: onLoadCanvas,
            onNew: onNewCanvas,
            onDelete: onDeleteCanvas,
            onRename: onRenameCanvas,
          ),
          const SizedBox(width: 12),

          // ── 插件 ID ──
          SizedBox(
            width: 120,
            child: TextField(
              controller: TextEditingController(text: project.pluginId),
              onChanged: onPluginIdChanged,
              decoration: const InputDecoration(
                labelText: '插件 ID', isDense: true, border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),

          // ── 侧边栏分组 ──
          _SectionSelector(
            value: project.navSection,
            onChanged: onNavSectionChanged,
          ),
          const SizedBox(width: 8),

          // ── 保存画布 ──
          FilledButton.icon(
            onPressed: onSave,
            icon: Icon(project.dirty ? Icons.save : Icons.check, size: 16),
            label: Text(project.dirty ? '保存 *' : '已保存'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 6),

          // ── 导出插件 ──
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.publish, size: 16),
            label: const Text('导出插件'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 8),

          OutlinedButton.icon(
            onPressed: onPreviewRefresh,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新预览'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 24),

          FilledButton.tonalIcon(
            onPressed: onAIGenerate,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI 生成'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 12),

          // ── 平台服务状态（B6：端口可达性体检）──
          const PlatformStatusIndicator(),
        ],
      ),
    );
}
}

/// 侧边栏分组选择器 —— 预设常用分组 + 自定义输入。
/// 变更后重新导出插件即可覆盖 manifest 的 nav.sidebar.section。
class _SectionSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  /// 常用分组预设（与项目现有分组保持一致）。
  static const List<String> _presets = [
    '自定义', '工具', '学习', '系统', '演示', '创作', '展示', '主功能', 'AI 工具', '校园',
  ];

  const _SectionSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final preset = _presets.contains(value) ? value : null;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.folder_outlined, size: 14),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: preset,
              hint: Text(value, style: const TextStyle(fontSize: 12)),
              isDense: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: [
                for (final s in _presets)
                  DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))),
              ],
              onChanged: (s) {
                if (s != null) onChanged(s);
              },
            ),
          ),
          // 自定义分组（当前值不在预设中时显示编辑入口）
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 14),
            tooltip: '自定义分组',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => _showCustomDialog(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _showCustomDialog(BuildContext context) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义侧边栏分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: '如：我的工作台',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      onChanged(result);
    }
  }
}

/// 画布选择下拉菜单。
class _CanvasSelector extends StatelessWidget {
  final List<CanvasMeta> canvases;
  final String? currentId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;

  const _CanvasSelector({
    required this.canvases,
    required this.currentId,
    required this.onSelect,
    required this.onNew,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final current = canvases.where((c) => c.id == currentId).firstOrNull;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.palette, size: 14),
        const SizedBox(width: 4),
        SizedBox(
          width: 160,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentId,
              isExpanded: true,
              isDense: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              hint: const Text('选择画布', style: TextStyle(fontSize: 12)),
              items: [
                for (final c in canvases)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (id) {
                if (id != null) onSelect(id);
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 新建
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          tooltip: '新建画布',
          onPressed: onNew,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        // 更多操作
        if (current != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '画布操作',
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  _showRenameDialog(context, current);
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 12))),
              const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(fontSize: 12, color: Colors.red))),
            ],
          ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, CanvasMeta meta) {
    final controller = TextEditingController(text: meta.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名画布'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () {
            onRename(controller.text);
            Navigator.pop(ctx);
          }, child: const Text('确定')),
        ],
      ),
    );
  }
}

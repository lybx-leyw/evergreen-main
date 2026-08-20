/// 统一左栏 —— 画板树 / 实例 / 数据源 三视图导航（I2）。
///
/// 仿 scraper `board_container_view` 侧栏范式：
/// - 头部 [SegmentedButton] 切换三视图 + 新建画板按钮
/// - 「画板树」：画板节点 + 缩进实例子节点（点击切板，长按重命名）
/// - 「实例」：跨画板平铺全部实例，标注所属画板名，实例索引到画板
/// - 「数据源」：由视图层以保活 key 创建的 [DataPanel]（原数据中枢列收编于此）
///
/// 纯 UI 交互组件（widgets/ 约定）：不碰磁盘/业务，全部经回调上抛。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/canvas_manager.dart';

/// 侧边栏视图模式（I2）。
enum HtmlSidebarView { boards, instances, sources }

class HtmlSidebar extends StatefulWidget {
  final List<CanvasMeta> canvases;
  final String? currentCanvasId;
  final String? currentInstanceId;

  /// 各画板当前实例（key = 画板 id；尚无实例的画板不收录）。
  final Map<String, InstanceMeta> instancesByBoard;

  /// 点击画板/实例节点 → 切换画板（视图层负责 ensureInstance + switchCanvas）。
  final ValueChanged<String> onSelectCanvas;

  /// 新建画板按钮（模板选择）。
  final VoidCallback onNewCanvas;

  /// 删除画板（按画板 id；视图层保证至少保留一个）。
  final ValueChanged<String> onDeleteCanvas;

  /// 重命名画板（画板 id + 新名）。
  final void Function(String canvasId, String newName) onRenameCanvas;

  /// 重命名实例（实例 id + 新名；实例 id 固定不可变）。
  final void Function(String instanceId, String newName) onRenameInstance;

  /// 「数据源」视图内容（视图层以保活 key 创建的 DataPanel）。
  final Widget dataPanel;

  const HtmlSidebar({
    super.key,
    required this.canvases,
    required this.currentCanvasId,
    required this.currentInstanceId,
    required this.instancesByBoard,
    required this.onSelectCanvas,
    required this.onNewCanvas,
    required this.onDeleteCanvas,
    required this.onRenameCanvas,
    required this.onRenameInstance,
    required this.dataPanel,
  });

  @override
  State<HtmlSidebar> createState() => _HtmlSidebarState();
}

class _HtmlSidebarState extends State<HtmlSidebar> {
  HtmlSidebarView _viewMode = HtmlSidebarView.boards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: switch (_viewMode) {
              HtmlSidebarView.boards => _buildBoardTree(context),
              HtmlSidebarView.instances => _buildInstancesList(context),
              HtmlSidebarView.sources => widget.dataPanel,
            },
          ),
        ],
      ),
    );
  }

  /// 头部：画板树 / 实例 / 数据源 SegmentedButton + 新建画板按钮。
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<HtmlSidebarView>(
              segments: const [
                ButtonSegment(value: HtmlSidebarView.boards, label: Text('画板树', style: TextStyle(fontSize: 10.5))),
                ButtonSegment(value: HtmlSidebarView.instances, label: Text('实例', style: TextStyle(fontSize: 10.5))),
                ButtonSegment(value: HtmlSidebarView.sources, label: Text('数据源', style: TextStyle(fontSize: 10.5))),
              ],
              selected: {_viewMode},
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 10.5)),
              ),
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _viewMode = s.first);
              },
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 16),
            tooltip: '新建画板',
            onPressed: widget.onNewCanvas,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// 画板树：画板节点 + 缩进实例子节点（实例索引到画板）。
  Widget _buildBoardTree(BuildContext context) {
    final children = <Widget>[];
    for (final board in widget.canvases) {
      children.add(_buildBoardTile(context, board));
      final instance = widget.instancesByBoard[board.id];
      if (instance != null) {
        children.add(_buildInstanceChildTile(context, board, instance));
      }
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: children,
    );
  }

  Widget _buildBoardTile(BuildContext context, CanvasMeta board) {
    final theme = Theme.of(context);
    final active = board.id == widget.currentCanvasId;
    final instance = widget.instancesByBoard[board.id];
    return InkWell(
      onTap: () => widget.onSelectCanvas(board.id),
      onLongPress: () => _showRenameCanvasDialog(context, board),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.palette, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                board.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                ),
              ),
            ),
            // 实例子节点计数徽标
            if (instance != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '1',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.outline),
                ),
              ),
            // 删除按钮（至少保留一个画板）
            if (widget.canvases.length > 1)
              InkWell(
                onTap: () => widget.onDeleteCanvas(board.id),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 14, color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 画板节点下缩进的实例子节点（点击 → 切到该画板；长按 → 重命名实例）。
  Widget _buildInstanceChildTile(BuildContext context, CanvasMeta board, InstanceMeta instance) {
    final theme = Theme.of(context);
    final active = board.id == widget.currentCanvasId;
    final shortId = instance.id.length > 14 ? '…${instance.id.substring(instance.id.length - 10)}' : instance.id;
    return InkWell(
      onTap: () => widget.onSelectCanvas(board.id),
      onLongPress: () => _showRenameInstanceDialog(context, instance),
      child: Container(
        margin: const EdgeInsets.only(left: 22, right: 6, top: 1, bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4) : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.link_rounded, size: 12, color: theme.colorScheme.tertiary),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                instance.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Text(
              '#$shortId',
              style: TextStyle(fontSize: 9, color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  /// 实例视图：跨画板平铺全部实例（索引到画板）。
  Widget _buildInstancesList(BuildContext context) {
    final theme = Theme.of(context);
    final refs = <InstanceRef>[
      for (final board in widget.canvases)
        if (widget.instancesByBoard[board.id] != null)
          InstanceRef(instance: widget.instancesByBoard[board.id]!, boardName: board.name),
    ];
    if (refs.isEmpty) {
      return Center(
        child: Text(
          '暂无实例\n（新建画板后自动分配一个实例）',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: refs.length,
      itemBuilder: (ctx, i) => _buildInstanceTile(ctx, refs[i]),
    );
  }

  Widget _buildInstanceTile(BuildContext context, InstanceRef ref) {
    final theme = Theme.of(context);
    final boardId = ref.instance.boardId;
    final active = boardId == widget.currentCanvasId;
    final shortId = ref.instance.id.length > 14
        ? '…${ref.instance.id.substring(ref.instance.id.length - 10)}'
        : ref.instance.id;
    return InkWell(
      onTap: () => widget.onSelectCanvas(boardId),
      onLongPress: () => _showRenameInstanceDialog(context, ref.instance),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 14, color: active ? theme.colorScheme.primary : theme.colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.instance.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    '画板「${ref.boardName}」 · #$shortId',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }

  // ═══════ 重命名对话框 ═══════

  void _showRenameCanvasDialog(BuildContext context, CanvasMeta board) {
    final controller = TextEditingController(text: board.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名画板'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '画板名称', border: OutlineInputBorder(), isDense: true),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              widget.onRenameCanvas(board.id, v.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                widget.onRenameCanvas(board.id, v);
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showRenameInstanceDialog(BuildContext context, InstanceMeta instance) {
    final controller = TextEditingController(text: instance.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名实例'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '实例 ID: ${instance.id}',
              style: TextStyle(fontSize: 10.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '实例名称（id 不变）', border: OutlineInputBorder(), isDense: true),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  widget.onRenameInstance(instance.id, v.trim());
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                widget.onRenameInstance(instance.id, v);
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

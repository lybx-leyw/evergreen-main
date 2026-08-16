/// 多画板容器视图（Phase 2 · A21-A24）。
///
/// 布局：左侧竖排画板列表（IDE 侧边栏风格）+ 右侧当前画板工作区。
/// - 每个画板 = 独立 [ScraperGeneratorView] 实例（独立 WebView/会话/快照，任务绝不交叉）
/// - 画板元数据持久化到 [BoardStore]（重启恢复 A24）
library board_container_view;

import 'package:flutter/material.dart';

import 'package:evergreen_base/core/module/module_descriptor.dart';

import 'scraper_board.dart';
import '../view/scraper_generator_view.dart';

/// 多画板容器。
class BoardContainerView extends StatefulWidget {
  final ModuleDescriptor descriptor;
  final ComponentDescriptor config;
  final String slotKey;
  final String projectRoot;
  final String workspaceDir;
  final String? initialUrl;

  const BoardContainerView({
    super.key,
    required this.descriptor,
    required this.config,
    required this.slotKey,
    required this.projectRoot,
    required this.workspaceDir,
    this.initialUrl,
  });

  @override
  State<BoardContainerView> createState() => BoardContainerViewState();
}

class BoardContainerViewState extends State<BoardContainerView> {
  late BoardStore _store;
  List<ScraperBoard> _boards = [];
  int _currentIdx = 0;

  @override
  void initState() {
    super.initState();
    _store = BoardStore(workspaceDir: widget.workspaceDir);
    _boards = _store.load(); // 重启恢复（A24）
    if (_boards.isEmpty) {
      // 首次：默认建一个画板
      _boards = [ScraperBoard.create('画板 1')];
      _persist();
    }
    if (_currentIdx >= _boards.length) _currentIdx = 0;
  }

  void _persist() {
    _store.save(_boards);
  }

  void _selectBoard(int idx) {
    if (idx < 0 || idx >= _boards.length || idx == _currentIdx) return;
    setState(() => _currentIdx = idx);
  }

  void _addBoard() {
    final board = ScraperBoard.create('画板 ${_boards.length + 1}');
    setState(() {
      _boards.add(board);
      _currentIdx = _boards.length - 1;
    });
    _persist();
  }

  void _removeBoard(int idx) {
    if (_boards.length <= 1) {
      // 至少保留一个画板
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个画板')),
      );
      return;
    }
    final board = _boards[idx];
    setState(() {
      _boards.removeAt(idx);
      if (_currentIdx >= _boards.length) _currentIdx = _boards.length - 1;
    });
    _store.deleteBoard(board.id); // 删除画板数据（含快照）
    _persist();
  }

  void _renameBoard(int idx) {
    final board = _boards[idx];
    final ctrl = TextEditingController(text: board.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名画板'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '画板名称'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              setState(() {
                board.name = v.trim();
                board.updatedAt = DateTime.now();
              });
              _persist();
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) {
                setState(() {
                  board.name = v;
                  board.updatedAt = DateTime.now();
                });
                _persist();
                Navigator.pop(ctx);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── 左侧画板列表 ──
        _buildBoardList(context),
        // ── 分割线 ──
        Container(width: 1, color: Theme.of(context).dividerColor),
        // ── 右侧：当前画板工作区（IndexedStack 保状态）──
        Expanded(
          child: IndexedStack(
            index: _currentIdx,
            children: [
              for (var i = 0; i < _boards.length; i++)
                ScraperGeneratorView(
                  key: ValueKey('board-${_boards[i].id}'),
                  descriptor: widget.descriptor,
                  config: widget.config,
                  slotKey: widget.slotKey,
                  initialUrl: widget.initialUrl,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 左侧画板列表（IDE 侧边栏风格）。
  Widget _buildBoardList(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 180,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // 头部：标题 + 新建按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '画板',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  tooltip: '新建画板',
                  onPressed: _addBoard,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 画板列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _boards.length,
              itemBuilder: (ctx, i) => _buildBoardTile(ctx, i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardTile(BuildContext context, int i) {
    final theme = Theme.of(context);
    final board = _boards[i];
    final active = i == _currentIdx;
    return InkWell(
      onTap: () => _selectBoard(i),
      onLongPress: () => _renameBoard(i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // 状态点（模式标识）
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: board.mode == ScraperBoardMode.explore
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                board.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            // 关闭按钮（悬停显示）
            if (_boards.length > 1)
              InkWell(
                onTap: () => _removeBoard(i),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

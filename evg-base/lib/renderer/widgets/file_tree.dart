/// 文件树组件——可展开/折叠的目录树。
///
/// 递归扫描目录，区分文件/文件夹，支持新建/删除/重命名操作。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// 文件树根节点。
class FileTree extends StatefulWidget {
  /// 工作区根目录绝对路径。
  final String rootDir;

  /// 文件点击回调。
  final ValueChanged<WorkspaceFile>? onFileTap;

  /// 外部强制刷新 key（值变化时重新扫描）。
  final Object? refreshKey;

  const FileTree({
    super.key,
    required this.rootDir,
    this.onFileTap,
    this.refreshKey,
  });

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  List<_TreeNode> _roots = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void didUpdateWidget(FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootDir != widget.rootDir ||
        oldWidget.refreshKey != widget.refreshKey) {
      _scan();
    }
  }

  void _scan() {
    final dir = Directory(widget.rootDir);
    if (!dir.existsSync()) {
      _roots = [];
      return;
    }
    _roots = _buildTree(dir);
    setState(() {});
  }

  List<_TreeNode> _buildTree(Directory dir) {
    final nodes = <_TreeNode>[];
    try {
      final entries = dir.listSync()..sort((a, b) {
            final aIsDir = a is Directory;
            final bIsDir = b is Directory;
            if (aIsDir && !bIsDir) return -1;
            if (!aIsDir && bIsDir) return 1;
            return p.basename(a.path).compareTo(p.basename(b.path));
          });

      for (final e in entries) {
        final name = p.basename(e.path);
        // 跳过隐藏文件和 state.json
        if (name.startsWith('.') || name == 'state.json') continue;
        final relPath = p.relative(e.path, from: widget.rootDir);

        if (e is Directory) {
          nodes.add(_TreeNode(
            name: name,
            path: e.path,
            relPath: relPath,
            isDir: true,
            children: _buildTree(e),
          ));
        } else if (e is File) {
          nodes.add(_TreeNode(
            name: name,
            path: e.path,
            relPath: relPath,
            isDir: false,
          ));
        }
      }
    } catch (_) {
      // 忽略权限错误
    }
    return nodes;
  }

  void _newFile(_TreeNode? parent) {
    final parentDir = parent?.path ?? widget.rootDir;
    showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('新建文件'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件名（如 hello.dart）'),
            onSubmitted: (v) {
              _createFile(parentDir, v.trim());
              Navigator.of(ctx).pop();
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isNotEmpty) _createFile(parentDir, name);
                Navigator.of(ctx).pop();
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  void _createFile(String parentDir, String name) {
    final file = File(p.join(parentDir, name));
    if (file.existsSync()) return;
    file.createSync(recursive: true);
    _scan();
  }

  void _deleteNode(_TreeNode node) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除 "${node.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final entity = FileSystemEntity.typeSync(node.path) == FileSystemEntityType.directory
                  ? Directory(node.path)
                  : File(node.path);
              entity.deleteSync(recursive: true);
              _scan();
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _renameNode(_TreeNode node) {
    final ctrl = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新名称'),
          onSubmitted: (v) {
            _doRename(node, v.trim());
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              _doRename(node, ctrl.text.trim());
              Navigator.of(ctx).pop();
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _doRename(_TreeNode node, String newName) {
    if (newName.isEmpty || newName == node.name) return;
    final parentDir = p.dirname(node.path);
    final newPath = p.join(parentDir, newName);
    if (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) return;
    File(node.path).renameSync(newPath);
    _scan();
  }

  /// 暴露 refresh 供外部调用。
  void refresh() => _scan();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_roots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 32,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text('工作区为空', style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建文件'),
              onPressed: () => _newFile(null),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 工具栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text('工作区',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: '新建文件',
                visualDensity: VisualDensity.compact,
                onPressed: () => _newFile(null),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
                onPressed: _scan,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 树节点
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 2),
            children: _roots.map((node) => _TreeNodeWidget(
                  node: node,
                  depth: 0,
                  onFileTap: (f) {
                    widget.onFileTap?.call(WorkspaceFile(
                      name: f.name,
                      path: f.relPath,
                    ));
                  },
                  onNewFile: _newFile,
                  onDelete: _deleteNode,
                  onRename: _renameNode,
                )).toList(),
          ),
        ),
      ],
    );
  }
}

/// 树节点数据。
class _TreeNode {
  final String name;
  final String path; // 绝对路径
  final String relPath; // 相对工作区路径
  final bool isDir;
  final List<_TreeNode> children;

  _TreeNode({
    required this.name,
    required this.path,
    required this.relPath,
    required this.isDir,
    this.children = const [],
  });
}

/// 树节点渲染组件。
class _TreeNodeWidget extends StatefulWidget {
  final _TreeNode node;
  final int depth;
  final ValueChanged<_TreeNode>? onFileTap;
  final void Function(_TreeNode parent)? onNewFile;
  final void Function(_TreeNode node)? onDelete;
  final void Function(_TreeNode node)? onRename;

  const _TreeNodeWidget({
    required this.node,
    required this.depth,
    this.onFileTap,
    this.onNewFile,
    this.onDelete,
    this.onRename,
  });

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = widget.node;
    final indent = 8.0 + widget.depth * 16.0;

    if (!node.isDir) {
      return _FileRow(
        name: node.name,
        indent: indent,
        onTap: () => widget.onFileTap?.call(node),
        onDelete: () => widget.onDelete?.call(node),
        onRename: () => widget.onRename?.call(node),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.only(left: indent, right: 4),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 14),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onSelected: (action) {
                      if (action == 'newFile') widget.onNewFile?.call(node);
                      if (action == 'delete') widget.onDelete?.call(node);
                      if (action == 'rename') widget.onRename?.call(node);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'newFile', child: Text('新建文件', style: TextStyle(fontSize: 13))),
                      PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 13))),
                      PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(fontSize: 13))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          ...node.children.map((child) => _TreeNodeWidget(
                node: child,
                depth: widget.depth + 1,
                onFileTap: widget.onFileTap,
                onNewFile: widget.onNewFile,
                onDelete: widget.onDelete,
                onRename: widget.onRename,
              )),
      ],
    );
  }
}

/// 文件行组件。
class _FileRow extends StatelessWidget {
  final String name;
  final double indent;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  const _FileRow({
    required this.name,
    required this.indent,
    this.onTap,
    this.onDelete,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: 4),
        child: SizedBox(
          height: 28,
          child: Row(
            children: [
              Icon(
                _fileIcon(name),
                size: 14,
                color: _fileColor(name),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 14),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onSelected: (action) {
                  if (action == 'rename') onRename?.call();
                  if (action == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(fontSize: 13))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Icons.code;
      case 'py': return Icons.code;
      case 'js':
      case 'ts': return Icons.javascript;
      case 'html': return Icons.html;
      case 'css': return Icons.css;
      case 'md': return Icons.description;
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml': return Icons.settings;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg': return Icons.image;
      case 'txt': return Icons.text_snippet;
      default: return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return const Color(0xFF00B4AB);
      case 'py': return const Color(0xFF3572A5);
      case 'js':
      case 'ts': return const Color(0xFFF0DB4F);
      case 'md': return const Color(0xFF083FA1);
      case 'json': return const Color(0xFF5B6C7D);
      default: return Colors.grey;
    }
  }
}

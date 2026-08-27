/// 工作区抽屉——从 AI 助手右侧滑出，展示工作区文件池。
///
/// 公开类：[WorkspaceDrawer]
///
/// Task 七 9.1：头部「管理文件」按钮进入多选管理模式——每个文件行显示
/// Checkbox + 选中高亮，底部操作栏提供【下载】【删除】【取消】。
/// 下载固定到系统下载目录（Android 回退 app 支持目录/downloads），
/// 成功弹窗展示路径 + 一键复制，失败 SnackBar 报错。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import '../workspace_file_download.dart';
import 'models.dart';
import 'empty_state.dart';

/// 工作区抽屉——从右侧滑出。
///
/// 读取 [WorkspaceDescriptor] 获取工作区配置，
/// 扫描 `.greenix/workspaces/<moduleId>/` 下的实际文件。
class WorkspaceDrawer extends ConsumerStatefulWidget {
  final WorkspaceDescriptor? workspace;
  final String moduleId;
  final void Function(WorkspaceFile file)? onFileTap;

  const WorkspaceDrawer({
    super.key,
    this.workspace,
    required this.moduleId,
    this.onFileTap,
  });

  @override
  ConsumerState<WorkspaceDrawer> createState() => _WorkspaceDrawerState();
}

class _WorkspaceDrawerState extends ConsumerState<WorkspaceDrawer> {
  /// 多选管理模式选中的文件绝对路径集合。
  final Set<String> _selected = {};
  bool _manageMode = false;

  /// 当前工作区文件（每次 build 重扫，删除后 setState 即刷新）。
  List<WorkspaceFile> get _files => _scanWorkspace(widget.moduleId);

  List<WorkspaceFile> get _selectedFiles =>
      _files.where((f) => _selected.contains(f.path)).toList();

  void _toggleManageMode() {
    setState(() {
      _manageMode = !_manageMode;
      _selected.clear();
    });
  }

  void _exitManageMode() {
    setState(() {
      _manageMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(WorkspaceFile file) {
    setState(() {
      if (!_selected.remove(file.path)) _selected.add(file.path);
    });
  }

  /// 批量下载：逐个复制到固定下载目录；成功弹窗（路径+复制），失败 SnackBar。
  Future<void> _downloadSelected(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final saved = <String>[];
    String? firstError;
    for (final f in files) {
      final r = await downloadWorkspaceFile(f);
      if (r.ok) {
        saved.add(r.savedPath!);
      } else {
        firstError ??= r.error;
      }
    }
    if (!mounted) return;
    if (saved.isNotEmpty) {
      showWorkspaceDownloadSuccessDialog(context, saved);
    }
    if (firstError != null) {
      showWorkspaceDownloadErrorSnackBar(context, firstError);
    }
  }

  /// 批量删除：确认对话框（参照 session_list_bar 的删除确认模式）→ 逐个删除。
  Future<void> _deleteSelected(BuildContext context) async {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除选中的 ${files.length} 个文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var failed = 0;
    for (final f in files) {
      try {
        final file = File(f.path);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        failed++;
        debugPrint('[WorkspaceDrawer] 删除失败: ${f.path}: $e');
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0 ? '已删除 ${files.length} 个文件' : '删除完成，${failed} 个失败',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    if (ws == null) {
      return const _EmptyPanel(message: '工作区未配置');
    }

    final files = _files;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 头部 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                '工作区文件',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${files.length}${ws.maxFiles != null ? ' / ${ws.maxFiles}' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 「管理文件」按钮（Task 七 9.1）——进入/退出多选管理模式
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _manageMode ? Icons.close : Icons.manage_search,
                  size: 18,
                ),
                tooltip: _manageMode ? '退出管理' : '管理文件',
                visualDensity: VisualDensity.compact,
                onPressed: _toggleManageMode,
              ),
            ],
          ),
        ),

        // ── AI 可创建的文件格式提示 ──
        if (ws.aiCreatable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ws.aiCreatable.map((ext) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ext,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        const Divider(height: 1),

        // ── 文件列表 ──
        Expanded(
          child: files.isEmpty
              ? const EmptyState(
                  icon: Icons.insert_drive_file_outlined,
                  title: '暂无文件',
                  subtitle: 'AI 生成的文件会自动出现在这里',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return _FileTile(
                      file: file,
                      manageMode: _manageMode,
                      selected: _selected.contains(file.path),
                      onTap: () {
                        if (_manageMode) {
                          _toggleSelect(file);
                        } else {
                          debugPrint('[WorkspaceDrawer] 点击文件: ${file.name}');
                          widget.onFileTap?.call(file);
                        }
                      },
                      onToggle: () => _toggleSelect(file),
                    );
                  },
                ),
        ),

        // ── 多选管理底部操作栏（Task 七 9.1） ──
        if (_manageMode)
          _buildManageBar(theme),
      ],
    );
  }

  Widget _buildManageBar(ThemeData theme) {
    final count = _selected.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '已选 $count 项',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: count == 0 ? null : () => _downloadSelected(context),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('下载'),
          ),
          TextButton.icon(
            onPressed: count == 0 ? null : () => _deleteSelected(context),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('删除'),
          ),
          TextButton(
            onPressed: _exitManageMode,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 扫描工作区目录下的实际文件（递归扫描子目录）。
  static List<WorkspaceFile> _scanWorkspace(String moduleId) {
    final dirPath = '$greenixWorkspacesDir/$moduleId';
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      return [];
    }
    try {
      final files = <WorkspaceFile>[];
      _scanRecursive(dir, '', files);
      debugPrint('[WorkspaceDrawer] 扫描 $dirPath → ${files.length} 个文件');
      return files;
    } catch (e) {
      debugPrint('[WorkspaceDrawer] 扫描工作区失败: $e');
      return [];
    }
  }

  static void _scanRecursive(Directory dir, String relativePath, List<WorkspaceFile> out) {
    for (final entity in dir.listSync()) {
      if (entity is File) {
        if (entity.path.endsWith('.meta')) continue;
        final name = relativePath.isEmpty
            ? entity.uri.pathSegments.last
            : '$relativePath/${entity.uri.pathSegments.last}';
        out.add(WorkspaceFile(
          name: name,
          path: entity.path,
          sizeBytes: entity.lengthSync(),
        ));
      } else if (entity is Directory) {
        final subPath = relativePath.isEmpty
            ? entity.uri.pathSegments.last
            : '$relativePath/${entity.uri.pathSegments.last}';
        _scanRecursive(entity, subPath, out);
      }
    }
  }
}

// ═══════ _FileTile ═══════

class _FileTile extends StatelessWidget {
  final WorkspaceFile file;
  final VoidCallback? onTap;
  final bool manageMode;
  final bool selected;
  final VoidCallback? onToggle;

  const _FileTile({
    required this.file,
    this.onTap,
    this.manageMode = false,
    this.selected = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        // 多选模式选中高亮
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 多选模式：Checkbox
            if (manageMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onToggle?.call(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
            ],
            // 文件类型图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _fileColor(file.name, theme.colorScheme)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _fileIcon(file.name),
                size: 18,
                color: _fileColor(file.name, theme.colorScheme),
              ),
            ),
            const SizedBox(width: 12),
            // 文件名 + 大小
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(file.sizeBytes),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 预览/打开图标（多选模式下不再显示）
            if (!manageMode)
              Icon(
                Icons.open_in_new,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.code,
      'py' => Icons.code,
      'js' || 'ts' => Icons.javascript,
      'json' => Icons.data_object,
      'md' => Icons.article,
      'pdf' => Icons.picture_as_pdf,
      'pptx' || 'ppt' => Icons.slideshow,
      'docx' || 'doc' => Icons.description,
      'xlsx' || 'xls' || 'csv' => Icons.table_chart,
      'jpg' || 'jpeg' || 'png' || 'gif' || 'svg' || 'bmp' => Icons.image,
      'mp4' || 'webm' || 'mov' => Icons.videocam,
      'mp3' || 'wav' || 'ogg' => Icons.audiotrack,
      'zip' || 'tar' || 'gz' || 'rar' => Icons.archive,
      'html' || 'htm' => Icons.html,
      'css' => Icons.css,
      'yaml' || 'yml' => Icons.settings,
      _ => Icons.insert_drive_file,
    };
  }

  Color _fileColor(String name, ColorScheme scheme) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'java' || 'cpp' || 'go' || 'rs' => Colors.blue,
      'json' || 'yaml' || 'yml' || 'xml' => Colors.orange,
      'md' || 'txt' => scheme.outlineVariant,
      'pdf' => Colors.red,
      'pptx' || 'ppt' => Colors.deepOrange,
      'docx' || 'doc' => Colors.indigo,
      'xlsx' || 'xls' || 'csv' => Colors.green,
      'jpg' || 'png' || 'gif' || 'svg' => Colors.purple,
      'mp4' || 'webm' => Colors.pink,
      'mp3' || 'wav' => Colors.teal,
      'zip' || 'tar' || 'gz' => Colors.brown,
      _ => scheme.outline,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ═══════ _EmptyPanel ═══════

class _EmptyPanel extends StatelessWidget {
  final String message;
  const _EmptyPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

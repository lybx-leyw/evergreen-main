/// 工作区抽屉——从 AI 助手右侧滑出，展示工作区文件池。
///
/// 公开类：[WorkspaceDrawer]
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'models.dart';
import 'empty_state.dart';

/// 工作区抽屉——从右侧滑出。
///
/// 读取 [WorkspaceDescriptor] 获取工作区配置，
/// 扫描 `.greenix/workspaces/<moduleId>/` 下的实际文件。
class WorkspaceDrawer extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = workspace;
    if (ws == null) {
      return const _EmptyPanel(message: '工作区未配置');
    }

    final files = _scanWorkspace(moduleId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 头部 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                '工作区文件',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${files.length}${ws.maxFiles != null ? ' / ${ws.maxFiles}' : ''}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ext,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      onTap: () {
                        debugPrint('[WorkspaceDrawer] 点击文件: ${file.name}');
                        onFileTap?.call(file);
                      },
                    );
                  },
                ),
        ),
      ],
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

  const _FileTile({required this.file, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 文件类型图标
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _fileColor(file.name).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _fileIcon(file.name),
                size: 18,
                color: _fileColor(file.name),
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
            // 预览/打开图标
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

  Color _fileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'java' || 'cpp' || 'go' || 'rs' => Colors.blue,
      'json' || 'yaml' || 'yml' || 'xml' => Colors.orange,
      'md' || 'txt' => Colors.grey,
      'pdf' => Colors.red,
      'pptx' || 'ppt' => Colors.deepOrange,
      'docx' || 'doc' => Colors.indigo,
      'xlsx' || 'xls' || 'csv' => Colors.green,
      'jpg' || 'png' || 'gif' || 'svg' => Colors.purple,
      'mp4' || 'webm' => Colors.pink,
      'mp3' || 'wav' => Colors.teal,
      'zip' || 'tar' || 'gz' => Colors.brown,
      _ => Colors.blueGrey,
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

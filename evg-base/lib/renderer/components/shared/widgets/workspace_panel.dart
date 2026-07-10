/// 工作区面板——根据 [WorkspaceDescriptor] 渲染文件池 UI。
///
/// 公开类：[WorkspacePanel]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'models.dart';
import 'empty_state.dart';

/// 文件工作区面板。
///
/// 读取 [WorkspaceDescriptor] 配置文件限制、AI 可创建等。
class WorkspacePanel extends StatelessWidget {
  final WorkspaceDescriptor? workspace;
  final List<WorkspaceFile> files;

  const WorkspacePanel({
    super.key,
    this.workspace,
    this.files = const [],
  });

  @override
  Widget build(BuildContext context) {
    final ws = workspace;
    if (ws == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部信息
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '工作区',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                '${files.length}${ws.maxFiles != null ? ' / ${ws.maxFiles}' : ''}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 文件列表
        Expanded(
          child: files.isEmpty
              ? const EmptyState(
                  icon: Icons.insert_drive_file_outlined,
                  title: '暂无文件',
                  subtitle: '拖入文件或通过 AI 生成',
                )
              : ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: Icon(
                        _fileIcon(file.name),
                        size: 20,
                      ),
                      title: Text(
                        file.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          // TODO: 关闭文件
                        },
                      ),
                      dense: true,
                    );
                  },
                ),
        ),
      ],
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
      'jpg' || 'png' || 'gif' || 'svg' => Icons.image,
      'mp4' || 'webm' => Icons.videocam,
      'mp3' || 'wav' => Icons.audiotrack,
      _ => Icons.insert_drive_file,
    };
  }
}


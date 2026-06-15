import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/file_utils.dart';
import '../../courses/providers/courses_provider.dart';
import '../providers/download_provider.dart';
import '../services/download_service.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/toast.dart';

/// Downloads screen — course material download manager.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadsProvider);
    final coursesAsync = ref.watch(coursesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: Column(
        children: [
          // Course selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: coursesAsync.when(
              loading: () => const LoadingIndicator.compact(hint: '加载课程...'),
              error: (e, _) => ErrorCard(
                message: '加载课程失败',
                detail: e.toString(),
                onRetry: () => ref.invalidate(coursesListProvider),
              ),
              data: (result) => result.fold(
                (courses) => DropdownButtonFormField<int>(
                  value: downloadState.selectedCourseId,
                  decoration: const InputDecoration(
                    labelText: '选择课程',
                    border: OutlineInputBorder(),
                  ),
                  items: courses
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (id) =>
                      ref.read(downloadsProvider.notifier).selectCourse(id),
                ),
                (error) => ErrorCard(
                  message: error.userMessage,
                  hint: error.recoveryHint,
                ),
              ),
            ),
          ),
          // File list
          Expanded(
            child: _buildFileList(context, ref, downloadState),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(
      BuildContext context, WidgetRef ref, DownloadsState state) {
    if (state.selectedCourseId == null) {
      return const EmptyState(
          icon: Icons.folder_off, title: '请选择课程以查看可下载文件');
    }

    if (state.isLoading) {
      return const LoadingWidget(message: '加载文件列表...');
    }

    if (state.error != null) {
      return ErrorCard(
        message: '加载文件列表失败',
        detail: state.error,
        onRetry: () {
          if (state.selectedCourseId != null) {
            ref
                .read(downloadsProvider.notifier)
                .loadFiles(state.selectedCourseId!);
          }
        },
      );
    }

    if (state.files.isEmpty) {
      return const EmptyState(icon: Icons.folder_off, title: '该课程暂无资料文件');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: state.files.length,
      itemBuilder: (_, i) {
        final f = state.files[i];
        final name = f['name']?.toString() ?? '未知文件';
        final size = f['size']?.toString() ?? '0';
        final url = f['url']?.toString() ?? '';
        final active = state.activeDownloads[name];

        return Card(
          child: ListTile(
            leading: active?.status == DownloadStatus.downloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: active!.progress > 0 ? active.progress : null,
                    ),
                  )
                : active?.status == DownloadStatus.completed
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : active?.status == DownloadStatus.failed
                        ? const Icon(Icons.error, color: Colors.red)
                        : const Icon(Icons.insert_drive_file),
            title: Text(name),
            subtitle: active?.status == DownloadStatus.downloading
                ? Text('${(active!.progress * 100).toStringAsFixed(0)}% — '
                    '${active.receivedBytes ~/ 1024} / ${active.totalBytes ~/ 1024} KB')
                : active?.status == DownloadStatus.completed
                    ? Text('下载完成 — $size bytes')
                : active?.status == DownloadStatus.failed
                    ? Text('下载失败 — ${active!.error ?? "未知错误"}')
                    : Text('$size bytes'),
            trailing: active?.status == DownloadStatus.completed
                ? IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: '打开文件位置',
                    onPressed: () {
                      openInFileManager(active!.destPath);
                      Toast.success(context, '已打开文件所在位置');
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: '下载',
                    onPressed: url.isNotEmpty
                        ? () => ref
                            .read(downloadsProvider.notifier)
                            .startDownload(url, name)
                        : null,
                  ),
          ),
        );
      },
    );
  }
}

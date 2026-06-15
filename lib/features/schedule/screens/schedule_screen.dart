import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/file_utils.dart';
import '../../../widgets/loading_indicator.dart';
import '../../../widgets/error_card.dart';
import '../../../widgets/toast.dart';
import '../providers/schedule_provider.dart';

/// 课表导出页 — 将当前课表导出为 iCal (.ics) 文件。
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  bool _didToast = false;

  @override
  Widget build(BuildContext context) {
    final exportAsync = ref.watch(icalExportFileProvider);

    // 导出成功后自动弹 Toast（仅一次）
    if (!_didToast && exportAsync.hasValue && exportAsync.value != null) {
      _didToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Toast.success(context, '课表已导出为 iCal 文件');
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('课表导出')),
      body: exportAsync.when(
        loading: () => const LoadingWidget(message: '生成课表文件...'),
        error: (e, _) {
          _didToast = false;
          return ErrorCard(
            message: '导出失败',
            detail: e.toString(),
            onRetry: () => ref.invalidate(icalExportFileProvider),
          );
        },
        data: (filePath) {
          if (filePath == null) {
            return const Center(child: Text('导出失败'));
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      const Text('课表已导出', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        filePath,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('打开文件夹'),
                            onPressed: () {
                              openInFileManager(filePath);
                              Toast.success(context, '已打开文件所在位置');
                            },
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重新导出'),
                            onPressed: () {
                              _didToast = false;
                              ref.invalidate(icalExportFileProvider);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

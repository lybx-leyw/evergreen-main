import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/file_utils.dart';
import '../../courses/providers/courses_provider.dart';
import '../../courses/services/courses_api_service.dart';
import '../services/download_service.dart';

/// State for the downloads feature.
class DownloadsState {
  final int? selectedCourseId;
  final List<Map<String, dynamic>> files;
  final bool isLoading;
  final String? error;
  final Map<String, DownloadTask> activeDownloads;

  const DownloadsState({
    this.selectedCourseId,
    this.files = const [],
    this.isLoading = false,
    this.error,
    this.activeDownloads = const {},
  });

  DownloadsState copyWith({
    int? selectedCourseId,
    List<Map<String, dynamic>>? files,
    bool? isLoading,
    String? error,
    Map<String, DownloadTask>? activeDownloads,
  }) {
    return DownloadsState(
      selectedCourseId: selectedCourseId ?? this.selectedCourseId,
      files: files ?? this.files,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      activeDownloads: activeDownloads ?? this.activeDownloads,
    );
  }
}

class DownloadsNotifier extends StateNotifier<DownloadsState> {
  final CoursesApiService _api;
  final DownloadService _downloadService;

  DownloadsNotifier(this._api, this._downloadService)
      : super(const DownloadsState());

  void selectCourse(int? courseId) {
    state = state.copyWith(selectedCourseId: courseId, files: [], error: null);
    if (courseId != null) {
      loadFiles(courseId);
    }
  }

  Future<void> loadFiles(int courseId) async {
    state = state.copyWith(isLoading: true, error: null, selectedCourseId: courseId);
    final result = await _api.getCourseFullData(courseId);
    result.fold(
      (fullData) {
        final files = <Map<String, dynamic>>[];
        for (final a in fullData.activities) {
          // 课程资料（文件上传）
          if (a['type'] == 'material' && a['uploads'] != null) {
            for (final u in (a['uploads'] as List)) {
              files.add(u as Map<String, dynamic>);
            }
          }
          // 作业附件
          if (a['type'] == 'homework' && a['attachments'] != null) {
            for (final att in (a['attachments'] as List)) {
              files.add(att as Map<String, dynamic>);
            }
          }
        }
        state = state.copyWith(files: files, isLoading: false);
      },
      (error) {
        state = state.copyWith(error: error.userMessage, isLoading: false);
      },
    );
  }

  Future<void> startDownload(String url, String fileName) async {
    // Always fall back to system Downloads directory
    final dlDir = AppConfig.getDownloadDirectory();

    // Resolve relative URLs against courses.zju.edu.cn
    String absoluteUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      absoluteUrl = 'https://courses.zju.edu.cn${url.startsWith('/') ? '' : '/'}$url';
    }

    final task = DownloadTask(
      url: absoluteUrl,
      destPath: '$dlDir${Platform.pathSeparator}$fileName',
      fileName: fileName,
    );

    final updated = Map<String, DownloadTask>.from(state.activeDownloads);
    updated[fileName] = task.copyWith(status: DownloadStatus.downloading);
    state = state.copyWith(activeDownloads: updated, error: null);

    try {
      await _downloadService.download(
        absoluteUrl,
        task.destPath,
        onProgress: (received, total) {
          updated[fileName] = task.copyWith(
            totalBytes: total,
            receivedBytes: received,
            status: DownloadStatus.downloading,
          );
          state = state.copyWith(activeDownloads: Map.from(updated));
        },
      );
      updated[fileName] = task.copyWith(
        totalBytes: task.totalBytes,
        receivedBytes: task.totalBytes,
        status: DownloadStatus.completed,
      );
    } catch (e) {
      String errorMsg = e.toString();
      // Provide clearer error message for common issues
      if (errorMsg.contains('Connection refused') || errorMsg.contains('SocketException')) {
        errorMsg = '网络连接失败，请检查是否在校园网环境或 RVPN 已连接';
      } else if (errorMsg.contains('401') || errorMsg.contains('403') || errorMsg.contains('未登录')) {
        errorMsg = '认证失败，请重新登录学在浙大';
      } else if (errorMsg.contains('timeout') || errorMsg.contains('Timeout')) {
        errorMsg = '下载超时，请检查网络后重试';
      }
      updated[fileName] = task.copyWith(
        status: DownloadStatus.failed,
        error: errorMsg,
      );
    }
    state = state.copyWith(activeDownloads: Map.from(updated));
  }
}

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final dio = ref.read(dioClientProvider);
  return DownloadService(dio);
});

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
  final api = ref.read(coursesApiProvider);
  final downloadService = ref.read(downloadServiceProvider);
  return DownloadsNotifier(api, downloadService);
});

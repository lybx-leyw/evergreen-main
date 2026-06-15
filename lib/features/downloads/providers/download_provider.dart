import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../../core/config/app_config.dart';
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
          if (a['type'] == 'material' && a['uploads'] != null) {
            for (final u in (a['uploads'] as List)) {
              files.add(u as Map<String, dynamic>);
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
    final dlDir = AppConfig.downloadPath;
    if (dlDir == null || dlDir.isEmpty) {
      state = state.copyWith(
          error: '未配置下载目录，请在设置中设置下载路径');
      return;
    }

    final task = DownloadTask(
      url: url,
      destPath: '$dlDir${Platform.pathSeparator}$fileName',
      fileName: fileName,
    );

    final updated = Map<String, DownloadTask>.from(state.activeDownloads);
    updated[fileName] = task.copyWith(status: DownloadStatus.downloading);
    state = state.copyWith(activeDownloads: updated, error: null);

    try {
      await _downloadService.download(
        url,
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
      updated[fileName] = task.copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
      );
    }
    state = state.copyWith(activeDownloads: Map.from(updated));
  }
}

final downloadServiceProvider = Provider<DownloadService>((ref) {
  return DownloadService();
});

final downloadsProvider =
    StateNotifierProvider<DownloadsNotifier, DownloadsState>((ref) {
  final api = ref.read(coursesApiProvider);
  final downloadService = ref.read(downloadServiceProvider);
  return DownloadsNotifier(api, downloadService);
});

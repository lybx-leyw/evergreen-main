import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 单个下载任务的状态。
enum DownloadStatus { pending, downloading, paused, completed, failed }

class DownloadTask {
  final String url;
  final String destPath;
  final String fileName;
  final int totalBytes;
  final int receivedBytes;
  final DownloadStatus status;
  final String? error;

  const DownloadTask({
    required this.url,
    required this.destPath,
    required this.fileName,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.status = DownloadStatus.pending,
    this.error,
  });

  double get progress => totalBytes > 0 ? receivedBytes / totalBytes : 0.0;

  DownloadTask copyWith({
    int? totalBytes,
    int? receivedBytes,
    DownloadStatus? status,
    String? error,
  }) {
    return DownloadTask(
      url: url,
      destPath: destPath,
      fileName: fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      status: status ?? this.status,
      error: error,
    );
  }
}

/// 简单下载管理器——HTTP 流式写入文件，带进度回调。
class DownloadService {
  /// 下载文件到指定目录。
  ///
  /// [onProgress] 在每次写入 chunk 后回调 `(received, total)`。
  /// 返回最终文件路径。
  Future<String> downloadToDir(
    String url,
    String dir, {
    void Function(int received, int total)? onProgress,
  }) async {
    final fileName = p.basename(Uri.parse(url).path);
    if (fileName.isEmpty) throw Exception('无法从 URL 提取文件名: $url');
    final destPath = '${dir}${Platform.pathSeparator}$fileName';
    return download(url, destPath, onProgress: onProgress);
  }

  /// 下载文件到指定路径。
  Future<String> download(
    String url,
    String destPath, {
    void Function(int received, int total)? onProgress,
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _doDownload(url, destPath, onProgress);
      } on SocketException catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << attempt));
      } on HttpException catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw Exception('下载失败（已重试 $maxRetries 次）');
  }

  Future<String> _doDownload(
    String url,
    String destPath,
    void Function(int received, int total)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }

    final contentLength = response.contentLength ?? 0;
    final file = File(destPath);
    await file.create(recursive: true);
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          onProgress(received, contentLength);
        }
      }
      await sink.flush();
    } catch (e) {
      await sink.close();
      rethrow;
    }
    await sink.close();
    return destPath;
  }
}

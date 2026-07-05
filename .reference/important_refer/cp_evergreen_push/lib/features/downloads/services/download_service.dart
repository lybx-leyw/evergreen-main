import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../../../core/network/network_config.dart';

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

/// 下载管理器——基于 Dio 的 HTTP 流式写入文件，带进度回调。
///
/// 使用 Dio 而非裸 http.Request，以复用 SSO Cookie、AuthInterceptor 等，
/// 确保 courses.zju.edu.cn 等需要认证的下载正常。
class DownloadService {
  final Dio _dio;

  DownloadService(this._dio);

  /// 下载文件到指定目录。
  ///
  /// [onProgress] 在每次写入 chunk 后回调 `(received, total)`。
  /// [headers] 可选的自定义请求头（如 Referer）。
  /// 返回最终文件路径。
  Future<String> downloadToDir(
    String url,
    String dir, {
    void Function(int received, int total)? onProgress,
    Map<String, String>? headers,
  }) async {
    final fileName = p.basename(Uri.parse(url).path);
    if (fileName.isEmpty) throw Exception('无法从 URL 提取文件名: $url');
    final destPath = '${dir}${Platform.pathSeparator}$fileName';
    return download(url, destPath, onProgress: onProgress, headers: headers);
  }

  /// 下载文件到指定路径。
  ///
  /// [headers] 可选的自定义请求头（如 Referer）。
  Future<String> download(
    String url,
    String destPath, {
    void Function(int received, int total)? onProgress,
    Map<String, String>? headers,
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _doDownload(url, destPath, onProgress, headers);
      } on SocketException catch (e) {
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 1 << attempt));
      } on DioException catch (e) {
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
    Map<String, String>? headers,
  ) async {
    // Auto-add Referer for ZJU domains to satisfy CSRF / auth requirements
    final effectiveHeaders = Map<String, String>.from(headers ?? {});
    final host = Uri.tryParse(url)?.host ?? '';
    if (NetworkConfig.isZjuDomain(url) && !effectiveHeaders.containsKey('Referer')) {
      // Derive Referer from the domain
      final scheme = Uri.tryParse(url)?.scheme ?? 'https';
      effectiveHeaders['Referer'] = '$scheme://$host/';
      // Ensure browser-like User-Agent for download endpoints
      effectiveHeaders.putIfAbsent(
        'User-Agent',
        () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      );
    }

    // For classroom.zju.edu.cn PPT image downloads, add Origin header
    if (host.contains('classroom.zju.edu.cn') || host.contains('tgmedia.cmc.zju.edu.cn')) {
      effectiveHeaders.putIfAbsent('Origin', () => 'https://classroom.zju.edu.cn');
    }

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: effectiveHeaders,
      ),
    );

    final body = response.data;
    if (body == null) {
      throw Exception('下载响应为空');
    }

    final contentLengthStr = body.headers['content-length']?.first;
    final contentLength = int.tryParse(contentLengthStr ?? '0') ?? 0;
    final file = File(destPath);
    await file.create(recursive: true);
    final sink = file.openWrite();
    int received = 0;

    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, contentLength);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return destPath;
  }
}

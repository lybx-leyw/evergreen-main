/// 文件下载服务 —— 把远端 URL 下载到本地文件（T8a，验收目标 4 core 侧）。
///
/// 面向「数据源声明 file 类型 → 返回文件清单/下载端点 → 平台可下载到本地文件」
/// 链路：消费方（T8b 导出 UI）经 [downloadFile] / [downloadFiles] 把单个或多个
/// 文件下载到用户自选路径，同时：
/// - 支持自定义 headers（凭据头，供 T2 会话中心导出注入，如 Cookie/Referer/UA）；
/// - 支持超时与失败重试（退避，对齐 T4 语义）；返回本地文件路径；
/// - 禁止越界写入：`targetPath` 经 [PathSandbox] 校验（构造时给 [sandboxRoot]），
///   防目录穿越。
///
/// 实现用 `dart:io` 的 [HttpClient]（零新依赖，纯 Dart，可独立 `dart test`），
/// 复用 `release_downloader.dart` 的 `_download` 模式，但服务化 + [Result] +
/// headers + 沙箱。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `DataFileService({sandboxRoot?, timeout?, retryBackoff?})` | 构造；sandboxRoot 设置后 targetPath 必须位于其内 |
/// | `downloadFile({url, targetPath, headers?, timeout?, maxRetries})` | 下载单文件，返回 `Result<String>`（Ok=本地绝对路径） |
/// | `downloadFiles({urls, targetDir, headers?, timeout?, maxRetries})` | 串行批量下载，返回逐项 `Result<String>` |
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../log.dart';
import '../result.dart';
import '../errors.dart';
import '../utils/path_sandbox.dart';

/// 重试判定：HTTP 状态码是否可重试（限流 429 与服务端 5xx 视为瞬态可重试；
/// 其余 4xx 视为确定性客户端错误，不重试）。
bool _isRetryableStatus(int? statusCode) =>
    statusCode == null || statusCode == 429 || statusCode >= 500;

/// HTTP 下载过程中的状态错误（用于内部分类重试与否）。
class _DownloadHttpError implements Exception {
  final int? statusCode;
  final String url;
  const _DownloadHttpError(this.statusCode, this.url);

  bool get retryable => _isRetryableStatus(statusCode);

  @override
  String toString() => '下载失败（HTTP ${statusCode ?? '未知'}）: $url';
}

/// 文件下载服务。
class DataFileService {
  /// 沙箱根目录（可选）。设置后 [downloadFile] 的 [targetPath] 必须位于该根内
  /// （经 [PathSandbox] 校验），越界直接拒绝且不写入；未设置（null）时仅做路径
  /// 规范化，不强制边界（调用方如导出 UI 显式选定的目录视为可信）。
  final String? sandboxRoot;

  /// 默认请求超时（单个请求，含连接与响应体读取）。
  final Duration timeout;

  /// 重试退避序列（对齐 PluginInstaller「3 次重试 1s/3s/5s」语义）。超过序列长度
  /// 复用末值。测试可注入更短序列加速。
  final List<Duration> retryBackoff;

  PathSandbox? get _sandbox =>
      sandboxRoot == null ? null : PathSandbox(sandboxRoot!);

  DataFileService({
    this.sandboxRoot,
    this.timeout = const Duration(seconds: 30),
    this.retryBackoff = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ],
  });

  /// 下载单个文件到 [targetPath]，返回 `Result<String>`（Ok = 本地绝对路径）。
  ///
  /// - [headers]：自定义请求头（凭据头，供 T2 会话中心导出注入）；逐个 `set`。
  /// - [timeout]：覆盖实例默认超时；超时 → [TimeoutException] → 重试（达上限则
  ///   `Err(AppError.timeout)`）。
  /// - [maxRetries]：首次请求失败后的最大重试次数（默认 3）；退避见 [retryBackoff]。
  ///   可重试：网络/连接错误、超时、HTTP 429/5xx；不可重试：其它 4xx（如 404，fail-fast）。
  /// - 沙箱：构造给了 [sandboxRoot] 且 [targetPath] 越界 → `Err`（拒绝写入）。
  Future<Result<String>> downloadFile({
    required String url,
    required String targetPath,
    Map<String, String>? headers,
    Duration? timeout,
    int maxRetries = 3,
  }) async {
    if (url.trim().isEmpty) {
      return Err(AppError.validationError('下载地址为空'));
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return Err(AppError.validationError('下载地址无效: $url'));
    }
    final effectiveTimeout = timeout ?? this.timeout;

    // 沙箱校验：越界拒绝（防目录穿越）。未设 sandboxRoot 时仅做绝对路径规范化。
    String resolvedPath;
    final sandbox = _sandbox;
    if (sandbox != null) {
      final confined = sandbox.confine(targetPath);
      if (confined == null) {
        Log().warn('DataFileService: 目标路径越界，拒绝写入',
            data: {'targetPath': targetPath, 'root': sandboxRoot});
        return Err(AppError.validationError('目标路径越界，已拒绝写入'));
      }
      resolvedPath = confined;
    } else {
      resolvedPath = File(targetPath).absolute.path;
    }

    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_backoffFor(attempt));
      }
      try {
        final bytes =
            await _downloadOnce(url, headers).timeout(effectiveTimeout);
        await _writeFile(resolvedPath, bytes);
        Log().info('DataFileService: 下载成功',
            data: {'url': url, 'target': resolvedPath, 'bytes': bytes.length});
        return Ok(resolvedPath);
      } on _DownloadHttpError catch (e) {
        if (!e.retryable || attempt >= maxRetries) {
          Log().warn('DataFileService: 下载失败（HTTP 状态）',
              data: {'url': url, 'statusCode': e.statusCode});
          return Err(e.statusCode != null
              ? AppError.httpStatus(e.statusCode!, url)
              : AppError.downloadFailed(url, reason: e.toString()));
        }
        lastError = e;
      } on TimeoutException catch (e) {
        if (attempt >= maxRetries) {
          Log().warn('DataFileService: 下载超时', data: {'url': url});
          return Err(AppError.timeout(effectiveTimeout.inSeconds, url));
        }
        lastError = e;
      } catch (e) {
        // 连接/网络错误视为可重试。
        if (attempt >= maxRetries) {
          Log()
              .warn('DataFileService: 下载失败', data: {'url': url, 'error': '$e'});
          return Err(AppError.downloadFailed(url, reason: e.toString()));
        }
        lastError = e;
      }
    }

    return Err(AppError.downloadFailed(url, reason: '$lastError'));
  }

  /// 串行批量下载多个 URL 到 [targetDir]（文件名自 URL 末段派生，无法派生时按
  /// 序号回退 `file_<i>.bin`）。
  ///
  /// 选择**串行**（并发度 = 1）：确定性、避免并发磁盘写入竞争，且对同一数据源
  /// 的多文件下载天然限流；如后续需要高吞吐可扩展为受限并发（[downloadFile]
  /// 本身并发安全，只需在此层加并发窗口）。
  ///
  /// 返回与 [urls] 等长的逐项 `Result<String>`（单项失败不影响后续项）。
  Future<List<Result<String>>> downloadFiles({
    required List<String> urls,
    required String targetDir,
    Map<String, String>? headers,
    Duration? timeout,
    int maxRetries = 3,
  }) async {
    final results = <Result<String>>[];
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final name = _fileNameFromUrl(url, i);
      final targetPath = p.join(targetDir, name);
      results.add(await downloadFile(
        url: url,
        targetPath: targetPath,
        headers: headers,
        timeout: timeout,
        maxRetries: maxRetries,
      ));
    }
    return results;
  }

  /// 单次 HTTP 下载（返回字节；HTTP 非 200 → 抛 [_DownloadHttpError]）。
  ///
  /// 超时由调用方外层 `.timeout()` 统一施加（覆盖连接 + 响应体读取全程），
  /// 这里仅设置 [HttpClient.connectionTimeout] 作为连接层兜底。
  Future<List<int>> _downloadOnce(
      String url, Map<String, String>? headers) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (headers != null) {
        headers.forEach((k, v) => request.headers.set(k, v));
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'evergreen-data-file');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw _DownloadHttpError(response.statusCode, url);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  /// 写文件：确保父目录存在后整块写入。
  Future<void> _writeFile(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  /// 第 [attempt] 次重试（1 起）前的退避时长。
  Duration _backoffFor(int attempt) {
    if (retryBackoff.isEmpty) return Duration.zero;
    final idx = (attempt - 1).clamp(0, retryBackoff.length - 1);
    return retryBackoff[idx];
  }

  /// 从 URL 末段派生文件名；无法派生时回退 `file_<index>.bin`。
  String _fileNameFromUrl(String url, int index) {
    try {
      final segs = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty);
      if (segs.isNotEmpty) {
        final last = segs.last;
        if (last.isNotEmpty) return last;
      }
    } catch (_) {}
    return 'file_$index.bin';
  }
}

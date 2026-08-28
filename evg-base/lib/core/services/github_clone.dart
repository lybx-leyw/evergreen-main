/// GitHub 源克隆器（M5-5，主包网络层）。
///
/// 把 [GithubSource] 克隆到本地目录，供 [scanSources]（core 子包纯逻辑）消费。
/// 实现分平台：
/// - 桌面：[Process.run] 调 `git clone` 子进程（支持 shallow / `--branch` / 私有仓库凭据）。
/// - 安卓：系统无 git 可执行文件，改用 GitHub zipball 端点
///   （`api.github.com/repos/{owner}/{repo}/zipball[/ref]`）下载 zip 解压，
///   语义等价于浅克隆指定 ref（ref 为空取默认分支）。
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import 'package:evergreen_base/core/module/github_source.dart';
import 'package:evergreen_base/core/module/marketplace_scanner.dart';

/// 克隆失败类型。
enum CloneErrorType {
  notFound,
  authRequired,
  timeout,
  unknown,
}

/// 克隆结果。
class CloneResult {
  final bool success;
  final String? error;
  final CloneErrorType? errorType;

  const CloneResult({required this.success, this.error, this.errorType});

  factory CloneResult.ok() => const CloneResult(success: true);
  factory CloneResult.fail(String error, CloneErrorType type) =>
      CloneResult(success: false, error: error, errorType: type);
}

/// 真实克隆一个 GitHub 源到 [targetDir]。
///
/// - 桌面：`git clone [--depth 1] [--branch <ref>] <cloneUrl> <targetDir>`。
///   [shallow]（默认 true）浅克隆，只拉最新提交；[ref] 非空加 `--branch <ref>`
///   （支持 branch/tag/commit）；超时 [timeout]（默认 60s）视为 [CloneErrorType.timeout]。
/// - 安卓：转 [cloneGithubViaZipball]（zipball 下载 + 解压，天然是单 ref 快照，
///   与浅克隆等价；[shallow] 无额外效果）。
///
/// 幂等：若 [targetDir] 已存在且非空，直接成功（跳过重复网络）。
Future<CloneResult> cloneGithub(
  GithubSource src,
  String targetDir, {
  bool shallow = true,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final dir = Directory(targetDir);
  if (dir.existsSync() && dir.listSync().isNotEmpty) {
    return CloneResult.ok();
  }

  if (Platform.isAndroid) {
    return cloneGithubViaZipball(src, targetDir, timeout: timeout);
  }

  final args = <String>['clone'];
  if (shallow) args.add('--depth');
  if (shallow) args.add('1');
  if (src.ref != null && src.ref!.isNotEmpty) {
    args.add('--branch');
    args.add(src.ref!);
  }
  args.add(src.cloneUrl);
  args.add(targetDir);

  try {
    final result = await Future(() => Process.run(
          'git',
          args,
          stdoutEncoding: const SystemEncoding(),
          stderrEncoding: const SystemEncoding(),
        )).timeout(timeout);
    if (result.exitCode == 0) {
      return CloneResult.ok();
    }
    final stderr = (result.stderr as String? ?? '').toLowerCase();
    if (stderr.contains('not found') || stderr.contains('repository') && stderr.contains('not exist')) {
      return CloneResult.fail(stderr, CloneErrorType.notFound);
    }
    if (stderr.contains('authentication') || stderr.contains('permission')) {
      return CloneResult.fail(stderr, CloneErrorType.authRequired);
    }
    return CloneResult.fail(stderr, CloneErrorType.unknown);
  } on TimeoutException {
    return CloneResult.fail('git clone 超时（>${timeout.inSeconds}s）', CloneErrorType.timeout);
  } on ProcessException catch (e) {
    return CloneResult.fail('无法启动 git: $e', CloneErrorType.unknown);
  }
}

/// 安卓路径：GitHub zipball 下载 + 解压（无 git 二进制的平台兜底）。
///
/// 与桌面 `git clone` 对齐：
/// - [ref] 非空下载该分支/tag/commit 的 zipball；为空取仓库默认分支
///   （zipball 端点本身对无 ref 请求返回默认分支快照）。
/// - 错误映射一致：404 → notFound，401/403 → authRequired，超时 → timeout。
/// - 幂等由 [cloneGithub] 入口统一处理（targetDir 非空即跳过），本函数不检查。
///
/// [dio] 可注入（测试传 mock adapter），默认新建 [Dio]。
Future<CloneResult> cloneGithubViaZipball(
  GithubSource src,
  String targetDir, {
  Dio? dio,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final client = dio ?? Dio();
  final ref = src.ref;
  final base = 'https://api.github.com/repos/${src.owner}/${src.repo}/zipball';
  final url = (ref == null || ref.isEmpty)
      ? base
      : '$base/${Uri.encodeComponent(ref)}';

  try {
    final resp = await client.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Evergreen-Android',
        },
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) {
      return CloneResult.fail(
          '下载 zipball 失败（HTTP ${resp.statusCode}）',
          _errorTypeFor(resp.statusCode));
    }

    final bytes = resp.data!;
    if (bytes.isEmpty) {
      return CloneResult.fail('zipball 内容为空', CloneErrorType.unknown);
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final topLevel = _zipTopLevel(archive);
    if (topLevel == null) {
      return CloneResult.fail('zipball 内容为空', CloneErrorType.unknown);
    }
    _extractZip(archive, topLevel, targetDir);
    return CloneResult.ok();
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return CloneResult.fail(
          '下载超时（>${timeout.inSeconds}s）', CloneErrorType.timeout);
    }
    return CloneResult.fail(
        '下载 zipball 失败: ${e.message ?? e}',
        _errorTypeFor(e.response?.statusCode));
  } catch (e) {
    return CloneResult.fail('解压 zipball 失败: $e', CloneErrorType.unknown);
  }
}

/// HTTP 状态码 → 克隆失败类型（与桌面 git clone 的 stderr 映射对齐）。
CloneErrorType _errorTypeFor(int? statusCode) {
  if (statusCode == 404) return CloneErrorType.notFound;
  if (statusCode == 401 || statusCode == 403) return CloneErrorType.authRequired;
  return CloneErrorType.unknown;
}

/// 取 zipball 内所有条目共享的顶层目录名（GitHub zipball 格式为
/// `{repo}-{ref}/...`）。空 zip 返回 null。
String? _zipTopLevel(Archive archive) {
  for (final f in archive.files) {
    final name = f.name;
    if (name.isEmpty) continue;
    final seg = name.split('/').first;
    if (seg.isNotEmpty && seg != '.' && seg != '..') return seg;
  }
  return null;
}

/// 把 zipball 内容提取到 [targetDir]（剥离共享顶层目录，与 git clone 落盘
/// 目录语义一致）。防御：跳过非文件条目、非顶层条目与路径穿越条目。
void _extractZip(Archive archive, String topLevel, String targetDir) {
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name;
    if (name.isEmpty) continue;
    final segments = name.split('/');
    if (segments.length < 2 || segments.first != topLevel) continue;
    final rel = segments.sublist(1).join('/');
    // 防御：拒绝路径穿越与绝对路径条目（zipball 由 GitHub 生成，正常不会出现）。
    if (rel.isEmpty || rel.contains('..') || rel.startsWith('/')) continue;
    final dest = File('$targetDir/$rel');
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(f.content);
  }
}

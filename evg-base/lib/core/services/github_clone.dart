/// GitHub 源克隆器（M5-5，主包网络层）。
///
/// 把 [GithubSource] 克隆到本地目录，供 [scanSources]（core 子包纯逻辑）消费。
/// 真实实现用 `git clone` 子进程；[cloneGithub] 即 [GithubCloner] 的默认实现。
library;

import 'dart:async';
import 'dart:io';

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
/// 实现：[Process.run] 调 `git clone [--depth 1] [--branch <ref>] <cloneUrl> <targetDir>`。
/// - [shallow]（默认 true）：浅克隆，只拉最新提交，显著降低大仓库耗时与体积。
/// - [ref] 非空时加 `--branch <ref>`（支持 branch/tag/commit）。
/// - 超时 [timeout]（默认 60s），超时视为 [CloneErrorType.timeout]。
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

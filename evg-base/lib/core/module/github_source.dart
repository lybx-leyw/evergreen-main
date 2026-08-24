/// GitHub 源接入（M4-1/M4-2，纯逻辑）。
///
/// - [parseGithubSource]：解析 `github:` 源 URL → owner/repo/ref（纯函数，无网络）。
/// - [classifyRepo]：按六格信号把仓库分类到 [Lattice]（复用 M0 的推断逻辑）。
///
/// 网络克隆/元数据抓取在主包 `core/plugin/` 完成；本文件只做可单测的解析与分类。
library;

import 'lattice.dart';

/// 解析后的 GitHub 源。
class GithubSource {
  final String owner;
  final String repo;

  /// 分支 / tag / commit，可空（默认主分支）。
  final String? ref;

  const GithubSource({required this.owner, required this.repo, this.ref});

  /// clone URL（https）。
  String get cloneUrl => 'https://github.com/$owner/$repo.git';

  /// 人类可读标识。
  String get fullName => '$owner/$repo';

  @override
  String toString() => ref != null ? '$fullName@$ref' : fullName;
}

/// 解析 `github:` 源描述。
///
/// 支持形式：
/// - `github:owner/repo`
/// - `github:owner/repo@ref`
/// - `https://github.com/owner/repo(.git)?`
/// - `https://github.com/owner/repo/tree/ref`（或 /blob/、/commit/）
///
/// 非法形式抛 [FormatException]（fail-closed）。
GithubSource parseGithubSource(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    throw FormatException('github 源不能为空');
  }

  // 形如 github:owner/repo[@ref]
  if (s.startsWith('github:')) {
    final body = s.substring('github:'.length);
    return _parseOwnerRepo(body);
  }
  // 形如 https://github.com/owner/repo...
  if (s.contains('github.com/')) {
    final uri = Uri.tryParse(s);
    if (uri == null || uri.pathSegments.length < 2) {
      throw FormatException('无法解析的 github URL: $raw');
    }
    final owner = uri.pathSegments[0];
    final repo = uri.pathSegments[1].replaceAll('.git', '');
    String? ref;
    // /tree/<ref> 或 /blob/<ref> 或 /commit/<ref>
    if (uri.pathSegments.length >= 4 &&
        {'tree', 'blob', 'commit'}.contains(uri.pathSegments[2])) {
      ref = uri.pathSegments[3];
    }
    return GithubSource(owner: owner, repo: repo, ref: ref);
  }
  throw FormatException('不是 github 源: $raw');
}

GithubSource _parseOwnerRepo(String body) {
  final noGit = body.replaceAll('.git', '');
  final atIdx = noGit.indexOf('@');
  final repoPart = atIdx >= 0 ? noGit.substring(0, atIdx) : noGit;
  final ref = atIdx >= 0 ? noGit.substring(atIdx + 1) : null;
  final slash = repoPart.indexOf('/');
  if (slash <= 0 || slash == repoPart.length - 1) {
    throw FormatException('github 源格式应为 owner/repo: $body');
  }
  final owner = repoPart.substring(0, slash);
  final repo = repoPart.substring(slash + 1);
  return GithubSource(owner: owner, repo: repo, ref: ref);
}

/// 仓库分类信号（M4-2，复用 [LatticeSignals]）。
///
/// [GithubSource] 不直接携带这些信号；由扫描器（主包）填好后再分类。
class RepoClassification {
  final LatticeSignals signals;

  /// 原始检测到的文件名/目录线索（用于审计与脚手架提示）。
  final List<String> hints;

  const RepoClassification(this.signals, [this.hints = const []]);

  /// 推断该仓库应落入的格（纯函数）。
  Lattice classify() => inferLattice(signals);
}

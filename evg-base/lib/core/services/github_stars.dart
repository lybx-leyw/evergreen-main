/// GitHub star 数的数据中枢接入（M6，主包服务层）。
///
/// 把「各 GitHub 仓库的实时 star 数」注册为 [DataOrchestrator] 的一个
/// [DataType<Map<String,int>>]，统一走数据中枢的缓存 / TTL / 状态 / 失败语义，
/// 而非发现页自行散装拉取。
///
/// 设计要点：
/// - 单一聚合数据类型 `github-stars`，value 为 `owner/repo -> stars`。
/// - 磁盘持久化（[DataType.persistentKey]）+ 1 小时 TTL，减少重复网络请求。
/// - fetcher 网络失败（[fetchStarsBatch] 返回空）时**抛 [GithubStarsFetchException]**，
///   由 orchestrator 捕获 → 标记 `connected:false` + `lastError`，并返回 null
///   （对齐数据中枢「拉取失败返回空 + 记录失败信息」的既有契约）。
library;

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/data/type.dart';
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/services/github_metadata.dart';

/// star 数据源在数据中枢中的唯一类型名。
const String kGithubStarsTypeName = 'github-stars';

/// star 数缓存 TTL：star 变化不频繁，1 小时足够新鲜，且显著降低 rate limit 压力。
const Duration kGithubStarsTtl = Duration(hours: 1);

/// GitHub star 拉取失败（网络不可达 / 全仓库失败 / 结果为空）。
class GithubStarsFetchException implements Exception {
  final String message;
  const GithubStarsFetchException(this.message);

  @override
  String toString() => 'GithubStarsFetchException: $message';
}

/// 构造 `github-stars` 的 [DataType] 描述符。
DataType<Map<String, int>> githubStarsType() => const DataType<Map<String, int>>(
      name: kGithubStarsTypeName,
      category: '市场',
      displayName: 'GitHub Star 数',
      ttl: kGithubStarsTtl,
      persistentKey: 'github-stars',
    );

/// 把 GitHub star 拉取注册进数据中枢 [orch]。
///
/// [repoUrls] 为待拉取的仓库 URL 列表（`https://github.com/owner/repo` 或
/// `github:owner/repo`）。fetcher 内部调 [fetchStarsBatch] 逐条串行拉取。
///
/// 语义（对齐数据中枢契约）：
/// - 全部仓库都拉取失败（结果为空 map）→ 抛 [GithubStarsFetchException]，
///   orchestrator 记 `lastError` 并返回 null（消费方回退 registry 静态 stars）。
/// - 部分失败 → 返回成功那部分的映射（失败的仓库不在其中，消费方逐仓库回退）。
///
/// [dio] / [token] 透传给 [fetchStarsBatch]（测试注入 mock / 提升 rate limit）。
void registerGithubStars(
  DataOrchestrator orch, {
  required List<String> repoUrls,
  Dio? dio,
  String? token,
}) {
  orch.register(githubStarsType(), () async {
    final result = await fetchStarsBatch(
      repoUrls,
      dio: dio,
      token: token,
    );
    if (result.isEmpty) {
      throw GithubStarsFetchException('GitHub star 拉取失败（无可用结果）');
    }
    return result;
  });
}

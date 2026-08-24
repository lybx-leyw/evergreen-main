/// GitHub 仓库元数据抓取（M6，主包网络层）。
///
/// 市场卡片需要「实时 star 数」：registry JSON 里的 [RegistryPlugin.stars] 是
/// 静态声明值，可能过时。本文件用 GitHub REST API 拉取真实 `stargazers_count`，
/// 失败时回退 null（调用方回退到静态值）。
///
/// 设计原则（与 github_issue_publisher.dart 一致）：
/// - 永不抛异常到调用方：任何网络/解析错误都收敛为返回 null。
/// - 默认 10s 超时，避免卡死市场加载。
/// - 匿名请求（无 token）受 GitHub 未认证 rate limit 约束（60 req/h/IP），
///   批量拉取需控制并发；可选注入 token 提升配额。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/module/github_source.dart';

/// 下载远程 manifest JSON（M6 · 补 4）。
///
/// [url] 为 manifest 的下载地址。返回解析后的 Map；任何失败（网络/超时/404/
/// 非 JSON）返回 null（调用方回退或报错）。
Future<Map<String, dynamic>?> fetchManifestJson(
  String url, {
  Dio? dio,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = dio ?? Dio();
  try {
    final resp = await client.get(
      url,
      options: Options(
        responseType: ResponseType.json,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    if (resp.statusCode != 200) return null;
    final data = resp.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        return Map<String, dynamic>.from(
            jsonDecode(data) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 拉取单个 GitHub 仓库的 star 数。
///
/// [owner]/[repo] 为仓库全名两段。返回 `stargazers_count`；
/// 任何失败（网络/超时/404/解析）返回 null。
///
/// [dio] 可注入（测试传 mock）；[token] 可选，填入则带 Bearer 头提升 rate limit。
Future<int?> fetchGithubStars(
  String owner,
  String repo, {
  Dio? dio,
  String? token,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final client = dio ?? Dio();
  try {
    final resp = await client.get(
      'https://api.github.com/repos/$owner/$repo',
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          if (token != null && token.trim().isNotEmpty)
            'Authorization': 'Bearer ${token.trim()}',
        },
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    if (resp.statusCode != 200) return null;
    final data = resp.data;
    if (data is Map && data['stargazers_count'] is num) {
      return (data['stargazers_count'] as num).toInt();
    }
    return null;
  } on DioException {
    return null;
  } catch (_) {
    return null;
  }
}

/// 批量拉取 star 数，返回 `repoFullName -> stars` 的映射。
///
/// - 只对能解析出 `owner/repo` 的仓库发起请求。
/// - 逐条失败不影响其它；失败的仓库不出现在结果里（调用方回退静态值）。
/// - 串行请求 + 可选 [gap] 间隔，规避未认证 rate limit。
/// - [resolveRepo]：把「来源 URL」转成 `owner/repo`（可注入便于测试；
///   默认实现用 [parseGithubSource] 解析 GitHub URL）。
Future<Map<String, int>> fetchStarsBatch(
  List<String> repoUrls, {
  Dio? dio,
  String? token,
  Duration timeout = const Duration(seconds: 10),
  Duration gap = const Duration(milliseconds: 100),
  String? Function(String url)? resolveRepo,
}) async {
  final out = <String, int>{};
  for (final url in repoUrls) {
    final String? full = resolveRepo != null
        ? resolveRepo(url)
        : _defaultResolveRepo(url);
    if (full == null) continue;
    final slash = full.indexOf('/');
    if (slash <= 0 || slash == full.length - 1) continue;
    final owner = full.substring(0, slash);
    final repo = full.substring(slash + 1);
    final stars = await fetchGithubStars(owner, repo,
        dio: dio, token: token, timeout: timeout);
    if (stars != null) {
      out[full] = stars;
    }
    if (gap > Duration.zero) {
      await Future<void>.delayed(gap);
    }
  }
  return out;
}

/// 默认的 owner/repo 解析：复用 [parseGithubSource]。
///
/// 这里用 `deferred` 式动态 import 会引入额外复杂度；直接 `import` core 子包的
/// `github_source.dart`（主包可 import core 子包，反向不行）。放在文件顶部 import。
String? _defaultResolveRepo(String url) {
  try {
    final src = parseGithubSource(url);
    return src.fullName;
  } catch (_) {
    return null;
  }
}

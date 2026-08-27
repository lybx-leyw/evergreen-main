/// 专业研究检索工具：论文、代码仓库与学术出版物。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import '../tool.dart';

// ═══════ 共享检索逻辑 ═══════
//
// 网络请求与响应解析只在这里实现一次，供两类消费者复用：
//   1. ArxivSearchTool / GithubSearchTool / CrossrefSearchTool（类定义保留——
//      供探针 search_recall_probe 直接引用；Task 二 R2-5 起不再独立注册/显示，
//      统一入口为 web_search 的 mode）；
//   2. WebSearchTool 的 mode=arxiv / mode=github / mode=crossref / mode=all
//      （web_search 多来源召回——避免为同一来源重复实现网络请求）。
// 共享函数返回 (结果条目, 错误信息?)：error 非 null 表示检索失败（含原始异常），
// 此时条目不使用；成功时 error 为 null。

/// 共享 arXiv 检索（arXiv API，XML 响应）。
Future<(List<Map<String, dynamic>>, String?)> arxivSearchShared(
    Dio dio, String query, int maxResults) async {
  try {
    final r = await dio.get('https://export.arxiv.org/api/query', queryParameters: {
      'search_query': 'all:$query', 'start': 0, 'max_results': maxResults,
    }, options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10)));
    final xml = r.data?.toString() ?? '';
    final entries = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(xml).map((m) {
      final b = m.group(1)!;
      String pick(String tag) => RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>').firstMatch(b)?.group(1)?.trim() ?? '';
      final authors = RegExp(r'<author>[\s\S]*?<name>([\s\S]*?)</name>[\s\S]*?</author>').allMatches(b).map((m) => m.group(1)!.trim()).join(', ');
      final id = pick('id');
      return {'title': pick('title').replaceAll(RegExp(r'\s+'), ' '), 'authors': authors,
        'published': pick('published'), 'summary': pick('summary').replaceAll(RegExp(r'\s+'), ' '),
        'url': id, 'pdf': id.replaceFirst('/abs/', '/pdf/')};
    }).toList();
    return (entries, null);
  } catch (e) {
    return (const <Map<String, dynamic>>[], 'arxiv search failed: $e');
  }
}

/// 共享 GitHub 仓库检索（GitHub Search API，JSON 响应）。
Future<(List<Map<String, dynamic>>, String?)> githubSearchShared(
    Dio dio, String query, int maxResults) async {
  try {
    final r = await dio.get('https://api.github.com/search/repositories', queryParameters: {'q': query, 'per_page': maxResults}, options: Options(receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Evergreen-Research-Agent'}));
    final items = (r.data is Map ? (r.data['items'] as List? ?? const []) : const []).map((x) => {'name': x['full_name'], 'url': x['html_url'], 'description': x['description'], 'language': x['language'], 'stars': x['stargazers_count'], 'updatedAt': x['updated_at']}).toList();
    return (items, null);
  } catch (e) {
    return (const <Map<String, dynamic>>[], 'github search failed: $e');
  }
}

/// 共享 Crossref 学术检索（Crossref API，JSON 响应）。
Future<(List<Map<String, dynamic>>, String?)> crossrefSearchShared(
    Dio dio, String query, int maxResults) async {
  try {
    final r = await dio.get('https://api.crossref.org/works', queryParameters: {'query': query, 'rows': maxResults}, options: Options(receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10), headers: {'User-Agent': 'Evergreen-Research-Agent/1.0'}));
    final message = r.data is Map ? r.data['message'] : null;
    final raw = message is Map ? (message['items'] as List? ?? const []) : const [];
    String first(dynamic value) => value is List && value.isNotEmpty ? value.first.toString() : '';
    final items = raw.map((x) {
      final authors = (x['author'] as List? ?? const []).map((a) => '${a['given'] ?? ''} ${a['family'] ?? ''}'.trim()).join(', ');
      return {'title': first(x['title']), 'doi': x['DOI'], 'url': x['URL'], 'authors': authors, 'container': first(x['container-title']), 'published': x['published-print'] ?? x['published-online'] ?? x['created']};
    }).toList();
    return (items, null);
  } catch (e) {
    return (const <Map<String, dynamic>>[], 'crossref search failed: $e');
  }
}

class ArxivSearchTool extends Tool {
  final Dio dio;
  ArxivSearchTool(this.dio);
  @override String get name => 'arxiv_search';
  @override String get description => '检索 arXiv 论文，返回标题、作者、摘要、年份和 PDF 链接。';
  @override Map<String, dynamic> get schema => {'type': 'object', 'properties': {
    'query': {'type': 'string'}, 'max_results': {'type': 'integer', 'minimum': 1, 'maximum': 10},
  }, 'required': ['query']};
  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final q = args['query']?.toString().trim() ?? '';
    if (q.isEmpty) return '[error: arxiv query is empty]';
    if (q.length > 2048) return '[error: arxiv query exceeds 2048 characters]';
    final limit = ((args['max_results'] as num?)?.toInt() ?? 5).clamp(1, 10);
    final (entries, err) = await arxivSearchShared(dio, q, limit);
    if (err != null) return '[error: $err]';
    return jsonEncode({'source': 'arxiv', 'query': q, 'results': entries});
  }
}
class GithubSearchTool extends Tool {
  final Dio dio;
  GithubSearchTool(this.dio);
  @override String get name => 'github_search';
  @override String get description => '检索 GitHub 开源仓库，返回仓库地址、描述、语言、星标和更新时间。';
  @override Map<String, dynamic> get schema => {'type': 'object', 'properties': {'query': {'type': 'string'}, 'max_results': {'type': 'integer', 'minimum': 1, 'maximum': 10}}, 'required': ['query']};
  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final q = args['query']?.toString().trim() ?? '';
    if (q.isEmpty) return '[error: github query is empty]';
    if (q.length > 2048) return '[error: github query exceeds 2048 characters]';
    final limit = ((args['max_results'] as num?)?.toInt() ?? 5).clamp(1, 10);
    final (entries, err) = await githubSearchShared(dio, q, limit);
    if (err != null) return '[error: $err]';
    return jsonEncode({'source': 'github', 'query': q, 'results': entries});
  }
}

class CrossrefSearchTool extends Tool {
  final Dio dio;
  CrossrefSearchTool(this.dio);
  @override String get name => 'crossref_search';
  @override String get description => '检索 Crossref 学术出版物，返回 DOI、标题、作者、期刊和发表时间。';
  @override Map<String, dynamic> get schema => {'type': 'object', 'properties': {'query': {'type': 'string'}, 'max_results': {'type': 'integer', 'minimum': 1, 'maximum': 10}}, 'required': ['query']};
  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final q = args['query']?.toString().trim() ?? '';
    if (q.isEmpty) return '[error: crossref query is empty]';
    if (q.length > 2048) return '[error: crossref query exceeds 2048 characters]';
    final limit = ((args['max_results'] as num?)?.toInt() ?? 5).clamp(1, 10);
    final (entries, err) = await crossrefSearchShared(dio, q, limit);
    if (err != null) return '[error: $err]';
    return jsonEncode({'source': 'crossref', 'query': q, 'results': entries});
  }
}

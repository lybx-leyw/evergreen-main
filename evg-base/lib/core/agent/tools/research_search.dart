/// 专业研究检索工具：论文、代码仓库与学术出版物。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import '../tool.dart';

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
    try {
      final r = await dio.get('https://export.arxiv.org/api/query', queryParameters: {
        'search_query': 'all:$q', 'start': 0, 'max_results': limit,
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
      return jsonEncode({'source': 'arxiv', 'query': q, 'results': entries});
    } catch (e) { return '[error: arxiv search failed: $e]'; }
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
    try {
      final r = await dio.get('https://api.github.com/search/repositories', queryParameters: {'q': q, 'per_page': limit}, options: Options(receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Evergreen-Research-Agent'}));
      final items = (r.data is Map ? (r.data['items'] as List? ?? const []) : const []).map((x) => {'name': x['full_name'], 'url': x['html_url'], 'description': x['description'], 'language': x['language'], 'stars': x['stargazers_count'], 'updatedAt': x['updated_at']}).toList();
      return jsonEncode({'source': 'github', 'query': q, 'results': items});
    } catch (e) { return '[error: github search failed: $e]'; }
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
    try {
      final r = await dio.get('https://api.crossref.org/works', queryParameters: {'query': q, 'rows': limit}, options: Options(receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 10), headers: {'User-Agent': 'Evergreen-Research-Agent/1.0'}));
      final message = r.data is Map ? r.data['message'] : null;
      final raw = message is Map ? (message['items'] as List? ?? const []) : const [];
      String first(dynamic value) => value is List && value.isNotEmpty ? value.first.toString() : '';
      final items = raw.map((x) {
        final authors = (x['author'] as List? ?? const []).map((a) => '${a['given'] ?? ''} ${a['family'] ?? ''}'.trim()).join(', ');
        return {'title': first(x['title']), 'doi': x['DOI'], 'url': x['URL'], 'authors': authors, 'container': first(x['container-title']), 'published': x['published-print'] ?? x['published-online'] ?? x['created']};
      }).toList();
      return jsonEncode({'source': 'crossref', 'query': q, 'results': items});
    } catch (e) { return '[error: crossref search failed: $e]'; }
  }
}

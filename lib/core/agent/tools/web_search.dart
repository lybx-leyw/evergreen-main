/// Web Search 工具——让 Agent 可以搜索网络。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../tool.dart';

/// 网络搜索工具——使用搜索引擎查询信息。
class WebSearchTool extends Tool {
  final Dio _dio;

  WebSearchTool(this._dio);

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索网络获取最新信息。当你需要回答用户关于实时事件、最新新闻、学术资料等需要联网获取的内容时使用。参数 query 为搜索关键词。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，尽量用中文，简洁准确',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return '[error: 搜索关键词为空]';

    // 直接使用 Bing 搜索（国内可访问），跳过 DuckDuckGo（被屏蔽）
    try {
      return await _searchBing(query);
    } catch (e) {
      return '[搜索失败: $e]';
    }
  }

  Future<String> _searchBing(String query) async {
    try {
      // 先用 cn.bing.com（国内镜像），失败再试 www.bing.com
      final hosts = ['https://cn.bing.com', 'https://www.bing.com'];
      String? html;

      for (final host in hosts) {
        try {
          final response = await _dio.get(
            '$host/search',
            queryParameters: {'q': query, 'cc': 'cn'},
            options: Options(
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            ),
          );
          html = response.data?.toString() ?? '';
          if (html!.isNotEmpty) break;
        } catch (_) {
          continue;
        }
      }

      if (html == null || html.isEmpty) return '[搜索失败: 无法连接搜索服务]';

      // 提取搜索结果——适应多种 HTML 结构
      final results = <String>[];

      // Bing 新版：<li class="b_algo"> 或者 <li class="b_algo_">
      final algoRegex = RegExp(r'<li[^>]*class="b_algo[^"]*"[^>]*>(.*?)</li>',
          dotAll: true);
      for (final match in algoRegex.allMatches(html)) {
        final block = match.group(1) ?? '';
        // 提取标题
        final titleMatch =
            RegExp(r'<h2[^>]*>.*?<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
                    dotAll: true)
                .firstMatch(block);
        final title = titleMatch?.group(2)
                ?.replaceAll(RegExp(r'<[^>]*>'), '')
                .trim() ??
            '';
        final url = titleMatch?.group(1) ?? '';
        // 提取摘要（多种可能的结构）
        final snippetMatch = RegExp(
                r'<p[^>]*class="b_lineclamp[^"]*"[^>]*>(.*?)</p>',
                dotAll: true)
            .firstMatch(block);
        final snippet = snippetMatch?.group(1)
                ?.replaceAll(RegExp(r'<[^>]*>'), '')
                .trim() ??
            '';
        if (title.isNotEmpty) {
          var entry = title;
          if (snippet.isNotEmpty) entry += '\n  $snippet';
          if (url.isNotEmpty) entry += '\n  $url';
          results.add(entry);
        }
      }

      if (results.isNotEmpty) {
        return '搜索 "$query" 的结果:\n\n${results.take(5).join('\n\n')}';
      }
      return '未找到 "$query" 的相关结果。';
    } catch (e) {
      return '[搜索失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}

/// 网页获取工具——抓取指定 URL 的文本内容。
class WebFetchTool extends Tool {
  final Dio _dio;

  WebFetchTool(this._dio);

  @override
  String get name => 'web_fetch';

  @override
  String get description => '获取指定 URL 的文本内容。当你需要查看某个网页的具体内容时使用。参数 url 为需要访问的网页地址。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '需要获取内容的网页 URL',
          },
        },
        'required': ['url'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final url = args['url']?.toString() ?? '';
    if (url.isEmpty) return '[error: URL 为空]';

    try {
      final response = await _dio.get(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) return '页面内容为空';

      // 提取正文（去除 HTML 标签、压缩空白）
      final bodyMatch = RegExp(r'<body[^>]*>(.*?)</body>', dotAll: true)
          .firstMatch(html);
      final body = bodyMatch?.group(1) ?? html;

      // 去除 script 和 style
      final cleaned = body
          .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
          .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // 截断到 4000 字符
      if (cleaned.length > 4000) {
        return '${cleaned.substring(0, 4000)}\n\n[内容过长，已截断]';
      }
      return cleaned;
    } catch (e) {
      return '[获取页面失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}

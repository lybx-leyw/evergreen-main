/// Agent 工具：网络搜索与网页获取。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../tool.dart';

// ═══════ WebSearchTool ═══════

/// 使用搜索引擎查询信息。
class WebSearchTool extends Tool {
  final Dio _dio;

  WebSearchTool(this._dio);

  /// 结果条数默认值（缺省 = 现状 take(5)，零行为变化）。
  static const int maxResultsDefault = 5;

  /// 结果条数上限（与 schema 一致）。
  static const int maxResultsCap = 10;

  /// 正常结果页的最小长度阈值：低于此值视为跳转/验证/错误页（被反爬）。
  static const int minNormalPageLength = 1000;

  /// HTML 抓取上限（保留现状 8MiB 截断）。
  static const int htmlCap = 8 * 1024 * 1024;

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索网络获取最新信息。当你需要回答用户关于实时事件、最新新闻、学术资料等需要联网获取的内容时使用。参数 query 为搜索关键词，max_results 为返回结果条数（1-10，默认 5）。';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词，尽量用中文，简洁准确',
          },
          'max_results': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 10,
            'description': '返回结果条数（1-10，默认 5）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return '[error: 搜索关键词为空]';
    final maxResults = _parseMaxResults(args);

    // 直接使用 Bing 搜索（国内可访问），跳过 DuckDuckGo（被屏蔽）
    try {
      return await _searchBing(query, maxResults);
    } catch (e) {
      return '[搜索失败: $e]';
    }
  }

  /// 解析 max_results：缺省 5；0/负值/超上限 clamp 到 1-10；
  /// 非法字符串回退默认 5；合法数字字符串（如 "7"）按数字处理。
  static int _parseMaxResults(Map<String, dynamic> args) {
    final raw = args['max_results'];
    if (raw is num) return raw.toInt().clamp(1, maxResultsCap);
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed.clamp(1, maxResultsCap);
    }
    return maxResultsDefault;
  }

  /// 从结果 URL 提取来源域名，供 LLM 判断来源可信度（轻量，不搬整套证据层）。
  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host;
  }

  Future<String> _searchBing(String query, int maxResults) async {
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
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept-Language': 'zh-CN,zh;q=0.9',
              },
            ),
          );
          if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
            continue;
          }
          html = response.data?.toString() ?? '';
          if (html.isNotEmpty) break;
        } catch (_) {
          continue;
        }
      }

      // 结构化错误 ①：网络失败（双 host 均不可达/无响应体）。
      if (html == null || html.isEmpty) {
        return '[搜索失败: 无法连接搜索服务]';
      }
      if (html.length > htmlCap) {
        html = html.substring(0, htmlCap);
      }

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
          // 附加来源域名，便于 LLM 判断可信度。
          final host = _hostOf(url);
          if (host.isNotEmpty) entry += '\n  来源: $host';
          results.add(entry);
        }
      }

      if (results.isNotEmpty) {
        return '搜索 "$query" 的结果:\n\n${results.take(maxResults).join('\n\n')}';
      }
      // 结构化错误 ②③：无 b_algo 结果块时，按页面长度区分
      // 「未找到结果」与「被反爬/异常页面（可能被限流）」。长度异常 = 过短
      // （跳转/验证页）或达到 8MiB 截断上限（JS 渲染/验证大页）。
      if (html.length < minNormalPageLength || html.length >= htmlCap) {
        return '[搜索失败: 搜索服务返回异常页面（可能被限流），请稍后重试]';
      }
      return '[搜索失败: 未找到结果]';
    } catch (e) {
      return '[搜索失败: $e]';
    }
  }

  @override
  bool get readOnly => true;
}

// ═══════ WebFetchTool ═══════

/// 抓取指定 URL 的文本内容。
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
    if (url.length > 8192) return '[error: URL 超过 8192 字符上限]';
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty || parsed.userInfo.isNotEmpty || !{'http', 'https'}.contains(parsed.scheme.toLowerCase())) {
      return '[error: 仅允许有效的 http/https URL]';
    }
    final host = parsed.host.toLowerCase();
    final privateIpv4 = RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)').hasMatch(host);
    final privateIpv6 = host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe80:');
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '0.0.0.0' || host == '169.254.169.254' || privateIpv4 || privateIpv6) {
      return '[error: 禁止访问本机或云元数据地址]';
    }
    try {
      final resolved = await InternetAddress.lookup(host);
      if (resolved.any((a) => a.isLoopback || a.isLinkLocal || RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)').hasMatch(a.address) || a.address.startsWith('fc') || a.address.startsWith('fd'))) {
        return '[error: DNS 解析到受限内网地址]';
      }
    } catch (_) { return '[error: 无法解析目标主机]'; }

    try {
      final response = await _dio.get(
        url,
        options: Options(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        return '[获取页面失败: HTTP ${response.statusCode}]';
      }

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) return '页面内容为空';
      if (html.length > 12 * 1024 * 1024) {
        return '[获取页面失败: 页面超过 12MiB 处理上限]';
      }

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

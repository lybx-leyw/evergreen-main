/// Agent 工具：网络搜索与网页获取。
library;

import 'dart:io';

import 'package:dio/dio.dart';

import '../tool.dart';
import 'research_search.dart';

// ═══════ WebSearchTool ═══════

/// web_search 的搜索来源 mode（Task 二 R2 多来源召回 + R2-5 统一入口）。
enum WebSearchMode {
  /// 网络搜索（缺省值——行为与返工前完全一致）。
  network,

  /// arXiv 论文检索（复用 research_search.dart 的共享逻辑）。
  arxiv,

  /// GitHub 仓库检索（复用 research_search.dart 的共享逻辑）。
  github,

  /// Crossref 学术出版物检索（复用 research_search.dart 的共享逻辑）。
  crossref,

  /// 四来源（网络 + arxiv + github + crossref）四合一一并召回，结果区分来源。
  all,
}

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

  /// mode=all 时 max_results 的分配策略（文档化，Task 二 R2-5 四来源）：
  /// 四来源均分（maxResults ~/ 4），余数全部优先给网络；分配为 0 的来源
  /// 直接跳过（不发起请求）。
  /// 例：max_results=5 → 网络 2 / arxiv 1 / github 1 / crossref 1；
  ///     =10 → 4/2/2/2；=1 → 1/0/0/0；=4 → 1/1/1/1。
  static (int, int, int, int) _splitForAll(int maxResults) {
    final per = maxResults ~/ 4;
    final rem = maxResults % 4;
    return (
      per + rem,
      per,
      per,
      per,
    );
  }

  /// 解析 mode：缺省/非法值静默回退到 [WebSearchMode.network]（未知静默忽略原则）；
  /// 字符串忽略大小写与首尾空白。
  static WebSearchMode _parseMode(dynamic raw) {
    if (raw is String) {
      switch (raw.trim().toLowerCase()) {
        case 'arxiv':
          return WebSearchMode.arxiv;
        case 'github':
          return WebSearchMode.github;
        case 'crossref':
          return WebSearchMode.crossref;
        case 'all':
          return WebSearchMode.all;
        case 'network':
          return WebSearchMode.network;
      }
    }
    return WebSearchMode.network;
  }

  @override
  String get name => 'web_search';

  @override
  String get description => '搜索获取最新信息（多来源统一入口）。当你需要回答用户关于实时事件、最新新闻、学术资料、开源代码等需要联网获取的内容时使用。参数 query 为搜索关键词，max_results 为返回结果条数（1-10，默认 5），mode 为搜索来源：network（默认，网络搜索）/ arxiv（arXiv 论文）/ github（GitHub 仓库）/ crossref（Crossref 学术出版物）/ all（四来源合并召回，结果带 [网络]/[arxiv]/[github]/[crossref] 来源标记）。';

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
            'description': '返回结果条数（1-10，默认 5）；mode=all 时四来源均分，余数优先网络',
          },
          'mode': {
            'type': 'string',
            'enum': ['network', 'arxiv', 'github', 'crossref', 'all'],
            'description':
                '搜索来源：network（默认，网络搜索）/ arxiv（arXiv 论文）/ github（GitHub 仓库）/ crossref（Crossref 学术出版物）/ all（四来源合并召回，结果带来源标记）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) return '[error: 搜索关键词为空]';
    final maxResults = _parseMaxResults(args);
    final mode = _parseMode(args['mode']);

    switch (mode) {
      case WebSearchMode.arxiv:
        return _searchArxiv(query, maxResults);
      case WebSearchMode.github:
        return _searchGithub(query, maxResults);
      case WebSearchMode.crossref:
        return _searchCrossref(query, maxResults);
      case WebSearchMode.all:
        return _searchAll(query, maxResults);
      case WebSearchMode.network:
        // 缺省 / 非法 mode → 现状网络搜索（铁律：零行为变化）。
        final (entries, err) = await _fetchBingEntries(query);
        if (err != null) return '[搜索失败: $err]';
        return '搜索 "$query" 的结果:\n\n${entries.take(maxResults).join('\n\n')}';
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

  /// mode=arxiv 单来源：复用 research_search.dart 的 [arxivSearchShared]，
  /// 结果以 web_search 文本条目格式输出，每条带 [arxiv] 来源标记。
  Future<String> _searchArxiv(String query, int maxResults) async {
    final (entries, err) = await arxivSearchShared(_dio, query, maxResults);
    if (err != null) return '[搜索失败: $err]';
    if (entries.isEmpty) return '[搜索失败: 未找到结果]';
    final body = entries.take(maxResults).map(_arxivEntryToText).join('\n\n');
    return '搜索 "$query" 的结果（来源: arxiv）:\n\n$body';
  }

  /// mode=github 单来源：复用 research_search.dart 的 [githubSearchShared]，
  /// 结果以 web_search 文本条目格式输出，每条带 [github] 来源标记。
  Future<String> _searchGithub(String query, int maxResults) async {
    final (entries, err) = await githubSearchShared(_dio, query, maxResults);
    if (err != null) return '[搜索失败: $err]';
    if (entries.isEmpty) return '[搜索失败: 未找到结果]';
    final body = entries.take(maxResults).map(_githubEntryToText).join('\n\n');
    return '搜索 "$query" 的结果（来源: github）:\n\n$body';
  }

  /// mode=crossref 单来源：复用 research_search.dart 的 [crossrefSearchShared]，
  /// 结果以 web_search 文本条目格式输出，每条带 [crossref] 来源标记。
  Future<String> _searchCrossref(String query, int maxResults) async {
    final (entries, err) = await crossrefSearchShared(_dio, query, maxResults);
    if (err != null) return '[搜索失败: $err]';
    if (entries.isEmpty) return '[搜索失败: 未找到结果]';
    final body = entries.take(maxResults).map(_crossrefEntryToText).join('\n\n');
    return '搜索 "$query" 的结果（来源: crossref）:\n\n$body';
  }

  /// mode=all 四合一召回：网络 + arxiv + github + crossref 一并召回，max_results
  /// 按 [_splitForAll] 均分（余数优先网络）；每条结果带来源标记；单来源失败
  /// 不阻塞其余来源，全部失败才返回整体失败。
  Future<String> _searchAll(String query, int maxResults) async {
    final (netN, arxN, gitN, crfN) = _splitForAll(maxResults);
    final sections = <String>[];
    final failures = <String>[];

    if (netN > 0) {
      final (entries, err) = await _fetchBingEntries(query);
      if (err != null) {
        failures.add('网络: $err');
      } else if (entries.isEmpty) {
        failures.add('网络: 未找到结果');
      } else {
        sections.add(entries.take(netN).map((e) => '[网络] $e').join('\n\n'));
      }
    }

    if (arxN > 0) {
      final (entries, err) = await arxivSearchShared(_dio, query, arxN);
      if (err != null) {
        failures.add('arxiv: $err');
      } else if (entries.isEmpty) {
        failures.add('arxiv: 未找到结果');
      } else {
        sections.add(entries.take(arxN).map(_arxivEntryToText).join('\n\n'));
      }
    }

    if (gitN > 0) {
      final (entries, err) = await githubSearchShared(_dio, query, gitN);
      if (err != null) {
        failures.add('github: $err');
      } else if (entries.isEmpty) {
        failures.add('github: 未找到结果');
      } else {
        sections.add(entries.take(gitN).map(_githubEntryToText).join('\n\n'));
      }
    }

    if (crfN > 0) {
      final (entries, err) = await crossrefSearchShared(_dio, query, crfN);
      if (err != null) {
        failures.add('crossref: $err');
      } else if (entries.isEmpty) {
        failures.add('crossref: 未找到结果');
      } else {
        sections.add(entries.take(crfN).map(_crossrefEntryToText).join('\n\n'));
      }
    }

    if (sections.isEmpty) {
      return '[搜索失败: ${failures.join('；')}]';
    }
    final header = '搜索 "$query" 的结果（来源: 网络+arxiv+github+crossref）:';
    final body = sections.join('\n\n');
    if (failures.isEmpty) return '$header\n\n$body';
    return '$header\n\n$body\n\n[部分来源失败: ${failures.join('；')}]';
  }

  /// arXiv 条目 → web_search 文本条目（带 [arxiv] 标记，摘要截断到 300 字符）。
  static String _arxivEntryToText(Map<String, dynamic> r) {
    final buf = StringBuffer('[arxiv] ${r['title'] ?? ''}');
    final authors = (r['authors'] ?? '').toString();
    if (authors.isNotEmpty) buf.write('\n  作者: $authors');
    final summary = (r['summary'] ?? '').toString();
    if (summary.isNotEmpty) buf.write('\n  摘要: ${_truncate(summary, 300)}');
    final url = (r['url'] ?? '').toString();
    if (url.isNotEmpty) buf.write('\n  $url');
    return buf.toString();
  }

  /// GitHub 条目 → web_search 文本条目（带 [github] 标记，描述截断到 200 字符）。
  static String _githubEntryToText(Map<String, dynamic> r) {
    final buf = StringBuffer('[github] ${r['name'] ?? ''}');
    final desc = (r['description'] ?? '').toString();
    if (desc.isNotEmpty) buf.write('\n  描述: ${_truncate(desc, 200)}');
    final meta = <String>[];
    final lang = (r['language'] ?? '').toString();
    if (lang.isNotEmpty) meta.add('语言: $lang');
    final stars = r['stars'];
    if (stars is num) meta.add('★ $stars');
    final updated = (r['updatedAt'] ?? '').toString();
    if (updated.isNotEmpty) meta.add('更新: $updated');
    if (meta.isNotEmpty) buf.write('\n  ${meta.join(' | ')}');
    final url = (r['url'] ?? '').toString();
    if (url.isNotEmpty) buf.write('\n  $url');
    return buf.toString();
  }

  /// Crossref 条目 → web_search 文本条目（带 [crossref] 标记，作者截断到 200 字符）。
  static String _crossrefEntryToText(Map<String, dynamic> r) {
    final buf = StringBuffer('[crossref] ${r['title'] ?? ''}');
    final authors = (r['authors'] ?? '').toString();
    if (authors.isNotEmpty) buf.write('\n  作者: ${_truncate(authors, 200)}');
    final container = (r['container'] ?? '').toString();
    if (container.isNotEmpty) buf.write('\n  期刊: $container');
    final doi = (r['doi'] ?? '').toString();
    if (doi.isNotEmpty) buf.write('\n  DOI: $doi');
    var url = (r['url'] ?? '').toString();
    if (url.isEmpty && doi.isNotEmpty) url = 'https://doi.org/$doi';
    if (url.isNotEmpty) buf.write('\n  $url');
    return buf.toString();
  }

  /// 截断到 [max] 字符（按字符数，避免截断半个代理对），超过加省略号。
  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// 从结果 URL 提取来源域名，供 LLM 判断来源可信度（轻量，不搬整套证据层）。
  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host;
  }

  /// 网络搜索核心：Bing 抓取 + 结果提取，返回 (条目列表, 错误原因?)。
  /// 错误原因非 null 表示失败（裸原因，不含「[搜索失败: ...]」外壳——
  /// 由调用方按场景包装，缺省 mode 包装后与返工前输出逐字节一致）。
  Future<(List<String>, String?)> _fetchBingEntries(String query) async {
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
        return (const <String>[], '无法连接搜索服务');
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

      if (results.isNotEmpty) return (results, null);
      // 结构化错误 ②③：无 b_algo 结果块时，按页面长度区分
      // 「未找到结果」与「被反爬/异常页面（可能被限流）」。长度异常 = 过短
      // （跳转/验证页）或达到 8MiB 截断上限（JS 渲染/验证大页）。
      if (html.length < minNormalPageLength || html.length >= htmlCap) {
        return (const <String>[], '搜索服务返回异常页面（可能被限流），请稍后重试');
      }
      return (const <String>[], '未找到结果');
    } catch (e) {
      return (const <String>[], '$e');
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

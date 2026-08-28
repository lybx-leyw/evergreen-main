// WebSearchTool 单元测试（Task 二 A2 交付物 4 + R2 多来源召回 + R2-5 统一入口）。
//
// 覆盖：
//   - schema：query + max_results（integer 1-10）+ mode（network/arxiv/github/crossref/all）
//   - max_results 解析：缺省 5 / 0·负值·超上限 clamp / 非法字符串回退 / 合法数字字符串
//   - 结构化错误：网络失败（无法连接搜索服务）/ 未找到结果 / 被反爬（长度异常页面）
//   - 结果条目：每条附加来源域名；双 host 回退；max_results 不进 Bing 请求参数
//   - mode 路由（Task 二 R2/R2-5）：单来源 arxiv/github/crossref、四合一 all、
//     缺省零行为变化、非法值静默回退、all 下 max_results 四源均分（余数优先网络）、
//     单来源失败不阻塞其余来源
//
// 运行：cd evg-base/lib/core/agent && dart test test/web_search_test.dart -j 1
// 依赖：dio stub（lib/dio_stub），不依赖真实网络。
library;

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../tools/web_search.dart';

/// 可控 Dio 替身：按 [responses] 列表依次返回（Response 或 Exception）。
/// web_search 双 host 回退依次请求 cn.bing.com → www.bing.com，因此列表顺序
/// 即各 host 的响应顺序；列表耗尽后重复最后一个元素。
class _StubDio extends Dio {
  _StubDio();

  final List<Object> responses = [];
  final List<String> requestPaths = [];
  final List<Map<String, dynamic>> queryParams = [];
  int _calls = 0;

  @override
  Future<Response> get(String path,
      {Object? queryParameters, Options? options}) async {
    requestPaths.add(path);
    queryParams.add(queryParameters == null
        ? const {}
        : Map<String, dynamic>.from(queryParameters as Map));
    final idx =
        _calls < responses.length ? _calls : responses.length - 1;
    _calls++;
    final r = responses[idx];
    if (r is Exception) throw r;
    return r as Response;
  }
}

/// 构造含 count 个 b_algo 结果块的模拟 Bing HTML。
/// [pad] 用于控制页面长度（被反爬长度判定用）；urlPrefix 控制来源域名。
String _bingHtml(int count,
    {String urlPrefix = 'https://example.com', int pad = 0}) {
  final buf = StringBuffer('<html><body>');
  buf.write(' ' * pad);
  for (var i = 1; i <= count; i++) {
    buf.write('<li class="b_algo"><h2><a href="$urlPrefix/page$i">标题 $i</a>'
        '</h2><p class="b_lineclamp">摘要 $i</p></li>');
  }
  buf.write('</body></html>');
  return buf.toString();
}

/// 构造含 count 个 item 的模拟 Bing RSS（format=rss 标准 XML）。
/// 标题/链接/摘要分别带 HTML 实体与 CDATA 变体，验证 XML 解析反转义。
String _bingRss(int count) {
  final buf = StringBuffer('<?xml version="1.0" encoding="utf-8"?>'
      '<rss version="2.0"><channel><title>必应：query</title>');
  for (var i = 1; i <= count; i++) {
    final snippet = i.isEven
        ? '<![CDATA[摘要 <b>$i</b> 带实体 &amp; 标签]]>'
        : '摘要 $i &amp; 实体';
    buf.write('<item>'
        '<title>RSS 标题 $i</title>'
        '<link>https://docs.example.net/page$i</link>'
        '<description>$snippet</description>'
        '<pubDate>周四, 27 8月 2026 10:00:00 GMT</pubDate>'
        '</item>');
  }
  buf.write('</channel></rss>');
  return buf.toString();
}

/// 统计 web_search 成功输出中的条目数。
int _entryCount(String out) {
  final idx = out.indexOf('\n\n');
  if (idx < 0) return 0;
  return out
      .substring(idx + 2)
      .split('\n\n')
      .where((e) => e.trim().isNotEmpty)
      .length;
}

/// 统计带指定来源标记（[网络]/[arxiv]/[github]）的条目数。
int _entryCountByMarker(String out, String marker) {
  final idx = out.indexOf('\n\n');
  if (idx < 0) return 0;
  return out
      .substring(idx + 2)
      .split('\n\n')
      .where((e) => e.trim().startsWith(marker))
      .length;
}

/// 构造含 count 个 entry 的模拟 arXiv Atom XML。
String _arxivXml(int count) {
  final buf = StringBuffer('<?xml version="1.0" encoding="UTF-8"?><feed>');
  for (var i = 1; i <= count; i++) {
    buf.write('<entry>'
        '<id>https://arxiv.org/abs/2301.0000$i</id>'
        '<title>Arxiv Paper $i</title>'
        '<author><name>Author $i</name></author>'
        '<published>2023-01-0$i</published>'
        '<summary>Summary of paper $i.</summary>'
        '</entry>');
  }
  buf.write('</feed>');
  return buf.toString();
}

/// 构造含 count 个仓库的模拟 GitHub Search JSON（Map 形式，等价 dio JSON 解码）。
Map<String, dynamic> _githubJson(int count) {
  return {
    'total_count': count,
    'items': List.generate(count, (i) => {
          'full_name': 'owner/repo$i',
          'html_url': 'https://github.com/owner/repo$i',
          'description': 'Repo description $i',
          'language': 'Dart',
          'stargazers_count': 100 + i,
          'updated_at': '2026-01-0${i + 1}T00:00:00Z',
        }),
  };
}

/// 构造含 count 条作品的模拟 Crossref JSON（Map 形式，等价 dio JSON 解码）。
Map<String, dynamic> _crossrefJson(int count) {
  return {
    'message': {
      'items': List.generate(count, (i) => {
            'title': ['Crossref Paper $i'],
            'DOI': '10.1000/paper$i',
            'URL': 'https://doi.org/10.1000/paper$i',
            'author': [
              {'given': 'Given$i', 'family': 'Family$i'},
            ],
            'container-title': ['Journal $i'],
            'published-print': {
              'date-parts': [
                [2024, 1, i + 1]
              ]
            },
          }),
    },
  };
}

void main() {
  group('WebSearchTool.schema', () {
    test('query 必填，max_results 为 integer 1-10（缺省 5 语义）', () {
      final tool = WebSearchTool(_StubDio());
      expect(tool.name, 'web_search');
      expect(tool.readOnly, isTrue);
      expect(tool.schema['required'], ['query']);
      final props = tool.schema['properties'] as Map<String, dynamic>;
      final mr = props['max_results'] as Map<String, dynamic>;
      expect(mr['type'], 'integer');
      expect(mr['minimum'], 1);
      expect(mr['maximum'], 10);
    });
  });

  group('max_results 解析', () {
    test('缺省 5 条（与现状 take(5) 行为一致）', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, startsWith('搜索 "flutter" 的结果:'));
      expect(_entryCount(out), 5);
    });

    test('max_results: 3 → 3 条', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'flutter', 'max_results': 3});
      expect(_entryCount(out), 3);
    });

    test('max_results: 0 / 负值 clamp 到 1', () async {
      for (final v in [0, -5]) {
        final dio = _StubDio()
          ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
        final out = await WebSearchTool(dio)
            .execute({'query': 'flutter', 'max_results': v});
        expect(_entryCount(out), 1, reason: 'max_results=$v 应 clamp 到 1');
      }
    });

    test('max_results: 15 超上限 clamp 到 10', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(15)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'flutter', 'max_results': 15});
      expect(_entryCount(out), 10);
    });

    test('字符串非法回退默认 5；合法数字字符串按数字（"7" → 7）', () async {
      final dioBad = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
      final outBad = await WebSearchTool(dioBad)
          .execute({'query': 'flutter', 'max_results': 'abc'});
      expect(_entryCount(outBad), 5, reason: '非法字符串应回退默认 5');

      final dioOk = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
      final outOk = await WebSearchTool(dioOk)
          .execute({'query': 'flutter', 'max_results': '7'});
      expect(_entryCount(outOk), 7, reason: '合法数字字符串应按数字解析');
    });

    test('max_results 不进 Bing 请求参数（仅本地裁剪），q 透传', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(8)));
      await WebSearchTool(dio)
          .execute({'query': 'flutter', 'max_results': 3});
      final params = dio.queryParams.single;
      expect(params['q'], 'flutter');
      expect(params.containsKey('max_results'), isFalse);
    });
  });

  group('结构化错误', () {
    test('双 host 网络异常 → 无法连接搜索服务', () async {
      final dio = _StubDio()
        ..responses.addAll([
          DioException(message: 'Connection refused'),
          DioException(message: 'Connection timed out'),
        ]);
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, '[搜索失败: 无法连接搜索服务]');
      expect(dio.requestPaths.length, 2, reason: '双 host 均失败');
    });

    test('双 host 非 2xx 状态码 → 无法连接搜索服务', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 503, data: ''),
          Response(statusCode: 403, data: ''),
        ]);
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, '[搜索失败: 无法连接搜索服务]');
    });

    test('空 HTML → 无法连接搜索服务', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: ''),
          Response(statusCode: 200, data: ''),
        ]);
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, '[搜索失败: 无法连接搜索服务]');
    });

    test('无 b_algo 且长度正常 → 未找到结果', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: '<html><body>${'x' * 2000}</body></html>'));
      final out = await WebSearchTool(dio).execute({'query': 'nonexistent'});
      expect(out, '[搜索失败: 未找到结果]');
    });

    test('无 b_algo 且页面过短 → 被反爬（可能被限流）', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: '<html><body>verify</body></html>'));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, '[搜索失败: 搜索服务返回异常页面（可能被限流），请稍后重试]');
    });

    test('无 b_algo 且达到 8MiB 截断上限 → 被反爬（可能被限流）', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: '<html><body>${' ' * (8 * 1024 * 1024 + 10)}</body></html>'));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, '[搜索失败: 搜索服务返回异常页面（可能被限流），请稍后重试]');
    });
  });

  group('结果条目与回退', () {
    test('每条附来源域名（host）', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: _bingHtml(2, urlPrefix: 'https://docs.flutter.dev')));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, contains('来源: docs.flutter.dev'));
      expect(out, contains('https://docs.flutter.dev/page1'));
      expect(out, contains('标题 1'));
    });

    test('双 host 回退：首个 host 异常、次个成功', () async {
      final dio = _StubDio()
        ..responses.addAll([
          DioException(message: 'conn refused'),
          Response(statusCode: 200, data: _bingHtml(2)),
        ]);
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, startsWith('搜索 "flutter" 的结果:'));
      expect(_entryCount(out), 2);
      expect(dio.requestPaths.length, 2);
      expect(dio.requestPaths[0], startsWith('https://cn.bing.com'));
      expect(dio.requestPaths[1], startsWith('https://www.bing.com'));
    });

    test('首个 host 返回空体、次个成功（html 非空即 break）', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: ''),
          Response(statusCode: 200, data: _bingHtml(3)),
        ]);
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(_entryCount(out), 3);
    });

    test('RSS 响应（format=rss XML）→ XML 解析出条目', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingRss(4)));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, startsWith('搜索 "flutter" 的结果:'));
      expect(_entryCount(out), 4);
      expect(out, contains('RSS 标题 1'));
      expect(out, contains('https://docs.example.net/page1'));
      expect(out, contains('来源: docs.example.net'));
    });

    test('RSS XML 实体与 CDATA 反转义/剥标签', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingRss(2)));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      // 奇数条：`摘要 1 &amp; 实体` → `摘要 1 & 实体`
      expect(out, contains('摘要 1 & 实体'));
      // 偶数条：CDATA `<b>2</b>` 剥标签 + `&amp;` → `摘要 2 带实体 & 标签`
      expect(out, contains('摘要 2 带实体 & 标签'));
    });

    test('RSS 响应但 0 条目 → 未找到结果（不判反爬）', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: '<?xml version="1.0"?><rss version="2.0"><channel>'
                '<title>必应：nonexistent</title></channel></rss>'));
      final out = await WebSearchTool(dio).execute({'query': 'nonexistent'});
      expect(out, '[搜索失败: 未找到结果]');
    });

    test('请求带 format=rss 参数；max_results 不进请求参数', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingRss(3)));
      await WebSearchTool(dio)
          .execute({'query': 'flutter', 'max_results': 3});
      final params = dio.queryParams.single;
      expect(params['q'], 'flutter');
      expect(params['format'], 'rss', reason: '应请求 Bing RSS 通道');
      expect(params.containsKey('max_results'), isFalse);
    });
  });

  group('mode 参数与 schema', () {
    test('schema 含 mode：enum network/arxiv/github/crossref/all', () {
      final tool = WebSearchTool(_StubDio());
      final props = tool.schema['properties'] as Map<String, dynamic>;
      final mode = props['mode'] as Map<String, dynamic>;
      expect(mode['type'], 'string');
      expect(mode['enum'], ['network', 'arxiv', 'github', 'crossref', 'all']);
    });

    test('mode 缺省 = 现状网络搜索（零行为变化：仅 Bing，无来源标记）', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(6)));
      final out = await WebSearchTool(dio).execute({'query': 'flutter'});
      expect(out, startsWith('搜索 "flutter" 的结果:'));
      expect(_entryCount(out), 5, reason: '缺省 max_results=5');
      expect(out, isNot(contains('[网络]')));
      expect(out, isNot(contains('[arxiv]')));
      expect(out, isNot(contains('[github]')));
      expect(dio.requestPaths.single, startsWith('https://cn.bing.com'));
    });

    test('mode: network 与缺省完全一致', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(6)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'flutter', 'mode': 'network'});
      expect(out, startsWith('搜索 "flutter" 的结果:'));
      expect(out, isNot(contains('[网络]')));
      expect(dio.requestPaths.single, startsWith('https://cn.bing.com'));
    });

    test('非法 mode（未知字符串/空串/数字）静默回退到网络搜索', () async {
      for (final bad in ['foo', '', '   ', 123, null]) {
        final dio = _StubDio()
          ..responses.add(Response(statusCode: 200, data: _bingHtml(6)));
        final args = <String, dynamic>{'query': 'flutter'};
        if (bad != null) args['mode'] = bad;
        final out = await WebSearchTool(dio).execute(args);
        expect(out, startsWith('搜索 "flutter" 的结果:'),
            reason: 'mode=$bad 应回退网络搜索');
        expect(out, isNot(contains('[网络]')), reason: 'mode=$bad 不应带来源标记');
        expect(dio.requestPaths.single, startsWith('https://cn.bing.com'),
            reason: 'mode=$bad 应只请求 Bing');
      }
    });

    test('mode 忽略大小写与首尾空白（"  ARXIV " → arxiv）', () async {
      final dio = _StubDio()
        ..responses.add(Response(
            statusCode: 200,
            data: _arxivXml(2)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'llm', 'mode': '  ARXIV '});
      expect(out, startsWith('搜索 "llm" 的结果（来源: arxiv）:'));
      expect(dio.requestPaths.single, 'https://export.arxiv.org/api/query');
    });
  });

  group('mode 单来源路由', () {
    test('mode: arxiv → 仅请求 arXiv API，条目带 [arxiv] 标记', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _arxivXml(3)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'llm', 'mode': 'arxiv', 'max_results': 2});
      expect(out, startsWith('搜索 "llm" 的结果（来源: arxiv）:'));
      expect(_entryCount(out), 2);
      expect(_entryCountByMarker(out, '[arxiv]'), 2);
      expect(out, contains('Arxiv Paper 1'));
      expect(out, contains('作者: Author 1'));
      expect(out, contains('https://arxiv.org/abs/2301.00001'));
      expect(dio.requestPaths.single, 'https://export.arxiv.org/api/query');
      final params = dio.queryParams.single;
      expect(params['search_query'], 'all:llm');
      expect(params['max_results'], 2);
    });

    test('mode: github → 仅请求 GitHub API，条目带 [github] 标记', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _githubJson(3)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'flutter', 'mode': 'github', 'max_results': 2});
      expect(out, startsWith('搜索 "flutter" 的结果（来源: github）:'));
      expect(_entryCount(out), 2);
      expect(_entryCountByMarker(out, '[github]'), 2);
      expect(out, contains('owner/repo1'));
      expect(out, contains('描述: Repo description 1'));
      expect(out, contains('https://github.com/owner/repo1'));
      expect(dio.requestPaths.single, 'https://api.github.com/search/repositories');
      final params = dio.queryParams.single;
      expect(params['q'], 'flutter');
      expect(params['per_page'], 2);
    });

    test('mode: crossref → 仅请求 Crossref API，条目带 [crossref] 标记', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _crossrefJson(3)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'llm', 'mode': 'crossref', 'max_results': 2});
      expect(out, startsWith('搜索 "llm" 的结果（来源: crossref）:'));
      expect(_entryCount(out), 2);
      expect(_entryCountByMarker(out, '[crossref]'), 2);
      expect(out, contains('Crossref Paper 1'));
      expect(out, contains('作者: Given1 Family1'));
      expect(out, contains('期刊: Journal 1'));
      expect(out, contains('DOI: 10.1000/paper1'));
      expect(out, contains('https://doi.org/10.1000/paper1'));
      expect(dio.requestPaths.single, 'https://api.crossref.org/works');
      final params = dio.queryParams.single;
      expect(params['query'], 'llm');
      expect(params['rows'], 2);
    });

    test('mode: crossref 无 URL 时回退 doi.org 链接', () async {
      final json = {
        'message': {
          'items': [
            {
              'title': ['No Url Paper'],
              'DOI': '10.1000/nourl',
              // URL 字段缺失 → 应回退 https://doi.org/<DOI>
              'author': [
                {'given': 'A', 'family': 'B'},
              ],
              'container-title': ['Journal X'],
            },
          ],
        },
      };
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: json));
      final out = await WebSearchTool(dio)
          .execute({'query': 'llm', 'mode': 'crossref'});
      expect(out, contains('https://doi.org/10.1000/nourl'));
    });

    test('mode: arxiv 检索失败 → 结构化错误文本', () async {
      final dio = _StubDio()
        ..responses.add(DioException(message: 'Connection refused'));
      final out = await WebSearchTool(dio)
          .execute({'query': 'llm', 'mode': 'arxiv'});
      expect(out, startsWith('[搜索失败: arxiv search failed'));
    });
  });

  group('mode: all 四合一召回', () {
    test('四来源一并召回，max_results=5 均分 2/1/1/1，条目区分来源', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: _bingHtml(3)),
          Response(statusCode: 200, data: _arxivXml(3)),
          Response(statusCode: 200, data: _githubJson(3)),
          Response(statusCode: 200, data: _crossrefJson(3)),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 5});
      expect(out,
          startsWith('搜索 "flutter" 的结果（来源: 网络+arxiv+github+crossref）:'));
      expect(_entryCount(out), 5);
      expect(_entryCountByMarker(out, '[网络]'), 2);
      expect(_entryCountByMarker(out, '[arxiv]'), 1);
      expect(_entryCountByMarker(out, '[github]'), 1);
      expect(_entryCountByMarker(out, '[crossref]'), 1);
      // 请求顺序：Bing → arXiv → GitHub → Crossref（网络条目在前）
      expect(dio.requestPaths[0], startsWith('https://cn.bing.com'));
      expect(dio.requestPaths[1], 'https://export.arxiv.org/api/query');
      expect(dio.requestPaths[2], 'https://api.github.com/search/repositories');
      expect(dio.requestPaths[3], 'https://api.crossref.org/works');
      // 各来源配额透传：网络取 2、arxiv max_results=1、github per_page=1、crossref rows=1
      expect(dio.queryParams[1]['max_results'], 1);
      expect(dio.queryParams[2]['per_page'], 1);
      expect(dio.queryParams[3]['rows'], 1);
    });

    test('max_results=1 → 分配 1/0/0/0，仅请求网络，其余来源不发起', () async {
      final dio = _StubDio()
        ..responses.add(Response(statusCode: 200, data: _bingHtml(3)));
      final out = await WebSearchTool(dio)
          .execute({'query': 'flutter', 'mode': 'all', 'max_results': 1});
      expect(_entryCount(out), 1);
      expect(_entryCountByMarker(out, '[网络]'), 1);
      expect(dio.requestPaths.length, 1,
          reason: '分配为 0 的来源应跳过，不发起请求');
      expect(dio.requestPaths.single, startsWith('https://cn.bing.com'));
    });

    test('max_results=10 → 分配 4/2/2/2（余数全给网络）', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: _bingHtml(10)),
          Response(statusCode: 200, data: _arxivXml(10)),
          Response(statusCode: 200, data: _githubJson(10)),
          Response(statusCode: 200, data: _crossrefJson(10)),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 10});
      expect(_entryCount(out), 10);
      expect(_entryCountByMarker(out, '[网络]'), 4);
      expect(_entryCountByMarker(out, '[arxiv]'), 2);
      expect(_entryCountByMarker(out, '[github]'), 2);
      expect(_entryCountByMarker(out, '[crossref]'), 2);
    });

    test('max_results=4 → 分配 1/1/1/1（整除无余数）', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: _bingHtml(4)),
          Response(statusCode: 200, data: _arxivXml(4)),
          Response(statusCode: 200, data: _githubJson(4)),
          Response(statusCode: 200, data: _crossrefJson(4)),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 4});
      expect(_entryCount(out), 4);
      expect(_entryCountByMarker(out, '[网络]'), 1);
      expect(_entryCountByMarker(out, '[arxiv]'), 1);
      expect(_entryCountByMarker(out, '[github]'), 1);
      expect(_entryCountByMarker(out, '[crossref]'), 1);
    });

    test('单来源失败不阻塞其余来源，末尾附部分失败说明', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: _bingHtml(3)),
          DioException(message: 'arxiv down'),
          Response(statusCode: 200, data: _githubJson(3)),
          Response(statusCode: 200, data: _crossrefJson(3)),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 5});
      expect(out,
          startsWith('搜索 "flutter" 的结果（来源: 网络+arxiv+github+crossref）:'));
      expect(_entryCountByMarker(out, '[网络]'), 2);
      expect(_entryCountByMarker(out, '[github]'), 1);
      expect(_entryCountByMarker(out, '[crossref]'), 1);
      expect(out, contains('[部分来源失败: arxiv: arxiv search failed'));
    });

    test('来源返回空结果（无错误）→ 记为该来源未找到结果', () async {
      final dio = _StubDio()
        ..responses.addAll([
          Response(statusCode: 200, data: _bingHtml(3)),
          Response(statusCode: 200, data: _arxivXml(0)),
          Response(statusCode: 200, data: _githubJson(0)),
          Response(statusCode: 200, data: _crossrefJson(3)),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 5});
      expect(_entryCountByMarker(out, '[网络]'), 2);
      expect(_entryCountByMarker(out, '[crossref]'), 1);
      expect(out, contains('[部分来源失败: arxiv: 未找到结果；github: 未找到结果]'));
    });

    test('四来源全部失败 → 整体失败并汇总原因', () async {
      final dio = _StubDio()
        ..responses.addAll([
          DioException(message: 'bing down'),
          DioException(message: 'bing down 2'),
          DioException(message: 'arxiv down'),
          DioException(message: 'github down'),
          DioException(message: 'crossref down'),
        ]);
      final out = await WebSearchTool(dio).execute(
          {'query': 'flutter', 'mode': 'all', 'max_results': 5});
      expect(out, startsWith('[搜索失败: 网络: 无法连接搜索服务'));
      expect(out, contains('arxiv: arxiv search failed'));
      expect(out, contains('github: github search failed'));
      expect(out, contains('crossref: crossref search failed'));
    });
  });
}

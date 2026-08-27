// WebSearchTool 单元测试（Task 二 A2 交付物 4）。
//
// 覆盖：
//   - schema：query + max_results（integer 1-10）
//   - max_results 解析：缺省 5 / 0·负值·超上限 clamp / 非法字符串回退 / 合法数字字符串
//   - 结构化错误：网络失败（无法连接搜索服务）/ 未找到结果 / 被反爬（长度异常页面）
//   - 结果条目：每条附加来源域名；双 host 回退；max_results 不进 Bing 请求参数
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
  });
}

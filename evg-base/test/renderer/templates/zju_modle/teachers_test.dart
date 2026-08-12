/// zju teachers 模型 + service 单测（B3-teachers）。
///
/// 验证：
/// - 4 个模型：fromJson 映射 / toJson 往返 / 数据集统计
/// - ZjuChalaoshiService：数据集注入加载 / 在线 HTML 解析 / 在线失败本地兜底
///   （姓名/拼音/缩写匹配）/ 空查询 / 详情本地秒回（mock Dio，与 classroom_test
///   同款 _MockAdapter）
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/shared/models/zju_teacher.dart';
import 'package:evergreen_base/renderer/templates/zju_modle/teachers/services/chalaoshi_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用完整数据集 JSON（colleges 1 + teachers 2）。
const String kDatasetJson = '''
{
  "colleges": [
    {"id": 1, "name": "数学科学学院"},
    {"id": 2, "name": "计算机科学与技术学院"}
  ],
  "teachers": [
    {"id": 101, "name": "张三", "py": "zhangsan", "sx": "zs", "xy": 1, "hot": 12, "rate": "8.5"},
    {"id": 102, "name": "李四", "py": "lisi", "sx": "ls", "xy": 2, "hot": 5, "rate": "9.2"}
  ]
}
''';

void main() {
  group('模型', () {
    test('ZjuTeacherRecord fromJson/toJson 往返（含 xy/hot/rate）', () {
      final r = ZjuTeacherRecord.fromJson(const {
        'id': 101,
        'name': '张三',
        'py': 'zhangsan',
        'sx': 'zs',
        'xy': 1,
        'hot': 12,
        'rate': '8.5',
      });
      expect(r.id, 101);
      expect(r.name, '张三');
      expect(r.py, 'zhangsan');
      expect(r.sx, 'zs');
      expect(r.collegeId, 1);
      expect(r.hot, 12);
      expect(r.rate, '8.5');
      final round = ZjuTeacherRecord.fromJson(r.toJson());
      expect(round.id, r.id);
      expect(round.rate, r.rate);
      expect(round.toJson(), contains('xy'));
    });

    test('ZjuTeacherRecord 缺省兜底', () {
      final r = ZjuTeacherRecord.fromJson(const {'id': 1, 'name': '王五'});
      expect(r.py, '');
      expect(r.sx, '');
      expect(r.collegeId, 0);
      expect(r.hot, 0);
      expect(r.rate, '');
    });

    test('ZjuTeacherResult fromJson/toJson 往返（可空 score/college 缺省不写）', () {
      final t = ZjuTeacherResult.fromJson(const {
        'id': 101,
        'name': '张三',
        'score': 8.5,
        'college': '数学科学学院',
        'url': 'https://chalaoshi.click/t/101',
        'dataSource': 'online',
      });
      expect(t.id, 101);
      expect(t.score, 8.5);
      expect(t.college, '数学科学学院');
      expect(t.dataSource, 'online');
      final json = t.toJson();
      expect(json['score'], 8.5);
      // 无 score/college → toJson 不写该字段
      final t2 = ZjuTeacherResult.fromJson(
          const {'id': 1, 'name': '李四', 'url': 'https://x/t/1'});
      expect(t2.score, isNull);
      expect(t2.college, isNull);
      expect(t2.toJson().containsKey('score'), isFalse);
      expect(t2.toJson().containsKey('college'), isFalse);
      expect(t2.dataSource, 'local');
    });

    test('ZjuTeacherDetail fromJson/toJson 往返', () {
      final d = ZjuTeacherDetail.fromJson(const {
        'id': 101,
        'name': '张三',
        'score': 8.5,
        'raters': 12,
        'college': '数学科学学院',
      });
      expect(d.id, 101);
      expect(d.score, 8.5);
      expect(d.raters, 12);
      final round = ZjuTeacherDetail.fromJson(d.toJson());
      expect(round.name, d.name);
      expect(round.score, d.score);
    });

    test('ZjuTeacherDataset fromJson/toJson/stats', () {
      final ds = ZjuTeacherDataset.fromJson(
          jsonDecodeForTest(kDatasetJson));
      expect(ds.colleges, hasLength(2));
      expect(ds.teachers, hasLength(2));
      expect(ds.collegeName(1), '数学科学学院');
      // toJson 往返
      final round = ZjuTeacherDataset.fromJson(ds.toJson());
      expect(round.teachers.first.name, '张三');
      // 数据中枢缓存形态：仅统计
      final stats = ds.toStatsJson();
      expect(stats['loaded'], isTrue);
      expect(stats['teachers'], 2);
      expect(stats['colleges'], 2);
    });
  });

  group('ZjuChalaoshiService.search（mock Dio）', () {
    ZjuChalaoshiService serviceWith(
        ResponseBody Function(RequestOptions options) handler) {
      final dio = _dioWith(handler);
      final s = ZjuChalaoshiService(dio);
      s.injectDataset(kDatasetJson);
      return s;
    }

    test('在线成功：解析 result-item HTML → online 结果', () async {
      const html = '''
<html><body>
<div class="result-item"><div><strong>张三</strong> 评分: 8.8</div><a href="http://chalaoshi.top/?teacher_id=101&page=1">查看</a></div>
<div class="result-item"><div><strong>张三丰</strong> 评分: 7.2</div><a href="http://chalaoshi.top/?teacher_id=202&page=1">查看</a></div>
</body></html>''';
      late Uri? lastUri;
      final s = serviceWith((options) {
        lastUri = options.uri;
        expect(options.receiveTimeout, const Duration(seconds: 3));
        return ResponseBody.fromString(html, 200);
      });
      final results = await s.search('张三');
      expect(results, isNotEmpty);
      expect(lastUri!.query, contains('search_query=%E5%BC%A0%E4%B8%89'));
      expect(lastUri!.query, contains('action=search'));
      // 过滤：仅保留 name 含查询词的条目
      expect(results.every((t) => t.name.contains('张三')), isTrue);
      expect(results.first.dataSource, 'online');
      expect(results.first.id, 101);
      expect(results.first.score, 8.8);
      // 在线结果已合并进本地缓存
      expect(results.first.url, contains('/t/101'));
    });

    test('在线响应无评分标记 → 不重试，直接本地兜底', () async {
      var calls = 0;
      final s = serviceWith((options) {
        calls++;
        return ResponseBody.fromString('<html><body>no data</body></html>', 200);
      });
      final results = await s.search('张三');
      expect(calls, 1, reason: '有响应但解析不到结果时不应重试');
      expect(results, isNotEmpty);
      expect(results.first.dataSource, 'local');
      expect(results.first.score, 8.5);
      expect(results.first.college, '数学科学学院');
    });

    test('在线网络失败两次 → 本地兜底（姓名匹配）', () async {
      var calls = 0;
      final s = serviceWith((options) {
        calls++;
        throw DioException.connectionError(
            requestOptions: options, reason: 'refused');
      });
      final results = await s.search('张三');
      expect(calls, 2, reason: '失败后应重试一次再降级');
      expect(results, hasLength(1));
      expect(results.first.name, '张三');
      expect(results.first.dataSource, 'local');
    });

    test('本地拼音/缩写匹配（py / sx 不区分大小写）', () async {
      final s = serviceWith(
          (options) => throw DioException.connectionError(
              requestOptions: options, reason: 'refused'));
      expect((await s.search('zhangsan')).first.id, 101); // 拼音全拼
      expect((await s.search('ZS')).first.id, 101); // 拼音缩写（大写）
      expect((await s.search('lisi')).first.id, 102);
      expect(await s.search('王五'), isEmpty); // 无匹配
    });

    test('空查询 → 空列表（不触发网络）', () async {
      var calls = 0;
      final s = serviceWith((options) {
        calls++;
        return ResponseBody.fromString('', 200);
      });
      expect(await s.search('   '), isEmpty);
      expect(calls, 0);
    });
  });

  group('ZjuChalaoshiService.loadDataset / getDetail', () {
    test('injectDataset 后 loadDataset 返回数据集', () async {
      final s = ZjuChalaoshiService(_dioWith(
          (o) => throw DioException.connectionError(
              requestOptions: o, reason: 'refused')));
      s.injectDataset(kDatasetJson);
      final ds = await s.loadDataset();
      expect(ds.teachers, hasLength(2));
      expect(ds.toStatsJson()['teachers'], 2);
    });

    test('未注入且无 asset：loadDataset 抛可读 StateError', () async {
      final s = ZjuChalaoshiService(_dioWith(
          (o) => throw DioException.connectionError(
              requestOptions: o, reason: 'refused')));
      expect(
        () => s.loadDataset(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('数据集缺失'))),
      );
    });

    test('getDetail 本地秒回（score/raters/college 映射）', () async {
      final s = ZjuChalaoshiService(_dioWith(
          (o) => throw DioException.connectionError(
              requestOptions: o, reason: 'refused')));
      s.injectDataset(kDatasetJson);
      final d = await s.getDetail(101, name: '张三');
      expect(d, isNotNull);
      expect(d!.name, '张三');
      expect(d.score, 8.5);
      expect(d.raters, 12);
      expect(d.college, '数学科学学院');
      expect(await s.getDetail(999), isNull);
    });
  });
}

/// 测试内联 jsonDecode 便捷入口。
Map<String, dynamic> jsonDecodeForTest(String source) =>
    jsonDecode(source) as Map<String, dynamic>;

// ── mock 工具（与 classroom_test / zdbk_test 同款）────────────────────

Dio _dioWith(ResponseBody Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://chalaoshi.top'));
  dio.httpClientAdapter =
      _MockAdapter((options) => Future<ResponseBody>.sync(() => handler(options)));
  return dio;
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

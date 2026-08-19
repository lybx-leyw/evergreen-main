// 探索数据源证据绑定测试（P0-2 · Evidence → CandidateDataSource）。
//
// 覆盖：
// 1. JsonPath 求值器：$.key / ['key'] / [i] / [*] / 非法 path / 非 JSON 容器
// 2. validateDataSourceEvidence：url 命中（ok）/ url 无匹配（仅警告不阻断）
// 3. sourceLogId 精确引用 / 归一化匹配（log-7 / log#7 / 7）
// 4. 字段 sourceJsonPath：解析成功 / 失败（仅警告）/ 未标注（仅警告）
// 5. 字段与源引用日志不一致 → 仅警告；证据 URL 归一（忽略 query）
// 6. 非 GET 日志可作为证据（放宽）
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_evidence.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/explore/explore_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleResponse = '{"data": [{"courseId": 1, "courseName": "高数", "tags": ["a", "b"]}], "total": 1}';

HttpRequestLog _log(String id, String url, {String? responseBody}) => HttpRequestLog(
  timestamp: DateTime.now(),
  method: 'GET',
  url: url,
  responseBody: responseBody,
  id: id,
);

CandidateDataSource _source({
  String url = 'https://site.com/api/courses',
  String? sourceLogId = 'log-1',
  List<CandidateField> fields = const [],
}) =>
    CandidateDataSource(
      name: 'courses',
      displayName: '课程',
      category: '课程',
      url: url,
      fields: fields,
      sourceLogId: sourceLogId,
    );

void main() {
  group('resolveJsonPath（P0-2 自带求值器）', () {
    final root = {
      'data': [
        {'courseId': 1, 'courseName': '高数', 'tags': ['a', 'b']},
      ],
      'total': 1,
      'nested': {'deep': {'key.with.dot': true}},
    };

    test('resolve \$.data[0].courseName', () {
      final r = resolveJsonPath(root, r'$.data[0].courseName');
      expect(r.found, isTrue);
      expect(r.first, '高数');
      expect(r.error, isNull);
    });

    test('括号键名与带点键名', () {
      expect(resolveJsonPath(root, r"$['data'][0]['courseId']").first, 1);
      expect(resolveJsonPath(root, r'$.data[0].tags[1]').first, 'b');
      expect(
          resolveJsonPath(root, r"$.nested.deep['key.with.dot']").first, isTrue);
    });

    test('末尾通配 [*]：命中值 = 数组元素', () {
      final r = resolveJsonPath(root, r'$.data[*]');
      expect(r.found, isTrue);
      expect(r.values, hasLength(1));
      expect((r.values.first as Map)['courseName'], '高数');
    });

    test('键不存在 → found=false + error（区分值为 null）', () {
      final r = resolveJsonPath(root, r'$.data[0].missing');
      expect(r.found, isFalse);
      expect(r.error, contains('不存在'));
    });

    test('下标越界 → found=false + error', () {
      final r = resolveJsonPath(root, r'$.data[5]');
      expect(r.found, isFalse);
      expect(r.error, contains('越界'));
    });

    test('非法语法：中段通配 / 空 path / 负下标 / 未闭合括号', () {
      expect(resolveJsonPath(root, r'$.data[*].courseName').found, isFalse);
      expect(resolveJsonPath(root, r'$.data[*].courseName').error, contains('语法非法'));
      expect(resolveJsonPath(root, '').found, isFalse);
      expect(resolveJsonPath(root, r'$.data[-1]').found, isFalse);
      expect(resolveJsonPath(root, r'$.data[0').found, isFalse);
    });

    test('root 非 JSON 容器 → found=false，不抛异常', () {
      expect(resolveJsonPath('not json', r'$.x').found, isFalse);
      expect(resolveJsonPath(42, r'$.x').found, isFalse);
    });
  });

  group('normalizeLogRef / sameLogRef（引用归一）', () {
    test('log-7 / log#7 / #7 / 7 视为同一引用', () {
      expect(normalizeLogRef('log-7'), 'log-7');
      expect(normalizeLogRef('log#7'), 'log-7');
      expect(normalizeLogRef('#7'), 'log-7');
      expect(normalizeLogRef('7'), 'log-7');
      expect(normalizeLogRef('LOG-7'), 'log-7');
      expect(sameLogRef('log-7', '7'), isTrue);
      expect(sameLogRef('log-7', 'log-8'), isFalse);
    });
  });

  group('validateDataSourceEvidence（url 证据）', () {
    test('sourceLogId 精确命中 → 放行（无警告）', () {
      final logs = [_log('log-1', 'https://site.com/api/courses', responseBody: _sampleResponse)];
      final r = validateDataSourceEvidence(_source(fields: const [
        CandidateField(name: 'id', type: 'number', sourceJsonPath: r'$.data[0].courseId'),
      ]), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.urlMatched, isTrue);
      expect(r.matchedLog!.id, 'log-1');
      expect(r.warnings, isEmpty);
      expect(r.fieldChecks.single.verified, isTrue);
    });

    test('sourceLogId 引用失效 → 按 URL 兜底 + 警告', () {
      final logs = [_log('log-9', 'https://site.com/api/courses', responseBody: _sampleResponse)];
      final r = validateDataSourceEvidence(_source(sourceLogId: 'log-99'), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.urlMatched, isTrue);
      expect(r.matchedLog!.id, 'log-9');
      expect(r.warnings.single, contains('兜底'));
    });

    test('url 无任何日志匹配 → 仅警告不阻断（放宽）', () {
      final r = validateDataSourceEvidence(_source(sourceLogId: null), [
        _log('log-1', 'https://site.com/other/path'),
      ]);
      expect(r.hardBlocked, isFalse);
      expect(r.urlMatched, isFalse);
      expect(r.errors, isEmpty);
      expect(r.warnings.single, contains('无捕获日志证据'));
    });

    test('证据 URL 归一：忽略 query/fragment，大小写不敏感', () {
      final r = validateDataSourceEvidence(_source(url: 'https://Site.com/api/courses?page=1#x'), [
        _log('log-1', 'https://site.com/api/courses?page=2'),
      ]);
      expect(r.hardBlocked, isFalse);
      expect(r.urlMatched, isTrue);
    });

    test('非 GET 日志可作为证据（放宽）', () {
      final r = validateDataSourceEvidence(_source(sourceLogId: null), [
        HttpRequestLog(timestamp: DateTime.now(), method: 'POST', url: 'https://site.com/api/courses', id: 'log-1'),
      ]);
      expect(r.hardBlocked, isFalse);
      expect(r.urlMatched, isTrue);
      expect(r.matchedLog!.method, 'POST');
    });
  });

  group('validateDataSourceEvidence（字段 path 证据）', () {
    test('path 解析失败 → 仅警告不阻断', () {
      final logs = [_log('log-1', 'https://site.com/api/courses', responseBody: _sampleResponse)];
      final r = validateDataSourceEvidence(_source(fields: const [
        CandidateField(name: 'fake', type: 'string', sourceJsonPath: r'$.data[0].fake'),
      ]), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.fieldChecks.single.verified, isFalse);
      expect(r.warnings.single, contains('解析失败'));
    });

    test('字段未标注 sourceJsonPath → 仅警告', () {
      final logs = [_log('log-1', 'https://site.com/api/courses', responseBody: _sampleResponse)];
      final r = validateDataSourceEvidence(_source(fields: const [
        CandidateField(name: 'id', type: 'number'),
      ]), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.fieldChecks.single.verified, isFalse);
      expect(r.warnings.single, contains('未标注 sourceJsonPath'));
    });

    test('日志无响应体 → path 无法验证，仅警告', () {
      final logs = [_log('log-1', 'https://site.com/api/courses')];
      final r = validateDataSourceEvidence(_source(fields: const [
        CandidateField(name: 'id', type: 'number', sourceJsonPath: r'$.data[0].courseId'),
      ]), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.warnings.single, contains('未捕获响应体'));
    });

    test('字段引用日志与源引用不一致 → 证据链混乱警告', () {
      final logs = [_log('log-1', 'https://site.com/api/courses', responseBody: _sampleResponse)];
      final r = validateDataSourceEvidence(_source(fields: const [
        CandidateField(name: 'id', type: 'number', sourceLogId: 'log-2', sourceJsonPath: r'$.data[0].courseId'),
      ]), logs);
      expect(r.hardBlocked, isFalse);
      expect(r.warnings.single, contains('不一致'));
    });
  });
}


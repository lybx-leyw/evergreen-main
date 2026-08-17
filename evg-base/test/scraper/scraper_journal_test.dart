// 探索经验 Journal 测试（P1-2 · field-journal）。
//
// 覆盖：
// 1. append / loadLatest 往返 + 每域上限裁剪
// 2. listAll 跨域按时间倒序
// 3. 损坏文件 / 目录不存在容错
// 4. 域名 sanitize 防路径穿越；写失败不抛
// 5. inferAuthMethod / inferKeyParams 从捕获日志自动提取
// 6. JournalEntry toPromptSummary / JSON 往返
import 'dart:io';

import 'package:evergreen_base/renderer/templates/scraper_modle/agent/scraper_journal.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:flutter_test/flutter_test.dart';

HttpRequestLog _log(String url, {Map<String, String>? headers}) =>
    HttpRequestLog(
  timestamp: DateTime.now(),
  method: 'GET',
  url: url,
  headers: headers,
);

JournalEntry _entry(String domain, DateTime at, {String auth = '', String flow = ''}) =>
    JournalEntry(domain: domain, authMethod: auth, flow: flow, recordedAt: at);

void main() {
  late Directory tmp;
  late ScraperJournal journal;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('journal_test_');
    journal = ScraperJournal(baseDir: tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('append / loadLatest / listAll', () {
    test('append 后 loadLatest 命中最新一条', () async {
      await journal.append(_entry('zju.edu.cn', DateTime(2026, 1, 1)));
      await journal.append(_entry('zju.edu.cn', DateTime(2026, 1, 2), auth: 'cookie 登录'));
      final latest = await journal.loadLatest('zju.edu.cn');
      expect(latest, isNotNull);
      expect(latest!.recordedAt, DateTime(2026, 1, 2));
      expect(latest.authMethod, 'cookie 登录');
    });

    test('无记录域名 → null；空域名 → null', () async {
      expect(await journal.loadLatest('none.com'), isNull);
      await journal.append(_entry('', DateTime.now()));
      expect(await journal.loadLatest(''), isNull);
    });

    test('每域名最多保留 5 条（防膨胀）', () async {
      for (var i = 1; i <= 7; i++) {
        await journal.append(_entry('a.com', DateTime(2026, 1, i)));
      }
      final all = await journal.listAll();
      expect(all.where((e) => e.domain == 'a.com').length, 5);
      final latest = await journal.loadLatest('a.com');
      expect(latest!.recordedAt, DateTime(2026, 1, 7));
    });

    test('listAll 跨域按记录时间倒序', () async {
      await journal.append(_entry('a.com', DateTime(2026, 1, 1)));
      await journal.append(_entry('b.com', DateTime(2026, 2, 1)));
      await journal.append(_entry('c.com', DateTime(2026, 3, 1)));
      final all = await journal.listAll();
      expect(all.map((e) => e.domain).toList(), ['c.com', 'b.com', 'a.com']);
    });
  });

  group('容错与安全', () {
    test('损坏的 journal 文件 → loadLatest 返回 null，listAll 跳过', () async {
      final dir = Directory(journal.baseDir);
      dir.createSync(recursive: true);
      File('${tmp.path}/a.com.json').writeAsStringSync('{corrupt');
      expect(await journal.loadLatest('a.com'), isNull);
      expect(await journal.listAll(), isEmpty);
    });

    test('域名 sanitize 防路径穿越（../../evil 不逃逸 baseDir）', () async {
      await journal.append(_entry('../../evil', DateTime(2026, 1, 1)));
      final escaped = Directory(tmp.parent.path);
      expect(escaped.listSync().where((f) => f.path.contains('evil')).toList(),
          isEmpty);
      // 条目写入 baseDir 内的 sanitize 文件
      final files = tmp.listSync().whereType<File>().toList();
      expect(files.length, 1);
      expect(files.single.path, startsWith(tmp.path));
    });

    test('baseDir 无法创建（指向文件）→ append 不抛', () async {
      final asFile = File('${tmp.path}/as_file');
      asFile.writeAsStringSync('x');
      final bad = ScraperJournal(baseDir: asFile.path);
      await bad.append(_entry('a.com', DateTime(2026, 1, 1))); // 不抛即通过
    });
  });

  group('经验自动提取', () {
    test('inferAuthMethod：token / cookie / 混合 / 无认证', () {
      expect(inferAuthMethod([_log('https://a.com/x', headers: {'Authorization': 'Bearer t'})]), 'token');
      expect(inferAuthMethod([_log('https://a.com/x', headers: {'x-api-key': 'k'})]), 'token');
      expect(inferAuthMethod([_log('https://a.com/x', headers: {'Cookie': 'sid=1'})]), 'cookie 登录');
      expect(inferAuthMethod([
        _log('https://a.com/x', headers: {'Authorization': 't', 'Cookie': 'sid=1'}),
      ]), 'token + cookie');
      expect(inferAuthMethod([_log('https://a.com/x')]), '无认证');
      expect(inferAuthMethod(const []), '无认证');
    });

    test('inferKeyParams：同域 query 去重排序 + 跨域过滤 + 上限', () {
      final logs = [
        _log('https://a.com/api?page=1&size=20&token=abc'),
        _log('https://a.com/api?page=2&sign=xyz'),
        _log('https://b.com/api?other=1'), // 跨域过滤
      ];
      final keys = inferKeyParams(logs, domain: 'a.com');
      expect(keys, ['page', 'sign', 'size', 'token']);
      // 上限裁剪
      final many = inferKeyParams([
        _log('https://a.com/x?${List.generate(30, (i) => 'k$i=1').join('&')}'),
      ], domain: 'a.com', cap: 20);
      expect(many.length, 20);
    });
  });

  group('模型往返与 prompt 摘要', () {
    test('JournalEntry toJson/fromJson 往返', () {
      final e = JournalEntry(
        domain: 'zju.edu.cn',
        authMethod: 'cookie 登录',
        flow: '探索 5 页',
        pitfalls: 'CAS 跳转坑',
        keyParams: ['sign', 'token'],
        recordedAt: DateTime(2026, 1, 1, 12),
      );
      final back = JournalEntry.fromJson(e.toJson());
      expect(back.domain, e.domain);
      expect(back.authMethod, e.authMethod);
      expect(back.flow, e.flow);
      expect(back.pitfalls, e.pitfalls);
      expect(back.keyParams, e.keyParams);
      expect(back.recordedAt, e.recordedAt);
    });

    test('toPromptSummary 含认证/流程/参数/坑', () {
      final s = _entry('zju.edu.cn', DateTime(2026, 1, 1),
              auth: 'cookie 登录', flow: '探索 5 页')
          .toPromptSummary();
      expect(s, contains('本域历史经验'));
      expect(s, contains('cookie 登录'));
      expect(s, contains('探索 5 页'));
      expect(s, contains('完整流程验证'));
    });
  });
}

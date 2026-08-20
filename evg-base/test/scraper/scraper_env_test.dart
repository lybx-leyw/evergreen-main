// ScraperEnvStore 环境变量存储测试。
//
// 覆盖（含用户反馈 bug 回归）：
// 1. 首次写入（env.json 不存在）成功——回归 "Cannot modify unmodifiable map" bug
// 2. 覆盖写入
// 3. key 校验拒绝（非法 key 不落盘）
// 4. env.json 损坏时 load 返回空、写入仍成功
// 5. 镜像 config.json（保留原有 key + 新增 key）
// 6. envForSubprocess 合并平台环境 + 存储 + PROJECT_ROOT
// 7. keys() / listSummary() 不回显值
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String envPath;
  late String mirrorPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scraper_env_test_');
    envPath = '${tmp.path}${Platform.pathSeparator}env.json';
    mirrorPath = '${tmp.path}${Platform.pathSeparator}config.json';
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ScraperEnvStore store({bool mirror = true}) => ScraperEnvStore(
        envFilePath: envPath,
        mirrorConfigPath: mirror ? mirrorPath : null,
      );

  group('setVar（写入/更新）', () {
    test('首次写入（env.json 不存在）成功——回归 unmodifiable map bug', () {
      // 修复前：load() 返回 const {} → all[k]=v 抛
      // "Cannot modify unmodifiable map"，工具/AI 拿不到写入确认。
      final s = store();
      final out = s.setVar('SCRAPER_USERNAME', 'alice');
      expect(out, startsWith('✅'));
      expect(out, contains('SCRAPER_USERNAME'));
      // 落盘校验
      final onDisk = jsonDecode(File(envPath).readAsStringSync()) as Map;
      expect(onDisk['SCRAPER_USERNAME'], 'alice');
    });

    test('连续写入多个 key 且覆盖更新', () {
      final s = store();
      s.setVar('SCRAPER_USERNAME', 'alice');
      s.setVar('SCRAPER_PASSWORD', 'p@ss');
      expect(s.keys(), containsAll(['SCRAPER_USERNAME', 'SCRAPER_PASSWORD']));
      // 覆盖：值更新，key 数不变
      final out = s.setVar('SCRAPER_USERNAME', 'bob');
      expect(out, startsWith('✅'));
      final onDisk = jsonDecode(File(envPath).readAsStringSync()) as Map;
      expect(onDisk['SCRAPER_USERNAME'], 'bob');
      expect(onDisk.length, 2);
    });

    test('非法 key 被拒绝且不落盘', () {
      final s = store();
      expect(s.setVar('lowercase', 'x'), startsWith('[error:'));
      expect(s.setVar('1DIGIT', 'x'), startsWith('[error:'));
      expect(s.setVar('', 'x'), startsWith('[error:'));
      expect(File(envPath).existsSync(), isFalse);
    });

    test('env.json 损坏时写入仍成功（load 兜底空字典）', () {
      File(envPath).writeAsStringSync('{ 这不是合法 JSON');
      final s = store();
      final out = s.setVar('SCRAPER_TOKEN', 'tok');
      expect(out, startsWith('✅'));
      final onDisk = jsonDecode(File(envPath).readAsStringSync()) as Map;
      expect(onDisk['SCRAPER_TOKEN'], 'tok');
    });

    test('镜像 config.json：保留原有 key 并新增', () {
      File(mirrorPath).writeAsStringSync(jsonEncode({'EXISTING': 'keep'}));
      store().setVar('SCRAPER_COOKIE', 'sid=1');
      final cfg = jsonDecode(File(mirrorPath).readAsStringSync()) as Map;
      expect(cfg['EXISTING'], 'keep');
      expect(cfg['SCRAPER_COOKIE'], 'sid=1');
    });
  });

  group('读取', () {
    test('keys() 只列 key、listSummary() 不回显值', () {
      final s = store();
      s.setVar('SCRAPER_USERNAME', 'secret-user');
      s.setVar('SCRAPER_PASSWORD', 'secret-pass');
      expect(s.keys(), containsAll(['SCRAPER_USERNAME', 'SCRAPER_PASSWORD']));
      final summary = s.listSummary();
      expect(summary, contains('SCRAPER_USERNAME'));
      expect(summary, isNot(contains('secret-user')));
      expect(summary, isNot(contains('secret-pass')));
    });

    test('envForSubprocess 合并平台环境 + 存储 + PROJECT_ROOT', () {
      final s = store();
      s.setVar('SCRAPER_USERNAME', 'alice');
      final env = s.envForSubprocess('/proj');
      expect(env['SCRAPER_USERNAME'], 'alice');
      expect(env['PROJECT_ROOT'], '/proj');
      expect(env.containsKey('PATH'), isTrue); // 平台环境保留
    });
  });
}

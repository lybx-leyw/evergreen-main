/// 文件型数据源输出条目解析测试（P2 前置：纯契约层）。
///
/// 锁定：`url`（待下载）与 `path`（已落盘）两种形态的判别，以及
/// 协议 §5.4 的边界规则——**同时给出时以 `path` 为准**。
library;

import 'package:test/test.dart';

import '../data/file_source_entries.dart';

void main() {
  group('parseFileSourceEntries', () {
    test('files[] 待下载形态（url）', () {
      final r = parseFileSourceEntries({
        'files': [
          {'url': 'https://x/a.mp4', 'name': '第1讲.mp4', 'mime': 'video/mp4'},
          {'url': 'https://x/b.pdf'},
        ]
      });
      expect(r, hasLength(2));
      expect(r[0].isCached, isFalse);
      expect(r[0].url, equals('https://x/a.mp4'));
      expect(r[0].name, equals('第1讲.mp4'));
      expect(r[0].mime, equals('video/mp4'));
      expect(r[1].name, equals('b.pdf'), reason: '缺 name 时由 url 末段派生');
    });

    test('files[] 已落盘形态（path）', () {
      final r = parseFileSourceEntries({
        'status': 'ready',
        'files': [
          {'path': '/c/file_cache/x-y.mp4', 'size': 1024, 'mime': 'video/mp4'}
        ]
      });
      expect(r, hasLength(1));
      expect(r[0].isCached, isTrue);
      expect(r[0].path, equals('/c/file_cache/x-y.mp4'));
      expect(r[0].size, equals(1024));
      expect(r[0].name, equals('x-y.mp4'));
    });

    test('同时给出 url 与 path → **path 优先**（协议 §5.4 边界）', () {
      final r = parseFileSourceEntries({
        'files': [
          {'url': 'https://x/a.mp4', 'path': '/c/file_cache/a.mp4'}
        ]
      });
      expect(r.single.isCached, isTrue);
      expect(r.single.path, equals('/c/file_cache/a.mp4'));
      expect(r.single.url, equals('https://x/a.mp4'),
          reason: 'url 仍保留（可溯源），但 isCached 由 path 决定');
    });

    test('顶层单文件形态（path）', () {
      final r = parseFileSourceEntries(
          {'status': 'ready', 'path': '/c/file_cache/only.mp4', 'size': 2048});
      expect(r, hasLength(1));
      expect(r.single.isCached, isTrue);
    });

    test('顶层 file 对象形态', () {
      final r = parseFileSourceEntries({
        'file': {'url': 'https://x/c.pdf', 'name': 'c.pdf'}
      });
      expect(r.single.url, equals('https://x/c.pdf'));
    });

    test('既无 url 也无 path 的元素被跳过', () {
      final r = parseFileSourceEntries({
        'files': [
          {'name': '无来源'},
          {'url': 'https://x/ok.bin'},
          {'title': '只有标题'},
        ]
      });
      expect(r, hasLength(1));
      expect(r.single.url, equals('https://x/ok.bin'));
    });

    test('未知结构 / 非 Map → 空且不抛', () {
      expect(parseFileSourceEntries(null), isEmpty);
      expect(parseFileSourceEntries('nope'), isEmpty);
      expect(parseFileSourceEntries(42), isEmpty);
      expect(parseFileSourceEntries({}), isEmpty);
      expect(parseFileSourceEntries({'status': 'missing', 'path': null}), isEmpty);
    });

    test('size 容错：数字 / 数字字符串 / 非法', () {
      final r = parseFileSourceEntries({
        'files': [
          {'url': 'u1', 'size': 100},
          {'url': 'u2', 'size': '200'},
          {'url': 'u3', 'size': 'abc'},
          {'url': 'u4'},
        ]
      });
      expect(r[0].size, equals(100));
      expect(r[1].size, equals(200));
      expect(r[2].size, isNull);
      expect(r[3].size, isNull);
    });

    test('别名兼容：downloadEndpoint / href / src / filename / mimeType', () {
      final r = parseFileSourceEntries({
        'files': [
          {'downloadEndpoint': 'https://x/1', 'filename': 'n1', 'mimeType': 'video/mp4'},
        ]
      });
      expect(r.single.url, equals('https://x/1'));
      expect(r.single.name, equals('n1'));
      expect(r.single.mime, equals('video/mp4'));
    });
  });

  group('FileSourceEntry.sizeLabel', () {
    test('人类可读格式化', () {
      expect(const FileSourceEntry(url: 'u', size: 512).sizeLabel, equals('512 B'));
      expect(const FileSourceEntry(url: 'u', size: 2048).sizeLabel, equals('2.0 KB'));
      expect(
          const FileSourceEntry(url: 'u', size: 5 * 1024 * 1024).sizeLabel,
          equals('5.0 MB'));
      expect(
          const FileSourceEntry(url: 'u', size: 3 * 1024 * 1024 * 1024).sizeLabel,
          equals('3.0 GB'));
      expect(const FileSourceEntry(url: 'u').sizeLabel, equals('未知'));
      expect(const FileSourceEntry(url: 'u', size: 0).sizeLabel, equals('未知'));
    });
  });
}

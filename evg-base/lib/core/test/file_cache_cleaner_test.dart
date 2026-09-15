/// 文件缓存清理测试（方案 P4 / D7）。
///
/// 锁定契约：
///  1. `.part` 与正式文件**分开处理**——`.part` 只看超龄，不参与配额；
///  2. 配额裁剪按 **mtime 从旧到新**；
///  3. 宽限期内文件**绝不**被删（可能正被 slot 消费）；
///  4. **至少保留最新 1 个**（单文件超配额也不清空缓存）；
///  5. 目录不存在 → 零值且不抛。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../data/file_cache_cleaner.dart';

/// 造一个缓存目录，写入若干文件并指定 mtime（相对 [now]）。
Directory makeCache(DateTime now, Map<String, (int, Duration)> files) {
  final d = Directory.systemTemp.createTempSync('fcc_');
  files.forEach((name, spec) {
    final f = File(p.join(d.path, name))
      ..writeAsBytesSync(List<int>.filled(spec.$1, 0));
    f.setLastModifiedSync(now.subtract(spec.$2));
  });
  return d;
}

void main() {
  final now = DateTime(2026, 9, 15, 12);

  group('isPartialFile', () {
    test('识别 .part 命名（与 evg_lib.download / DataFileService 一致）', () {
      expect(isPartialFile('abc-123.mp4.part.42.1700000000'), isTrue);
      expect(isPartialFile('abc-123.mp4'), isFalse);
      expect(isPartialFile('partition.mp4'), isFalse,
          reason: '只认 ".part" 片段，不误伤含 partition 的普通名');
    });
  });

  group('fileCacheStats', () {
    test('分别统计正式文件与 .part', () {
      final d = makeCache(now, {
        'a.mp4': (100, const Duration(hours: 2)),
        'b.mp4': (200, const Duration(hours: 1)),
        'c.mp4.part.1.2': (50, const Duration(minutes: 1)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final s = fileCacheStats(dir: d.path);
      expect(s.fileCount, equals(2));
      expect(s.totalBytes, equals(300));
      expect(s.partialCount, equals(1), reason: '.part 不计入 totalBytes');
    });

    test('目录不存在 → 零值且不抛', () {
      final s = fileCacheStats(dir: '/tmp/no-such-cache-dir-xyz');
      expect(s.fileCount, equals(0));
      expect(s.totalBytes, equals(0));
    });
  });

  group('clearOrphanPartials（契约 1）', () {
    test('超龄 .part 回收；新鲜 .part 保留；正式文件不动', () {
      final d = makeCache(now, {
        'keep.mp4': (100, const Duration(days: 30)),
        'old.mp4.part.1.1': (10, const Duration(hours: 3)),
        'fresh.mp4.part.2.2': (10, const Duration(minutes: 5)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final n = clearOrphanPartials(dir: d.path, now: now);
      expect(n, equals(1));
      expect(File(p.join(d.path, 'old.mp4.part.1.1')).existsSync(), isFalse);
      expect(File(p.join(d.path, 'fresh.mp4.part.2.2')).existsSync(), isTrue,
          reason: '新鲜 .part 可能正在写入，不能删');
      expect(File(p.join(d.path, 'keep.mp4')).existsSync(), isTrue,
          reason: '正式缓存文件不受影响（哪怕很旧）');
    });
  });

  group('trimFileCache（契约 2–4）', () {
    test('未超配额 → 不删任何文件', () {
      final d = makeCache(now, {
        'a': (100, const Duration(hours: 2)),
        'b': (100, const Duration(hours: 1)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final r = trimFileCache(dir: d.path, maxBytes: 1000, now: now);
      expect(r.removedFiles, equals(0));
      expect(r.remainingFiles, equals(2));
      expect(r.remainingBytes, equals(200));
    });

    test('超配额 → 最旧优先淘汰，直到回到配额内', () {
      final d = makeCache(now, {
        'oldest': (400, const Duration(hours: 3)),
        'middle': (400, const Duration(hours: 2)),
        'newest': (400, const Duration(hours: 1)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final r = trimFileCache(dir: d.path, maxBytes: 900, now: now);
      expect(r.removedFiles, equals(1));
      expect(File(p.join(d.path, 'oldest')).existsSync(), isFalse,
          reason: 'mtime 最旧者先淘汰');
      expect(File(p.join(d.path, 'middle')).existsSync(), isTrue);
      expect(File(p.join(d.path, 'newest')).existsSync(), isTrue);
      expect(r.remainingBytes, equals(800));
    });

    test('宽限期内的文件绝不被删（可能正被 slot 消费）', () {
      final d = makeCache(now, {
        'just_downloaded': (900, const Duration(minutes: 1)),
        'old': (900, const Duration(hours: 5)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final r = trimFileCache(
          dir: d.path,
          maxBytes: 500,
          grace: const Duration(minutes: 10),
          now: now);
      expect(r.removedFiles, equals(1));
      expect(File(p.join(d.path, 'just_downloaded')).existsSync(), isTrue,
          reason: '刚下载的文件在宽限期内必须保留');
      expect(File(p.join(d.path, 'old')).existsSync(), isFalse);
    });

    test('至少保留最新 1 个：单文件超配额也不清空', () {
      final d = makeCache(now, {'huge': (5000, const Duration(hours: 10))});
      addTearDown(() => d.deleteSync(recursive: true));
      final r = trimFileCache(
          dir: d.path,
          maxBytes: 100,
          grace: Duration.zero, // 排除宽限期干扰，专测「至少留 1 个」
          now: now);
      expect(r.removedFiles, equals(0));
      expect(File(p.join(d.path, 'huge')).existsSync(), isTrue,
          reason: '清空缓存等于永久禁用文件源');
    });

    test('.part 不参与配额，但仍会被顺带回收', () {
      final d = makeCache(now, {
        'data': (100, const Duration(hours: 1)),
        'x.part.9.9': (9999, const Duration(hours: 5)),
      });
      addTearDown(() => d.deleteSync(recursive: true));
      final r = trimFileCache(dir: d.path, maxBytes: 1000, now: now);
      expect(r.removedFiles, equals(0), reason: '正式文件仅 100 字节，未超配额');
      expect(r.removedPartials, equals(1), reason: '顺带回收超龄 .part');
      expect(r.remainingBytes, equals(100), reason: '.part 不计入 remainingBytes');
    });

    test('目录不存在 → 零值且不抛', () {
      final r = trimFileCache(dir: '/tmp/no-such-cache-dir-xyz', now: now);
      expect(r.removedFiles, equals(0));
      expect(r.remainingFiles, equals(0));
      expect(r.remainingBytes, equals(0));
    });

    test('默认常量：2 GiB / 10 分钟 / 1 小时', () {
      expect(kDefaultFileCacheMaxBytes, equals(2 * 1024 * 1024 * 1024));
      expect(kFileCacheGrace, equals(const Duration(minutes: 10)));
      expect(kOrphanPartialMaxAge, equals(const Duration(hours: 1)));
    });
  });
}

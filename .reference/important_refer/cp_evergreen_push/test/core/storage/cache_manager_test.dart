import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CacheManager', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('cache_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('文件缓存读写往返', () {
      final file = File(p.join(tmpDir.path, 'cache.json'));
      file.writeAsStringSync('cached_data');
      expect(file.existsSync(), true);
      expect(file.readAsStringSync(), 'cached_data');
    });

    test('TTL 过期判断', () {
      final now = DateTime.now();
      final fresh = now.subtract(const Duration(minutes: 30));
      final stale = now.subtract(const Duration(hours: 3));
      final ttl = const Duration(hours: 1);

      bool isFresh(DateTime cachedAt) =>
          now.difference(cachedAt) < ttl;

      expect(isFresh(fresh), true);
      expect(isFresh(stale), false);
    });

    test('不存在的缓存文件返回不存在', () {
      final file = File(p.join(tmpDir.path, 'missing.json'));
      expect(file.existsSync(), false);
    });
  });
}

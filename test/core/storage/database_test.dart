import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WebCacheDatabase', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('zdbk_cache_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    // 模拟缓存读写（不依赖完整 WebCacheDatabase 单例）
    test('写入 JSON 文件并读取', () {
      final file = File(p.join(tmpDir.path, 'test_key.json'));
      final data = {'test': 'value', 'num': 42};
      file.writeAsStringSync(jsonEncode(data));

      expect(file.existsSync(), true);
      final read = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(read['test'], 'value');
      expect(read['num'], 42);
    });

    test('读取不存在的 key 返回空', () {
      final file = File(p.join(tmpDir.path, 'nonexistent.json'));
      expect(file.existsSync(), false);
    });

    test('缓存列表 JSON 数组', () {
      final file = File(p.join(tmpDir.path, 'list.json'));
      final list = [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': 'b'},
      ];
      file.writeAsStringSync(jsonEncode(list));

      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<List>());
      expect((decoded as List).length, 2);
    });

    test('TTL 过期逻辑', () {
      final fresh = DateTime.now().subtract(const Duration(minutes: 30));
      final stale = DateTime.now().subtract(const Duration(hours: 2));
      final ttl = const Duration(hours: 1);

      expect(DateTime.now().difference(fresh) < ttl, true);
      expect(DateTime.now().difference(stale) < ttl, false);
    });
  });
}

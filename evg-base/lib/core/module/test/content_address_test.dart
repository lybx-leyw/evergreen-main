/// 内容寻址测试（M3-1）。
import 'package:test/test.dart';

import '../content_address.dart';

void main() {
  group('computeContentAddress (M3-1)', () {
    test('同内容同 ID', () {
      final a = computeContentAddress({'id': 'x', 'name': 'X'});
      final b = computeContentAddress({'name': 'X', 'id': 'x'});
      expect(a.id, b.id);
      expect(a.sha256, b.sha256);
    });

    test('改一字节 → 不同 ID', () {
      final a = computeContentAddress({'id': 'x', 'name': 'X'});
      final b = computeContentAddress({'id': 'x', 'name': 'Y'});
      expect(a.id, isNot(b.id));
    });

    test('字段顺序不影响 ID（规范化）', () {
      final a = computeContentAddress({'a': 1, 'b': 2});
      final b = computeContentAddress({'b': 2, 'a': 1});
      expect(a.id, b.id);
    });

    test('资源哈希纳入寻址：改资源 → 不同 ID', () {
      final a = computeContentAddress({'id': 'x'},
          resourceHashes: {'s.js': 'aaa'});
      final b = computeContentAddress({'id': 'x'},
          resourceHashes: {'s.js': 'bbb'});
      expect(a.id, isNot(b.id));
    });

    test('idLength 截断生效', () {
      final a = computeContentAddress({'id': 'x'}, idLength: 8);
      expect(a.id.length, 8);
      expect(a.sha256.length, 64);
    });

    test('idLength 非法 → 抛', () {
      expect(() => computeContentAddress({'id': 'x'}, idLength: 0),
          throwsArgumentError);
      expect(() => computeContentAddress({'id': 'x'}, idLength: 100),
          throwsArgumentError);
    });

    test('sha256OfString 稳定', () {
      // 空串 SHA-256 已知值。
      expect(sha256OfString(''),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });
}

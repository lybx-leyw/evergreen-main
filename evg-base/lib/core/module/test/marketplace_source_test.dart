/// MarketplaceSource 解析层测试（M5-1 · 纯逻辑）。
import 'package:test/test.dart';

import '../marketplace_source.dart';

void main() {
  group('MarketplaceSource.fromJson', () {
    test('github 源正常解析', () {
      final s = MarketplaceSource.fromJson({
        'id': 'zju',
        'kind': 'github',
        'src': 'github:ZJU-Evergreen/plugins',
        'name': 'ZJU 官方',
      });
      expect(s.id, 'zju');
      expect(s.kind, MarketplaceSourceKind.github);
      expect(s.name, 'ZJU 官方');
      expect(s.enabled, isTrue);
      expect(s.github.repo, 'plugins');
      expect(s.github.owner, 'ZJU-Evergreen');
    });

    test('kind 大小写不敏感', () {
      final s = MarketplaceSource.fromJson({
        'id': 'x',
        'kind': 'LocalDir',
        'src': '/tmp/p',
      });
      expect(s.kind, MarketplaceSourceKind.localDir);
    });

    test('缺 id → FormatException', () {
      expect(
        () => MarketplaceSource.fromJson({'kind': 'github', 'src': 'a/b'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺 kind → FormatException', () {
      expect(
        () => MarketplaceSource.fromJson({'id': 'x', 'src': 'a/b'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('非法 kind → FormatException', () {
      expect(
        () => MarketplaceSource.fromJson(
            {'id': 'x', 'kind': 's3', 'src': 'a/b'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺 src → FormatException', () {
      expect(
        () => MarketplaceSource.fromJson({'id': 'x', 'kind': 'github'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('enabled 缺省为 true，可显式 false', () {
      final a = MarketplaceSource.fromJson(
          {'id': 'a', 'kind': 'github', 'src': 'o/r'});
      expect(a.enabled, isTrue);
      final b = MarketplaceSource.fromJson(
          {'id': 'b', 'kind': 'github', 'src': 'o/r', 'enabled': false});
      expect(b.enabled, isFalse);
    });

    test('非 github 源访问 .github → StateError', () {
      final s = MarketplaceSource.fromJson(
          {'id': 'x', 'kind': 'localDir', 'src': '/tmp'});
      expect(() => s.github, throwsA(isA<StateError>()));
    });
  });

  group('parseMarketplaceSources', () {
    test('正常解析多条', () {
      const body = '''
      {
        "sources": [
          {"id": "a", "kind": "github", "src": "o1/r1"},
          {"id": "b", "kind": "localDir", "src": "/tmp"}
        ]
      }
      ''';
      final list = parseMarketplaceSources(body);
      expect(list, hasLength(2));
      expect(list[0].id, 'a');
      expect(list[1].id, 'b');
    });

    test('顶层非对象 → FormatException', () {
      expect(() => parseMarketplaceSources('[]'),
          throwsA(isA<FormatException>()));
    });

    test('缺 sources 数组 → FormatException', () {
      expect(() => parseMarketplaceSources('{"foo": 1}'),
          throwsA(isA<FormatException>()));
    });

    test('sources 非数组 → FormatException', () {
      expect(() => parseMarketplaceSources('{"sources": {}}'),
          throwsA(isA<FormatException>()));
    });

    test('单条非法 → 透传 FormatException（不全集跳过）', () {
      const body = '''
      {
        "sources": [
          {"id": "good", "kind": "github", "src": "o/r"},
          {"id": "bad"}
        ]
      }
      ''';
      expect(() => parseMarketplaceSources(body),
          throwsA(isA<FormatException>()));
    });

    test('按 id 去重，保留首次出现', () {
      const body = '''
      {
        "sources": [
          {"id": "dup", "kind": "github", "src": "o/first"},
          {"id": "dup", "kind": "github", "src": "o/second"}
        ]
      }
      ''';
      final list = parseMarketplaceSources(body);
      expect(list, hasLength(1));
      expect(list.first.src, 'o/first');
    });
  });

  group('enabledSources', () {
    test('过滤掉 enabled=false', () {
      final all = [
        MarketplaceSource.fromJson(
            {'id': 'a', 'kind': 'github', 'src': 'o/a'}),
        MarketplaceSource.fromJson(
            {'id': 'b', 'kind': 'github', 'src': 'o/b', 'enabled': false}),
      ];
      final en = enabledSources(all);
      expect(en, hasLength(1));
      expect(en.first.id, 'a');
    });
  });

  group('toJson 往返', () {
    test('fromJson → toJson → fromJson 等价', () {
      final src = MarketplaceSource.fromJson({
        'id': 'x',
        'kind': 'github',
        'src': 'o/r@v1',
        'name': 'X',
        'enabled': false,
      });
      final round = MarketplaceSource.fromJson(src.toJson());
      expect(round.id, src.id);
      expect(round.kind, src.kind);
      expect(round.src, src.src);
      expect(round.name, src.name);
      expect(round.enabled, src.enabled);
    });
  });
}

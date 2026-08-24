/// registry 解析测试（M6-0）。
import 'dart:convert';

import 'package:test/test.dart';

import '../plugin_registry.dart';

void main() {
  group('parsePluginRegistry (M6-0)', () {
    test('解析含 2 个真实条目的 registry', () {
      const body = '''
      {
        "plugins": [
          {
            "id": "zjucrawler",
            "name": "ZJU Crawler",
            "description": "浙大成绩爬虫",
            "author": "cubicYYY",
            "version": "0.1.0",
            "repo": "https://github.com/cubicYYY/ZJUCrawler",
            "lattice": "data-source",
            "dimensions": ["data"],
            "install": { "type": "github", "url": "https://github.com/cubicYYY/ZJUCrawler" },
            "installCount": 0,
            "rating": 0.0
          },
          {
            "id": "zju-ical",
            "name": "ZJU iCal",
            "description": "浙大课表导出 iCal",
            "author": "cxz66666",
            "version": "1.0.0",
            "repo": "https://github.com/cxz66666/zju-ical",
            "lattice": "data-source",
            "dimensions": ["data"],
            "install": { "type": "github", "url": "https://github.com/cxz66666/zju-ical" }
          }
        ]
      }
      ''';
      final plugins = parsePluginRegistry(body);
      expect(plugins.length, 2);
      expect(plugins[0].id, 'zjucrawler');
      expect(plugins[0].name, 'ZJU Crawler');
      expect(plugins[0].installUrl, 'https://github.com/cubicYYY/ZJUCrawler');
      expect(plugins[1].id, 'zju-ical');
      expect(plugins[1].dimensions, ['data']);
    });

    test('installUrl 回退到 repo（无 install 字段）', () {
      const body = '''
      {
        "plugins": [
          { "id": "x", "name": "X", "repo": "https://github.com/a/x" }
        ]
      }
      ''';
      final plugins = parsePluginRegistry(body);
      expect(plugins.single.installUrl, 'https://github.com/a/x');
    });

    test('缺 id 抛 FormatException（fail-closed）', () {
      const body = '{"plugins": [{"name": "无 id"}]}';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('缺 plugins 数组抛 FormatException', () {
      const body = '{"foo": []}';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('顶层非对象抛 FormatException', () {
      const body = '[]';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('重复 id 去重保留首次', () {
      const body = '''
      {
        "plugins": [
          {"id": "dup", "name": "A", "version": "1"},
          {"id": "dup", "name": "B", "version": "2"}
        ]
      }
      ''';
      final plugins = parsePluginRegistry(body);
      expect(plugins.length, 1);
      expect(plugins.single.name, 'A');
    });

    test('未知字段静默忽略', () {
      const body = '''
      {
        "plugins": [
          {"id": "y", "name": "Y", "unknownField": 123, "extra": {"a": 1}}
        ]
      }
      ''';
      final plugins = parsePluginRegistry(body);
      expect(plugins.single.id, 'y');
      expect(plugins.single.name, 'Y');
    });
  });

  group('PluginManifest（M6 · 补 4）', () {
    test('inline manifest 解析', () {
      const body = '''
      {
        "plugins": [
          {
            "id": "m1", "name": "M1",
            "manifest": { "source": "inline", "json": { "type": "module", "id": "m1", "name": "M1" } }
          }
        ]
      }
      ''';
      final p = parsePluginRegistry(body).single;
      expect(p.manifest, isNotNull);
      expect(p.manifest!.source, PluginManifestSource.inline);
      expect(p.manifest!.inline, {'type': 'module', 'id': 'm1', 'name': 'M1'});
    });

    test('local manifest 解析', () {
      const body = '''
      {
        "plugins": [
          {
            "id": "m2", "name": "M2",
            "manifest": { "source": "local", "path": "assets/m2" }
          }
        ]
      }
      ''';
      final p = parsePluginRegistry(body).single;
      expect(p.manifest!.source, PluginManifestSource.local);
      expect(p.manifest!.path, 'assets/m2');
    });

    test('github manifest 解析', () {
      const body = '''
      {
        "plugins": [
          {
            "id": "m2b", "name": "M2b",
            "manifest": { "source": "github", "repo": "owner/repo", "path": "evergreen/manifest.json" }
          }
        ]
      }
      ''';
      final p = parsePluginRegistry(body).single;
      expect(p.manifest!.source, PluginManifestSource.github);
      expect(p.manifest!.repo, 'owner/repo');
      expect(p.manifest!.path, 'evergreen/manifest.json');
    });

    test('无 manifest 字段 → null（回退旧逻辑）', () {
      const body = '{"plugins": [{"id": "m3", "name": "M3"}]}';
      expect(parsePluginRegistry(body).single.manifest, isNull);
    });

    test('inline 缺 json 抛 FormatException（fail-closed）', () {
      const body = '''
      {"plugins": [{"id": "m4", "name": "M4", "manifest": {"source": "inline"}}]}
      ''';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('local 缺 path 抛 FormatException（fail-closed）', () {
      const body = '''
      {"plugins": [{"id": "m5", "name": "M5", "manifest": {"source": "local"}}]}
      ''';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('github 缺 repo/path 抛 FormatException（fail-closed）', () {
      const body = '''
      {"plugins": [{"id": "m5b", "name": "M5b", "manifest": {"source": "github", "repo": "owner/repo"}}]}
      ''';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('未知 source 抛 FormatException（fail-closed）', () {
      const body = '''
      {"plugins": [{"id": "m6", "name": "M6", "manifest": {"source": "magic"}}]}
      ''';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });

    test('toJson 往返保留 manifest', () {
      const body = '''
      {
        "plugins": [
          {
            "id": "m7", "name": "M7",
            "manifest": { "source": "inline", "json": { "type": "data-source", "id": "m7" } }
          }
        ]
      }
      ''';
      final p = parsePluginRegistry(body).single;
      final round = RegistryPlugin.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(round.manifest!.source, PluginManifestSource.inline);
      expect(round.manifest!.inline!['type'], 'data-source');
    });
  });

  group('installStrategy（M6 · 补 5）', () {
    test('默认 source（无 strategy 字段）', () {
      const body = '{"plugins": [{"id": "s1", "name": "S1"}]}';
      expect(parsePluginRegistry(body).single.installStrategy,
          PluginInstallStrategy.source);
    });

    test('显式 source', () {
      const body = '''
      {"plugins": [{"id": "s2", "name": "S2", "install": {"strategy": "source"}}]}
      ''';
      expect(parsePluginRegistry(body).single.installStrategy,
          PluginInstallStrategy.source);
    });

    test('release + assetPattern', () {
      const body = '''
      {"plugins": [{"id": "s3", "name": "S3", "install": {"strategy": "release", "assetPattern": "windows-amd64"}}]}
      ''';
      final p = parsePluginRegistry(body).single;
      expect(p.installStrategy, PluginInstallStrategy.release);
      expect(p.releaseAssetPattern, 'windows-amd64');
    });

    test('未知 strategy 抛 FormatException（fail-closed）', () {
      const body = '''
      {"plugins": [{"id": "s4", "name": "S4", "install": {"strategy": "magic"}}]}
      ''';
      expect(() => parsePluginRegistry(body), throwsFormatException);
    });
  });

  group('manifestRelativePath（M6 · 补 5）', () {
    test('module → module/manifest.json', () {
      expect(manifestRelativePath('module'), 'module/manifest.json');
    });

    test('data-source → data/manifest.json（特例映射）', () {
      expect(manifestRelativePath('data-source'), 'data/manifest.json');
    });

    test('agent → agent/manifest.json', () {
      expect(manifestRelativePath('agent'), 'agent/manifest.json');
    });

    test('空/空串 → null', () {
      expect(manifestRelativePath(null), isNull);
      expect(manifestRelativePath(''), isNull);
    });
  });
}

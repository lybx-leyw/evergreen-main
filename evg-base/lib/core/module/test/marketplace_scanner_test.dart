/// MarketplaceScanner 纯逻辑单测（M5-5）。
///
/// clone 用 fake：把预置目录内容写入 targetDir，验证 github 源扫描链路
/// 与 localDir 源扫描链路一致，且不依赖真实 git / 网络。
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../marketplace_scanner.dart';
import '../marketplace_source.dart';
import '../github_source.dart';

/// fake clone：把 [from] 目录整体复制到 [targetDir]。
Future<void> _fakeClone(GithubSource src, String targetDir) async {
  final from = Directory('test/_fixtures/gh_${src.owner}_${src.repo}');
  if (!from.existsSync()) {
    throw StateError('fake clone 源不存在: ${from.path}');
  }
  // 复制目录树到 targetDir
  await _copyDir(from, Directory(targetDir));
}

Future<void> _copyDir(Directory src, Directory dst) async {
  if (dst.existsSync()) dst.deleteSync(recursive: true);
  dst.createSync(recursive: true);
  for (final e in src.listSync(recursive: true)) {
    final rel = p.relative(e.path, from: src.path);
    final dest = '${dst.path}/$rel';
    if (e is Directory) {
      Directory(dest).createSync(recursive: true);
    } else if (e is File) {
      File(dest).createSync(recursive: true);
      await File(dest).writeAsBytes(await e.readAsBytes());
    }
  }
}

void main() {
  group('localDir 源扫描', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mkt_local_');
      // 造一个 module 插件
      final modDir = Directory('${tmp.path}/my-mod');
      modDir.createSync(recursive: true);
      Directory('${modDir.path}/module').createSync(recursive: true);
      File('${modDir.path}/module/manifest.json')
          .writeAsStringSync('{"id":"my-mod","name":"我的模块","type":"module"}');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('扫出 module 类型条目', () async {
      final src = MarketplaceSource(
        id: 'local1',
        kind: MarketplaceSourceKind.localDir,
        src: tmp.path,
      );
      final results = await scanSources([src], clone: _fakeClone);
      expect(results, hasLength(1));
      expect(results.first.entries, hasLength(1));
      final e = results.first.entries.first;
      expect(e.id, 'my-mod');
      expect(e.type, 'module');
      expect(e.sourceId, 'local1');
      expect(e.dirPath, endsWith('my-mod'));
    });
  });

  group('github 源扫描（fake clone）', () {
    late Directory fixtureBase;
    setUp(() {
      // 预置 fake 仓库：test/_fixtures/gh_<owner>_<repo>/
      fixtureBase = Directory('test/_fixtures');
      final repo = Directory('${fixtureBase.path}/gh_zju_plugins');
      repo.createSync(recursive: true);
      final agentDir = Directory('${repo.path}/cool-agent');
      agentDir.createSync(recursive: true);
      Directory('${agentDir.path}/agent').createSync(recursive: true);
      File('${agentDir.path}/agent/manifest.json')
          .writeAsStringSync('{"id":"cool-agent","name":"酷代理","type":"agent"}');
    });
    tearDown(() {
      if (fixtureBase.existsSync()) fixtureBase.deleteSync(recursive: true);
    });

    test('fake clone 后扫出 agent 条目', () async {
      final src = MarketplaceSource(
        id: 'gh1',
        kind: MarketplaceSourceKind.github,
        src: 'github:zju/plugins',
      );
      final results = await scanSources(
        [src],
        clone: _fakeClone,
        cacheDir: Directory.systemTemp.createTempSync('mkt_cache_').path,
      );
      expect(results, hasLength(1));
      expect(results.first.failed, isFalse);
      expect(results.first.entries, hasLength(1));
      expect(results.first.entries.first.type, 'agent');
      expect(results.first.entries.first.sourceId, 'gh1');
    });

    test('clone 抛错时源标记失败但不影响其它源', () async {
      final bad = MarketplaceSource(
        id: 'gh-bad',
        kind: MarketplaceSourceKind.github,
        src: 'github:nonexist/repo',
      );
      final good = MarketplaceSource(
        id: 'local-good',
        kind: MarketplaceSourceKind.localDir,
        src: Directory.systemTemp.createTempSync('mkt_g_').path,
      );
      final results = await scanSources([bad, good], clone: _fakeClone);
      final badRes = results.firstWhere((r) => r.source.id == 'gh-bad');
      final goodRes = results.firstWhere((r) => r.source.id == 'local-good');
      expect(badRes.failed, isTrue);
      expect(goodRes.failed, isFalse);
    });
  });

  test('collectEntries 按 id 去重保留首次', () {
    final a = MarketplaceEntry(
      id: 'x',
      name: 'X',
      type: 'module',
      dirPath: '/a',
      sourceId: 's1',
    );
    final b = MarketplaceEntry(
      id: 'x',
      name: 'X2',
      type: 'module',
      dirPath: '/b',
      sourceId: 's2',
    );
    final c = MarketplaceEntry(
      id: 'y',
      name: 'Y',
      type: 'agent',
      dirPath: '/c',
      sourceId: 's1',
    );
    final out = collectEntries([
      SourceScanResult(
          MarketplaceSource(id: 's1', kind: MarketplaceSourceKind.localDir, src: '/x'),
          [a, c]),
      SourceScanResult(
          MarketplaceSource(id: 's2', kind: MarketplaceSourceKind.localDir, src: '/y'),
          [b]),
    ]);
    expect(out, hasLength(2));
    expect(out.first.id, 'x'); // 保留首次（s1 的 a）
  });
}

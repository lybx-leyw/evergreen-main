/// GitHub 源 + 脚手架测试（M4-1/M4-2/M4-3）。
import 'package:test/test.dart';

import 'dart:convert';

import '../github_source.dart';
import '../lattice.dart';
import '../module_descriptor.dart';
import '../runtime.dart';
import '../scaffold_plugin.dart';

void main() {
  group('parseGithubSource (M4-1)', () {
    test('github:owner/repo', () {
      final s = parseGithubSource('github:lybx-leyw/evergreen-main');
      expect(s.owner, 'lybx-leyw');
      expect(s.repo, 'evergreen-main');
      expect(s.ref, isNull);
      expect(s.cloneUrl, 'https://github.com/lybx-leyw/evergreen-main.git');
    });

    test('github:owner/repo@ref', () {
      final s = parseGithubSource('github:lybx-leyw/evergreen-main@v2.0');
      expect(s.owner, 'lybx-leyw');
      expect(s.repo, 'evergreen-main');
      expect(s.ref, 'v2.0');
    });

    test('https URL', () {
      final s = parseGithubSource('https://github.com/lybx-leyw/evergreen-main');
      expect(s.owner, 'lybx-leyw');
      expect(s.repo, 'evergreen-main');
    });

    test('https URL + .git', () {
      final s = parseGithubSource('https://github.com/a/b.git');
      expect(s.repo, 'b');
    });

    test('https URL /tree/ref', () {
      final s =
          parseGithubSource('https://github.com/a/b/tree/feature-x');
      expect(s.ref, 'feature-x');
    });

    test('非法 → 抛', () {
      expect(() => parseGithubSource(''), throwsFormatException);
      expect(() => parseGithubSource('github:bad'), throwsFormatException);
      expect(() => parseGithubSource('https://gitlab.com/a/b'),
          throwsFormatException);
    });
  });

  group('classifyRepo (M4-2)', () {
    test('有 runtime → sidecar', () {
      final c = RepoClassification(
          const LatticeSignals(hasRuntime: true), ['package.json']);
      expect(c.classify(), Lattice.sidecar);
    });
    test('template=html → web-bridged', () {
      final c = RepoClassification(const LatticeSignals(template: 'html'));
      expect(c.classify(), Lattice.webBridged);
    });
    test('dataSource 存在 → data-source', () {
      final c = RepoClassification(const LatticeSignals(hasDataSource: true));
      expect(c.classify(), Lattice.dataSource);
    });
    test('activateSkills → agent-tool', () {
      final c =
          RepoClassification(const LatticeSignals(hasActivateSkills: true));
      expect(c.classify(), Lattice.agentTool);
    });
    test('纯 v4 → static-web（最安全兜底）', () {
      final c = RepoClassification(const LatticeSignals(isPlainV4: true));
      expect(c.classify(), Lattice.staticWeb);
    });
  });

  group('generateManifest (M4-3)', () {
    test('static-web 生成物可 fromJson 往返', () {
      final map = generateManifest(const ScaffoldInput(
        id: 'zju-foo',
        name: 'ZJU Foo',
        lattice: Lattice.staticWeb,
      ));
      final d = ModuleDescriptor.fromJson(map);
      expect(d.lattice, Lattice.staticWeb);
      expect(d.id, 'zju-foo');
    });

    test('sidecar 生成物含 runtime 且可往返', () {
      final map = generateManifest(ScaffoldInput(
        id: 'zju-side',
        name: 'ZJU Side',
        lattice: Lattice.sidecar,
        entry: 'src/server.js',
        runtimeKind: RuntimeKind.node,
      ));
      final d = ModuleDescriptor.fromJson(map);
      expect(d.lattice, Lattice.sidecar);
      expect(d.runtime!.kind, RuntimeKind.node);
    });

    test('sidecar 缺 runtimeKind → fail-closed', () {
      expect(
        () => generateManifest(ScaffoldInput(
          id: 'x',
          name: 'X',
          lattice: Lattice.sidecar,
          entry: 's.js',
        )),
        throwsFormatException,
      );
    });

    test('data-source 生成物含 dataSource 且可往返', () {
      final map = generateManifest(ScaffoldInput(
        id: 'zju-data',
        name: 'ZJU Data',
        lattice: Lattice.dataSource,
        dataSourceEndpoint: 'orch://zju',
      ));
      final d = ModuleDescriptor.fromJson(map);
      expect(d.lattice, Lattice.dataSource);
    });

    test('generateManifestJson 返回合法 JSON 字符串', () {
      final json = generateManifestJson(const ScaffoldInput(
        id: 'zju-x',
        name: 'ZJU X',
        lattice: Lattice.webBridged,
      ));
      final back = ModuleDescriptor.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
      expect(back.lattice, Lattice.webBridged);
    });
  });
}

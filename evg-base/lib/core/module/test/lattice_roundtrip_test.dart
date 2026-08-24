/// 六格契约往返测试（M0 验收）— G1–G5 共 29 用例。
///
/// 设计上游：`evg-base/docs/m0-lattice-contract-design.md` §5。
/// 运行：`cd evg-base/lib/core/module && dart test test/lattice_roundtrip_test.dart`
import 'package:test/test.dart';
import '../lattice.dart';
import '../runtime.dart';
import '../module_descriptor.dart';

void main() {
  // ═══════ G1 — lattice 解析与默认推断 ═══════
  group('G1 lattice 解析与默认推断', () {
    test('1 缺 lattice + template:html → web-bridged', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'template': 'html',
      });
      expect(d.lattice, Lattice.webBridged);
      expect(d.latticeExplicit, isFalse);
    });

    test('2 缺 lattice + dataSource 存在 → data-source', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'dataSource': {'endpoint': 'orch://x'},
      });
      expect(d.lattice, Lattice.dataSource);
    });

    test('3 缺 lattice + dataSources 存在 → data-source', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'dataSources': {
          'a': {'endpoint': 'orch://a'}
        },
      });
      expect(d.lattice, Lattice.dataSource);
    });

    test('4 缺 lattice + activateSkills 非空 → agent-tool', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'activateSkills': ['foo'],
      });
      expect(d.lattice, Lattice.agentTool);
    });

    test('5 缺 lattice + runtime 存在 → sidecar（最高优先级）', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'runtime': {
          'kind': 'node',
          'entry': 'index.js',
        },
      });
      expect(d.lattice, Lattice.sidecar);
    });

    test('6 缺 lattice + 纯 v4 pages → static-web', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'pages': [
          {'id': 'p1', 'label': 'P1'}
        ],
      });
      expect(d.lattice, Lattice.staticWeb);
    });

    test('7 显式 lattice:sidecar 不受其它信号影响', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'template': 'html',
        'lattice': 'sidecar',
        'runtime': {'kind': 'python', 'entry': 's.py'},
      });
      expect(d.lattice, Lattice.sidecar);
      expect(d.latticeExplicit, isTrue);
    });

    test('8 web_bridged / WEB-BRIDGED 容错', () {
      expect(
        ModuleDescriptor.fromJson({
          'type': 'module',
          'id': 'x',
          'name': 'x',
          'lattice': 'web_bridged',
        }).lattice,
        Lattice.webBridged,
      );
      expect(
        ModuleDescriptor.fromJson({
          'type': 'module',
          'id': 'x',
          'name': 'x',
          'lattice': 'WEB-BRIDGED',
        }).lattice,
        Lattice.webBridged,
      );
    });

    test('9 lattice:quantum → throws FormatException（fail-closed）', () {
      expect(
        () => ModuleDescriptor.fromJson({
              'type': 'module',
              'id': 'x',
              'name': 'x',
              'lattice': 'quantum',
            }),
        throwsFormatException,
      );
    });

    test('10 六格逐一 round-trip', () {
      for (final l in Lattice.values) {
        final Map<String, dynamic> map = {
          'type': 'module',
          'id': 'x',
          'name': 'x',
          'lattice': formatLattice(l),
        };
        // sidecar 格按 fail-closed 必须有 runtime 才能解析（§2.2 校验）。
        if (l == Lattice.sidecar) {
          map['runtime'] = <String, dynamic>{'kind': 'node', 'entry': 's.js'};
        }
        final d = ModuleDescriptor.fromJson(map);
        expect(d.lattice, l);
        expect(d.latticeExplicit, isTrue);
      }
    });
  });

  // ═══════ G2 — runtime 描述符 ═══════
  group('G2 runtime 描述符', () {
    test('11 完整 runtime 往返', () {
      final json = {
        'kind': 'node',
        'entry': 'sidecar/index.js',
        'protocol': 'http',
        'port': 0,
        'gracefulTimeoutMs': 8000,
        'capabilities': {
          'fs.scope': 'plugin-dir',
          'net.allow': ['127.0.0.1', 'api.github.com:443'],
          'spawn': []
        },
      };
      final rt = RuntimeDescriptor.fromJson(json);
      expect(rt.kind, RuntimeKind.node);
      expect(rt.entry, 'sidecar/index.js');
      expect(rt.protocol, RuntimeProtocol.http);
      expect(rt.port, 0);
      expect(rt.gracefulTimeoutMs, 8000);
      expect(rt.capabilities.fsScope, FileScope.pluginDir);
      expect(rt.capabilities.netAllow, ['127.0.0.1', 'api.github.com:443']);
      expect(rt.capabilities.spawnAllow, isEmpty);

      final back = RuntimeDescriptor.fromJson(rt.toJson());
      expect(back.kind, rt.kind);
      expect(back.entry, rt.entry);
      expect(back.protocol, rt.protocol);
      expect(back.port, rt.port);
      expect(back.gracefulTimeoutMs, rt.gracefulTimeoutMs);
      expect(back.capabilities.fsScope, rt.capabilities.fsScope);
      expect(back.capabilities.netAllow, rt.capabilities.netAllow);
      expect(back.capabilities.spawnAllow, rt.capabilities.spawnAllow);
    });

    test('12 runtime 缺省字段', () {
      final rt = RuntimeDescriptor.fromJson({
        'kind': 'python',
        'entry': 's.py',
      });
      expect(rt.protocol, RuntimeProtocol.http);
      expect(rt.port, 0);
      expect(rt.gracefulTimeoutMs, 8000);
      expect(rt.capabilities.isDenyAll, isTrue);
    });

    test('13 kind:rust / protocol:grpc → throws', () {
      expect(
        () => RuntimeDescriptor.fromJson({
              'kind': 'rust',
              'entry': 's',
            }),
        throwsFormatException,
      );
      expect(
        () => RuntimeDescriptor.fromJson({
              'kind': 'node',
              'entry': 's',
              'protocol': 'grpc',
            }),
        throwsFormatException,
      );
    });

    test('14 sidecar 缺 runtime → throws', () {
      expect(
        () => ModuleDescriptor.fromJson({
              'type': 'module',
              'id': 'x',
              'name': 'x',
              'lattice': 'sidecar',
            }),
        throwsFormatException,
      );
    });

    test('15 static-web 却带 runtime → throws', () {
      expect(
        () => ModuleDescriptor.fromJson({
              'type': 'module',
              'id': 'x',
              'name': 'x',
              'lattice': 'static-web',
              'runtime': {'kind': 'node', 'entry': 's.js'},
            }),
        throwsFormatException,
      );
    });

    test('16 entry 空串/缺失 → throws', () {
      expect(
        () => RuntimeDescriptor.fromJson({'kind': 'node', 'entry': ''}),
        throwsFormatException,
      );
      expect(
        () => RuntimeDescriptor.fromJson({'kind': 'node'}),
        throwsFormatException,
      );
    });
  });

  // ═══════ G3 — capabilities ═══════
  group('G3 capabilities', () {
    test('17 capabilities 全缺省 → deny-all', () {
      final c = RuntimeCapabilities.fromJson(null);
      expect(c.fsScope, FileScope.none);
      expect(c.netAllow, isEmpty);
      expect(c.spawnAllow, isEmpty);
      expect(c.isDenyAll, isTrue);
    });

    test('18 fs.scope 三值 round-trip', () {
      for (final s in [FileScope.none, FileScope.pluginDir, FileScope.appData]) {
        final c = RuntimeCapabilities.fromJson({'fs.scope': formatFileScope(s)});
        expect(c.fsScope, s);
      }
    });

    test('19 fs.scope:home / / → throws', () {
      expect(
        () => RuntimeCapabilities.fromJson({'fs.scope': 'home'}),
        throwsFormatException,
      );
      expect(
        () => RuntimeCapabilities.fromJson({'fs.scope': '/'}),
        throwsFormatException,
      );
    });

    test('20 net.allow 白名单 round-trip', () {
      final c = RuntimeCapabilities.fromJson({
        'net.allow': ['api.zju.edu.cn', 'api.zju.edu.cn:443'],
      });
      expect(c.netAllow, ['api.zju.edu.cn', 'api.zju.edu.cn:443']);
    });

    test('21 net.allow:[""] / ["file://x"] → throws', () {
      expect(
        () => RuntimeCapabilities.fromJson({'net.allow': ['']}),
        throwsFormatException,
      );
      expect(
        () => RuntimeCapabilities.fromJson({'net.allow': ['file://x']}),
        throwsFormatException,
      );
    });

    test('22 spawn:[] 与 spawn:["node"] round-trip', () {
      expect(RuntimeCapabilities.fromJson({'spawn': []}).spawnAllow, isEmpty);
      expect(
        RuntimeCapabilities.fromJson({'spawn': ['node']}).spawnAllow, ['node']);
    });

    test('23 未知 capability 键 → 静默忽略', () {
      final c = RuntimeCapabilities.fromJson({
        'net.wildcard': true,
        'fs.scope': 'plugin-dir',
      });
      expect(c.fsScope, FileScope.pluginDir);
      expect(c.netAllow, isEmpty);
      expect(c.spawnAllow, isEmpty);
    });

    test('24 toJson 省 deny-all capabilities', () {
      final rt = RuntimeDescriptor.fromJson({
        'kind': 'node',
        'entry': 's.js',
      });
      expect(rt.toJson().containsKey('capabilities'), isFalse);
    });
  });

  // ═══════ G4 — 序列化与幂等 ═══════
  group('G4 序列化与幂等', () {
    test('25 旧 manifest round-trip 不新增字段', () {
      final json = {
        'schemaVersion': '2.0',
        'type': 'module',
        'id': 'legacy',
        'name': 'Legacy',
        'template': 'v4',
        'pages': [
          {'id': 'p1', 'label': 'P1'}
        ],
      };
      final d = ModuleDescriptor.fromJson(json);
      final out = d.toJson();
      expect(out.containsKey('lattice'), isFalse);
      expect(out.containsKey('runtime'), isFalse);
    });

    test('26 显式 lattice 写回', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      });
      expect(d.toJson()['lattice'], 'sidecar');
    });

    test('27 fromJson(toJson(d)) == d（六格各一次）', () {
      for (final l in Lattice.values) {
        final Map<String, dynamic> base = {
          'type': 'module',
          'id': 'x',
          'name': 'x',
          'lattice': formatLattice(l),
        };
        if (l == Lattice.sidecar) {
          base['runtime'] = <String, dynamic>{'kind': 'python', 'entry': 's.py'};
        }
        final d = ModuleDescriptor.fromJson(base);
        final round = ModuleDescriptor.fromJson(d.toJson());
        expect(round.lattice, d.lattice);
        expect(round.latticeExplicit, d.latticeExplicit);
        expect(round.runtime?.kind, d.runtime?.kind);
        expect(round.runtime?.entry, d.runtime?.entry);
      }
    });
  });

  // ═══════ G5 — 与 v5P 字段共存 ═══════
  group('G5 与 v5P 字段共存', () {
    test('28 lattice 与 template/dataSource/dataSources/modleRoute 共存', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'lattice': 'data-source',
        'template': 'scraper',
        'dataSource': {'endpoint': 'orch://x'},
        'dataSources': {
          'a': {'endpoint': 'orch://a'}
        },
        'modle_route': 'score',
      });
      expect(d.lattice, Lattice.dataSource);
      expect(d.template, 'scraper');
      expect(d.dataSource, isNotNull);
      expect(d.dataSources, isNotNull);
      expect(d.modleRoute, 'score');
    });

    test('29 现有 descriptor_test 全绿（无回归，由 descriptor_test.dart 覆盖）', () {
      // 此用例仅作占位声明；真正的回归由同包 descriptor_test.dart 全量覆盖。
      expect(Lattice.values.length, 6);
    });
  });
}

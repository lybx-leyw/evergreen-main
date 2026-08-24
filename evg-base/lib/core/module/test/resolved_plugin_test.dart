/// ResolvedPlugin 单一事实源测试（M0-12）。
import 'package:test/test.dart';
import '../lattice.dart';
import '../module_descriptor.dart';
import '../resolved_plugin.dart';
import '../runtime.dart';

void main() {
  group('ResolvedPlugin', () {
    test('fromDescriptor 携带 lattice/runtime', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'side',
        'name': 'Side',
        'lattice': 'sidecar',
        'runtime': {
          'kind': 'node',
          'entry': 's.js',
          'capabilities': {'fs.scope': 'plugin-dir'},
        },
      });
      final r = ResolvedPlugin.fromDescriptor(d);
      expect(r.id, 'side');
      expect(r.lattice, Lattice.sidecar);
      expect(r.isSidecar, isTrue);
      expect(r.runtime, isNotNull);
      expect(r.capabilities.fsScope, FileScope.pluginDir);
    });

    test('fromDescriptor 推断 lattice（无显式声明）', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'template': 'html',
      });
      final r = ResolvedPlugin.fromDescriptor(d);
      expect(r.lattice, Lattice.webBridged);
      expect(r.latticeExplicit, isFalse);
      expect(r.isSidecar, isFalse);
      expect(r.capabilities.isDenyAll, isTrue);
    });

    test('非 sidecar 格 capabilities 为 deny-all', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'lattice': 'static-web',
      });
      final r = ResolvedPlugin.fromDescriptor(d);
      expect(r.capabilities.isDenyAll, isTrue);
    });

    test('幂等：fromDescriptor 两次结果等价', () {
      final d = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'x',
        'name': 'x',
        'lattice': 'data-source',
        'dataSource': {'endpoint': 'orch://x'},
      });
      final a = ResolvedPlugin.fromDescriptor(d);
      final b = ResolvedPlugin.fromDescriptor(d);
      expect(a.lattice, b.lattice);
      expect(a.id, b.id);
      expect(a == b, isTrue);
    });

    test('== 基于 id', () {
      final d1 = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'same',
        'name': 'A',
      });
      final d2 = ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'same',
        'name': 'B',
      });
      expect(ResolvedPlugin.fromDescriptor(d1) ==
          ResolvedPlugin.fromDescriptor(d2), isTrue);
    });
  });
}

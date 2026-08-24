/// M0-13/14/15 集成测试：registry/loader 消费 ResolvedPlugin + lattice↔capability 桥接。
import 'package:test/test.dart';
import '../capability.dart';
import '../lattice.dart';
import '../module_descriptor.dart';
import '../module_registry.dart';
import '../resolved_plugin.dart';

void main() {
  group('ModuleRegistry + ResolvedPlugin (M0-13)', () {
    test('含 lattice:sidecar 的 manifest 被注册且能被 findByLattice 命中', () {
      final registry = ModuleRegistry();
      registry.register(ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'sc1',
        'name': 'SC1',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
        'route': '/sc1',
      }));
      registry.register(ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'web1',
        'name': 'WEB1',
        'lattice': 'web-bridged',
        'route': '/web1',
      }));
      registry.seal();

      final sidecars = registry.findByLattice(Lattice.sidecar);
      expect(sidecars.length, 1);
      expect(sidecars.first.id, 'sc1');
      expect(sidecars.first.isSidecar, isTrue);

      final resolved = registry.resolved;
      expect(resolved.any((r) => r.id == 'sc1' && r.lattice == Lattice.sidecar),
          isTrue);
      expect(resolved.any((r) => r.id == 'web1' && r.lattice == Lattice.webBridged),
          isTrue);
    });

    test('旧 manifest（无 lattice）字节兼容且推断为 static-web', () {
      final registry = ModuleRegistry();
      registry.register(ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'legacy',
        'name': 'Legacy',
        'template': 'v4',
        'route': '/legacy',
      }));
      registry.seal();
      final r = registry.resolved.first;
      expect(r.lattice, Lattice.staticWeb);
      expect(r.latticeExplicit, isFalse);
      // 旧 manifest toJson 不新增 lattice/runtime 键
      expect(r.descriptor.toJson().containsKey('lattice'), isFalse);
    });

    test('reloadModule 同步 _resolved', () {
      final registry = ModuleRegistry();
      registry.register(ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'm',
        'name': 'M',
        'route': '/m',
      }));
      registry.seal();
      registry.reloadModule(ModuleDescriptor.fromJson({
        'type': 'module',
        'id': 'm',
        'name': 'M2',
        'lattice': 'data-source',
        'dataSource': {'endpoint': 'orch://m'},
        'route': '/m',
      }));
      expect(registry.findByLattice(Lattice.dataSource).first.id, 'm');
    });
  });

  group('latticeToCapability 桥接 (M0-15)', () {
    test('映射正确', () {
      expect(latticeToCapability(Lattice.sidecar), CapabilityDimension.process);
      expect(latticeToCapability(Lattice.dataSource), CapabilityDimension.data);
      expect(latticeToCapability(Lattice.agentTool), CapabilityDimension.agent);
      expect(latticeToCapability(Lattice.webBridged), CapabilityDimension.module);
      expect(latticeToCapability(Lattice.staticWeb), CapabilityDimension.module);
      expect(latticeToCapability(Lattice.externalApp), isNull);
    });
  });
}

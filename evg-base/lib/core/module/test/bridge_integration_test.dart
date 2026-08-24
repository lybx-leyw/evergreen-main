/// BridgeInterceptor 端到端集成测试（M2-3 收尾）。
///
/// 验证真实调用链：ResolvedPlugin(sidecar, deny-all) → PermissionResolver
/// → BridgeInterceptor.intercept('platform.fs.read') 越权返回标准错误体；
/// 授权维度（module）放行返回 null，且审计记录被写入。
import 'package:test/test.dart';

import '../capability.dart';
import '../lattice.dart';
import '../module_descriptor.dart';
import '../resolved_plugin.dart';
import '../permission.dart';
import '../runtime.dart';

ResolvedPlugin _resolved(Map<String, dynamic> json) =>
    ResolvedPlugin.fromDescriptor(ModuleDescriptor.fromJson(json));

void main() {
  group('BridgeInterceptor 端到端（M2-3）', () {
    test('sidecar deny-all：未授权维度（agent）越权 → permission_denied', () {
      final plugin = _resolved({
        'type': 'module',
        'id': 'sc',
        'name': 'SC',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      });
      final resolver = PermissionResolver.fromResolved(plugin);
      final audit = PermissionAudit();
      final interceptor =
          BridgeInterceptor(resolver, audit: audit, subject: 'sc');

      // agent 维度未在 deny-all 的授予集中 → 拒绝，返回标准错误体。
      final err = interceptor.intercept(CapabilityDimension.agent,
          operation: 'platform.agent.invoke');
      expect(err, isNotNull);
      expect(err!['error'], 'permission_denied');
      expect(err['dimension'], 'agent');
      expect(err['operation'], 'platform.agent.invoke');

      // 审计：应记录一条被拒条目。
      expect(audit.denied, hasLength(1));
      expect(audit.entries.first.ticket.granted, isFalse);
    });

    test('已授权维度（process，sidecar 默认授予）放行 → null 且审计允许', () {
      final plugin = _resolved({
        'type': 'module',
        'id': 'sc',
        'name': 'SC',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      });
      final resolver = PermissionResolver.fromResolved(plugin);
      expect(resolver.allows(CapabilityDimension.process), isTrue);

      final audit = PermissionAudit();
      final interceptor =
          BridgeInterceptor(resolver, audit: audit, subject: 'sc');

      final err = interceptor.intercept(CapabilityDimension.process,
          operation: 'platform.process.spawn');
      expect(err, isNull); // 放行
      expect(audit.entries, hasLength(1));
      expect(audit.entries.first.ticket.granted, isTrue);
    });

    test('sidecar 带 net.allow → data 维度放行（能力只窄不宽）', () {
      final plugin = _resolved({
        'type': 'module',
        'id': 'sc2',
        'name': 'SC2',
        'lattice': 'sidecar',
        'runtime': {
          'kind': 'node',
          'entry': 's.js',
          'capabilities': {'net.allow': ['api.zju.edu.cn']},
        },
      });
      final resolver = PermissionResolver.fromResolved(plugin);
      expect(resolver.allows(CapabilityDimension.data), isTrue);

      final interceptor = BridgeInterceptor(resolver, subject: 'sc2');
      final err = interceptor.intercept(CapabilityDimension.data,
          operation: 'platform.net.get');
      expect(err, isNull); // data 已授权
    });
  });
}

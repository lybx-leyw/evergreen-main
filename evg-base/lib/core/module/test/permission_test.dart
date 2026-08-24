/// 权限执行器测试（M2-1/M2-2/M2-5）。
///
/// 覆盖 PermissionResolver 维度裁决、PermissionTicket 不可变、bridge 握手子集协商。
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
  group('PermissionResolver (M2-1)', () {
    test('static-web → 仅 module 维度', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'static-web',
      }));
      expect(r.allows(CapabilityDimension.module), isTrue);
      expect(r.allows(CapabilityDimension.agent), isFalse);
      expect(r.allows(CapabilityDimension.data), isFalse);
      expect(r.allows(CapabilityDimension.process), isFalse);
    });

    test('data-source → data 维度', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'data-source',
        'dataSource': {'endpoint': 'orch://x'},
      }));
      expect(r.allows(CapabilityDimension.data), isTrue);
      expect(r.allows(CapabilityDimension.agent), isFalse);
    });

    test('agent-tool → agent 维度', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'agent-tool',
        'activateSkills': ['x'],
      }));
      expect(r.allows(CapabilityDimension.agent), isTrue);
    });

    test('sidecar deny-all → 仅 process（不含额外 net/spawn）', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'sidecar',
        'runtime': {'kind': 'node', 'entry': 's.js'},
      }));
      expect(r.allows(CapabilityDimension.process), isTrue);
      // deny-all：net/spawn 全空 → 不再追加 data/process(重复)
      expect(r.allows(CapabilityDimension.data), isFalse);
    });

    test('sidecar + net.allow → 追加 data 维度', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'sidecar',
        'runtime': {
          'kind': 'node',
          'entry': 's.js',
          'capabilities': {'net.allow': ['api.zju.edu.cn']}
        },
      }));
      expect(r.allows(CapabilityDimension.process), isTrue);
      expect(r.allows(CapabilityDimension.data), isTrue);
    });

    test('sidecar + spawn → 追加 process（重复无副作用）', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'sidecar',
        'runtime': {
          'kind': 'node',
          'entry': 's.js',
          'capabilities': {'spawn': ['node']}
        },
      }));
      expect(r.allows(CapabilityDimension.process), isTrue);
    });

    test('resolve：已授权维度 → granted ticket', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'agent-tool',
        'activateSkills': ['x'],
      }));
      final t = r.resolve(PermissionRequest(CapabilityDimension.agent,
          operation: 'platform.api.call'));
      expect(t.granted, isTrue);
      expect(t.reason, isNull);
      expect(t.operation, 'platform.api.call');
    });

    test('resolve：未授权维度 → denied ticket + 标准错误体', () {
      final r = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'static-web',
      }));
      final t = r.resolve(PermissionRequest(CapabilityDimension.agent));
      expect(t.granted, isFalse);
      expect(t.reason, contains('agent'));
      final err = t.toErrorJson();
      expect(err['error'], 'permission_denied');
      expect(err['dimension'], 'agent');
    });
  });

  group('PermissionTicket (M2-2)', () {
    test('granted/denied 工厂字段正确', () {
      final g = PermissionTicket.granted(
        const PermissionRequest(CapabilityDimension.data),
        decidedAtMs: 1000,
      );
      expect(g.granted, isTrue);
      expect(g.decidedAtMs, 1000);

      final d = PermissionTicket.denied(
        const PermissionRequest(CapabilityDimension.agent),
        reason: 'no',
        decidedAtMs: 2000,
      );
      expect(d.granted, isFalse);
      expect(d.reason, 'no');
    });
  });

  group('BridgeHandshake (M2-5)', () {
    test('granted 是 wants 的子集（能力只窄不宽）', () {
      final hs = BridgeHandshake(
        bridgeVersion: 3,
        supported: {CapabilityDimension.module, CapabilityDimension.data},
      );
      final res = hs.hello(
        bridge: 3,
        wants: [
          CapabilityDimension.module,
          CapabilityDimension.agent, // 不在 supported → 被收窄
          CapabilityDimension.data,
        ],
      );
      expect(res.granted,
          containsAll([CapabilityDimension.module, CapabilityDimension.data]));
      expect(res.granted.contains(CapabilityDimension.agent), isFalse);
      expect(res.bridge, 3);
      expect(res.requestedBridge, 3);
    });

    test('toJson 输出 bridge + granted', () {
      final hs = BridgeHandshake(
        bridgeVersion: 2,
        supported: {CapabilityDimension.module},
      );
      final res = hs.hello(bridge: 2, wants: [CapabilityDimension.module]);
      expect(res.toJson(), {
        'bridge': 2,
        'granted': ['module'],
      });
    });
  });

  group('PermissionAudit (M2-4)', () {
    test('record 收集条目 + denied 过滤', () {
      final audit = PermissionAudit();
      final resolver = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'static-web',
      }));
      // module 放行
      audit.record(
        resolver.resolve(PermissionRequest(CapabilityDimension.module)),
        'a',
        'bridge',
      );
      // agent 拒绝
      audit.record(
        resolver.resolve(PermissionRequest(CapabilityDimension.agent)),
        'a',
        'bridge',
      );
      expect(audit.entries.length, 2);
      expect(audit.denied.length, 1);
      expect(audit.denied.first.ticket.dimension, CapabilityDimension.agent);
    });

    test('sink 回调触发（可接落盘）', () {
      final seen = <PermissionAuditEntry>[];
      final audit = PermissionAudit(sink: seen.add);
      final resolver = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'static-web',
      }));
      audit.record(
        resolver.resolve(PermissionRequest(CapabilityDimension.module)),
        'a',
        'bridge',
      );
      expect(seen.length, 1);
    });
  });

  group('BridgeInterceptor (M2-3)', () {
    test('授权维度 → 返回 null（放行）', () {
      final resolver = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'agent-tool',
        'activateSkills': ['x'],
      }));
      final interceptor = BridgeInterceptor(resolver, subject: 'a');
      expect(
        interceptor.intercept(CapabilityDimension.agent,
            operation: 'platform.api.call'),
        isNull,
      );
    });

    test('越权维度 → 返回标准错误体 + 写审计', () {
      final resolver = PermissionResolver.fromResolved(_resolved({
        'type': 'module',
        'id': 'a',
        'name': 'A',
        'lattice': 'static-web',
      }));
      final audit = PermissionAudit();
      final interceptor =
          BridgeInterceptor(resolver, audit: audit, subject: 'a');
      final err = interceptor.intercept(CapabilityDimension.agent);
      expect(err, isNotNull);
      expect(err!['error'], 'permission_denied');
      expect(audit.denied.length, 1);
    });
  });
}

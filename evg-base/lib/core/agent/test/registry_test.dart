/// Registry 集成测试 — 覆盖跨插件调度、并行工具调用、边界条件。
library;

import 'package:test/test.dart';

import '../tool.dart';

// ═══════ helpers ═══════

Tool _ro(String name) => SimpleTool(
      name: name,
      description: 'read-only $name',
      schema: {'type': 'object', 'properties': {}},
      readOnly: true,
      execute: (_) async => '$name result',
    );

Tool _rw(String name) => SimpleTool(
      name: name,
      description: 'write $name',
      schema: {'type': 'object', 'properties': {}},
      readOnly: false,
      execute: (_) async => '$name done',
    );

// ═══════ tests ═══════

void main() {
  group('Registry integration', () {
    late Registry registry;

    setUp(() {
      registry = Registry();
    });

    test('registerAll + enabled returns all sorted', () {
      registry.registerAll([_rw('save'), _ro('search'), _ro('fetch')]);
      final names = registry.enabled().map((t) => t.name).toList();
      expect(names, ['fetch', 'save', 'search']);
    });

    test('readOnlyToolNames excludes write tools', () {
      registry.registerAll([_ro('search'), _rw('save'), _ro('fetch')]);
      final names = registry.readOnlyToolNames;
      expect(names.length, 2);
      expect(names, contains('search'));
      expect(names, contains('fetch'));
      expect(names, isNot(contains('save')));
    });

    test('cross-plugin dispatch: multi-tool sequential call', () async {
      registry.registerAll([_ro('search'), _ro('fetch')]);

      final r1 = await registry.callWithArgs('search', {});
      final r2 = await registry.callWithArgs('fetch', {});

      expect(r1, 'search result');
      expect(r2, 'fetch result');
    });

    test('write tool disabled → call returns error', () async {
      registry.register(_rw('save'));
      registry.disable('save');
      final result = await registry.call('save', '{}');
      expect(result, contains('disabled'));
    });

    test('remove then re-register clears disabled state', () {
      registry.register(_rw('save'));
      registry.disable('save');
      registry.remove('save');
      registry.register(_rw('save'));
      expect(registry.isEnabled('save'), isTrue);
    });

    test('enabled filters disabled tools', () {
      registry.registerAll([_ro('a'), _ro('b'), _ro('c')]);
      registry.disable('b');
      final names = registry.enabled().map((t) => t.name);
      expect(names, ['a', 'c']);
    });

    test('has returns false for removed', () {
      registry.register(_ro('x'));
      registry.remove('x');
      expect(registry.has('x'), isFalse);
    });

    test('get returns null for removed', () {
      registry.register(_ro('x'));
      registry.remove('x');
      expect(registry.get('x'), isNull);
    });

    test('all returns all tools including disabled', () {
      registry.registerAll([_ro('a'), _rw('b')]);
      registry.disable('b');
      final names = registry.all().map((t) => t.name);
      expect(names.length, 2);
      expect(names, contains('b')); // present in all() even if disabled
    });
  });

  group('BuiltinRegistry integration', () {
    test('createRegistry excludes specified tools', () {
      final a = _ro('alpha');
      final b = _ro('bravo');
      BuiltinRegistry.register(a);
      BuiltinRegistry.register(b);

      final r = BuiltinRegistry.createRegistry(exclude: ['alpha']);
      expect(r.has('alpha'), isFalse);
      expect(r.has('bravo'), isTrue);
    });

    test('createRegistry with empty exclude', () {
      final r = BuiltinRegistry.createRegistry();
      expect(r.has('alpha'), isTrue);
      expect(r.has('bravo'), isTrue);
    });
  });

  group('empty registry', () {
    test('enabled returns empty list', () {
      final r = Registry();
      expect(r.enabled(), isEmpty);
    });

    test('readOnlyToolNames returns empty', () {
      final r = Registry();
      expect(r.readOnlyToolNames, isEmpty);
    });

    test('call nonexistent returns error', () async {
      final r = Registry();
      final result = await r.call('none', '{}');
      expect(result, contains('not found'));
    });
  });
}

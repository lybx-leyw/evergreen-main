/// Tool 接口、Registry、BuiltinRegistry 单元测试。
///
/// 覆盖：Tool/SimpleTool 接口、schema 转换、Registry 注册/启用/禁用/移除/调用/异常、
/// BuiltinRegistry 静态注册/createRegistry/排除。
library;

import 'package:test/test.dart';

import '../tool.dart';

// ═══════ helpers ═══════

Tool _echoTool() => SimpleTool(
      name: 'echo',
      description: '回声工具。',
      schema: {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '消息'},
        },
        'required': ['message'],
      },
      readOnly: true,
      execute: (args) async => 'echo: ${args['message']}',
    );

Tool _writeTool() => SimpleTool(
      name: 'save',
      description: '写文件。',
      schema: {'type': 'object', 'properties': {}},
      readOnly: false,
      execute: (_) async => 'saved',
    );

Tool _clockTool() => SimpleTool(
      name: 'clock',
      description: '返回时间。',
      schema: {'type': 'object', 'properties': {}},
      readOnly: true,
      execute: (_) async => '2026-01-01T00:00:00Z',
    );

// ═══════ Tool interface ═══════

void main() {
  group('Tool interface', () {
    test('name/description/schema/readOnly', () {
      final t = _echoTool();
      expect(t.name, 'echo');
      expect(t.description, contains('回声'));
      expect(t.schema['type'], 'object');
      expect(t.readOnly, isTrue);
    });

    test('SimpleTool execute returns result', () async {
      final result = await _echoTool().execute({'message': 'hi'});
      expect(result, 'echo: hi');
    });

    test('write tool readOnly=false', () {
      expect(_writeTool().readOnly, isFalse);
    });
  });

  // ═══════ toolToSchema / toolsToSchemas ═══════

  group('toolToSchema', () {
    test('produces OpenAI function schema', () {
      final s = toolToSchema(_echoTool());
      expect(s['type'], 'function');
      final f = s['function'] as Map<String, dynamic>;
      expect(f['name'], 'echo');
      expect(f['description'], isNotEmpty);
      expect(f['parameters']['required'], ['message']);
    });

    test('toolsToSchemas returns list', () {
      final schemas = toolsToSchemas([_echoTool(), _clockTool()]);
      expect(schemas.length, 2);
      expect(schemas[0]['function']['name'], 'echo');
    });
  });

  // ═══════ Registry ═══════

  group('Registry', () {
    late Registry registry;

    setUp(() {
      registry = Registry();
    });

    test('register adds tool', () {
      registry.register(_echoTool());
      expect(registry.has('echo'), isTrue);
      expect(registry.enabled().length, 1);
    });

    test('register duplicate throws', () {
      registry.register(_echoTool());
      expect(() => registry.register(_echoTool()), throwsArgumentError);
    });

    test('registerAll adds multiple', () {
      registry.registerAll([_echoTool(), _clockTool()]);
      expect(registry.enabled().length, 2);
    });

    test('remove deletes tool and clears disabled state', () {
      registry.register(_echoTool());
      registry.disable('echo');
      registry.remove('echo');
      expect(registry.has('echo'), isFalse);
      // re-register should succeed after remove
      registry.register(_echoTool());
      expect(registry.isEnabled('echo'), isTrue);
    });

    test('enable/disable toggles availability', () {
      registry.register(_echoTool());
      expect(registry.isEnabled('echo'), isTrue);

      registry.disable('echo');
      expect(registry.isEnabled('echo'), isFalse);
      expect(registry.has('echo'), isTrue); // still exists

      registry.enable('echo');
      expect(registry.isEnabled('echo'), isTrue);
    });

    test('enabled returns sorted', () {
      registry.register(_clockTool());
      registry.register(_echoTool());
      registry.register(_writeTool());
      final names = registry.enabled().map((t) => t.name).toList();
      expect(names, ['clock', 'echo', 'save']); // alphabetically sorted
    });

    test('get returns tool or null', () {
      expect(registry.get('nonexist'), isNull);
      registry.register(_echoTool());
      expect(registry.get('echo')!.name, 'echo');
    });

    test('call executes tool via json string', () async {
      registry.register(_echoTool());
      final result = await registry.call('echo', '{"message":"test"}');
      expect(result, 'echo: test');
    });

    test('call nonexistent returns error text not throw', () async {
      final result = await registry.call('nope', '{}');
      expect(result, contains('not found'));
    });

    test('call disabled tool returns error text', () async {
      registry.register(_echoTool());
      registry.disable('echo');
      final result = await registry.call('echo', '{"message":"x"}');
      expect(result, contains('disabled'));
    });

    test('callWithArgs executes with parsed map', () async {
      registry.register(_echoTool());
      final result = await registry.callWithArgs('echo', {'message': 'hi'});
      expect(result, 'echo: hi');
    });

    test('callWithArgs handles invalid json gracefully', () async {
      registry.register(_echoTool());
      final result = await registry.call('echo', 'not json');
      expect(result, contains('failed'));
    });

    test('readOnlyToolNames returns read-only tool names', () {
      registry.register(_echoTool()); // readOnly=true
      registry.register(_writeTool()); // readOnly=false
      final names = registry.readOnlyToolNames;
      expect(names, contains('echo'));
      expect(names, isNot(contains('save')));
    });
  });

  // ═══════ BuiltinRegistry ═══════

  group('BuiltinRegistry', () {
    test('register and all', () {
      BuiltinRegistry.register(_clockTool());
      final tools = BuiltinRegistry.all();
      expect(tools.any((t) => t.name == 'clock'), isTrue);
    });

    test('duplicate throws', () {
      expect(() => BuiltinRegistry.register(_clockTool()), throwsArgumentError);
    });

    test('get returns tool', () {
      expect(BuiltinRegistry.get('clock')!.name, 'clock');
      expect(BuiltinRegistry.get('nonexist'), isNull);
    });

    test('createRegistry creates runtime copy', () {
      final r = BuiltinRegistry.createRegistry();
      expect(r.has('clock'), isTrue);
    });

    test('createRegistry with exclude', () {
      final r = BuiltinRegistry.createRegistry(exclude: ['clock']);
      expect(r.has('clock'), isFalse);
    });
  });

  // ═══════ Previewer ═══════

  group('Previewer + ToolChange', () {
    test('ToolChange stores path/oldText/newText/binary', () {
      final c = ToolChange(
        path: '/tmp/test',
        oldText: '旧',
        newText: '新',
        binary: true,
      );
      expect(c.path, '/tmp/test');
      expect(c.oldText, '旧');
      expect(c.newText, '新');
      expect(c.binary, isTrue);
    });

    test('Previewer mixin preview before execute', () {
      final tool = _PreviewWriteTool();
      final change = (tool as Previewer).preview({'path': '/a', 'content': 'b'});
      expect(change!.path, '/a');
      expect(change.newText, 'b');
      expect(change.oldText, isNull);
    });
  });
}

// ═══════ _PreviewWriteTool ═══════

class _PreviewWriteTool extends Tool with Previewer {
  @override String get name => 'write';
  @override String get description => '写文件。';
  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
      };
  @override bool get readOnly => false;
  @override Future<String> execute(Map<String, dynamic> args) async => 'ok';

  @override
  ToolChange? preview(Map<String, dynamic> args) => ToolChange(
        path: args['path']?.toString() ?? '',
        newText: args['content']?.toString(),
      );
}

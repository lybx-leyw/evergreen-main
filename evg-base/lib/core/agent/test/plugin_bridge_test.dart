/// PluginBridge 测试 — 覆盖 discover/registerAll/refresh、PluginManifest 解析、ArgSpec。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tools/plugin_bridge.dart';
import '../tool.dart';

// ═══════ helpers ═══════

/// 创建临时插件目录结构：`tmp/plugins/<name>/agent/<name>.exe` + `manifest.json`。
Directory _createPluginDir(String base, String name, String manifestJson) {
  final agentDir = Directory('$base${Platform.pathSeparator}$name${Platform.pathSeparator}agent');
  agentDir.createSync(recursive: true);

  // 写入 manifest.json
  File('${agentDir.path}${Platform.pathSeparator}manifest.json')
      .writeAsStringSync(manifestJson);

  // 创建假的 .exe 文件（PluginBridge 只检查存在性，不会真正执行它）
  File('${agentDir.path}${Platform.pathSeparator}$name.exe')
      .writeAsStringSync('dummy exe');

  return agentDir.parent;
}

void main() {
  // ═══════ PluginManifest ═══════

  group('PluginManifest.fromJson', () {
    test('parses all fields', () {
      const json = '''
{
  "name": "weather",
  "description": "查询天气。",
  "schema": {"type": "object", "properties": {"city": {"type": "string"}}},
  "readOnly": true,
  "argMode": "args",
  "argSpec": {"style": "flag", "prefix": "--", "flags": {"city": "-c"}}
}''';
      final m = PluginManifest.fromJson(json);
      expect(m.name, 'weather');
      expect(m.description, '查询天气。');
      expect(m.readOnly, isTrue);
      expect(m.argMode, 'args');
      expect(m.argSpec.style, 'flag');
      expect(m.argSpec.flags['city'], '-c');
      expect(m.isValid, isTrue);
    });

    test('defaults: stdin mode, readOnly=false, json style', () {
      const json = '{"name": "test", "description": "test", "schema": {}}';
      final m = PluginManifest.fromJson(json);
      expect(m.argMode, 'stdin');
      expect(m.readOnly, isFalse);
      expect(m.argSpec.style, 'json');
    });

    test('empty name → isValid=false', () {
      const json = '{"name": "", "description": "", "schema": {}}';
      expect(PluginManifest.fromJson(json).isValid, isFalse);
    });

    test('missing argSpec → defaults', () {
      const json = '{"name": "t", "description": "d", "schema": {}, "argMode": "args"}';
      final m = PluginManifest.fromJson(json);
      expect(m.argSpec.style, 'json'); // default when no argSpec
    });
  });

  // ═══════ ArgSpec ═══════

  group('ArgSpec', () {
    test('default is json style', () {
      const spec = ArgSpec();
      expect(spec.style, 'json');
      expect(spec.prefix, '--');
    });

    test('fromJson with flag style', () {
      final spec = ArgSpec.fromJson({
        'style': 'flag',
        'prefix': '-',
        'flags': {'q': '-q'},
        'order': ['q', 'limit'],
      });
      expect(spec.style, 'flag');
      expect(spec.prefix, '-');
      expect(spec.flags['q'], '-q');
      expect(spec.order, ['q', 'limit']);
    });

    test('fromJson with null returns defaults', () {
      final spec = ArgSpec.fromJson(null);
      expect(spec.style, 'json');
    });

    test('positional with order', () {
      final spec = ArgSpec.fromJson({
        'style': 'positional',
        'order': ['a', 'b'],
      });
      expect(spec.style, 'positional');
      expect(spec.order.length, 2);
    });
  });

  // ═══════ PluginBridge ═══════

  group('PluginBridge', () {
    late String tmpBase;
    late Directory pluginsDir;

    setUp(() {
      tmpBase = '${Directory.systemTemp.path}${Platform.pathSeparator}agent_pb_test_${DateTime.now().millisecondsSinceEpoch}';
      pluginsDir = Directory(tmpBase);
      pluginsDir.createSync(recursive: true);
    });

    tearDown(() {
      if (Directory(tmpBase).existsSync()) {
        Directory(tmpBase).deleteSync(recursive: true);
      }
    });

    test('discover finds plugins with .exe + manifest.json', () {
      _createPluginDir(tmpBase, 'time', '''
{"name": "time", "description": "获取时间。", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools.length, 1);
      expect(tools.first.name, 'time');
      expect(tools.first, isA<PluginTool>());
    });

    test('discover skips dirs without .exe', () {
      // 创建只有 manifest 没有 exe 的目录
      final d = Directory('$tmpBase${Platform.pathSeparator}noexe${Platform.pathSeparator}agent');
      d.createSync(recursive: true);
      File('${d.path}${Platform.pathSeparator}manifest.json').writeAsStringSync(
        '{"name":"noexe","description":"","schema":{}}',
      );

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools, isEmpty);
    });

    test('discover skips invalid manifests', () {
      _createPluginDir(tmpBase, 'bad', '''
{"name": "", "description": "", "schema": {}}''');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools, isEmpty);
    });

    test('registerAll registers discovered tools', () {
      _createPluginDir(tmpBase, 'time', '''
{"name": "time", "description": "time tool", "schema": {"type":"object","properties":{}}, "readOnly": true}''');
      _createPluginDir(tmpBase, 'date', '''
{"name": "date", "description": "date tool", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      final registry = Registry();
      PluginBridge.registerAll(registry, pluginsDir);
      expect(registry.enabled().length, 2);
      expect(registry.has('time'), isTrue);
      expect(registry.has('date'), isTrue);
    });

    test('registerAll skips already registered', () {
      _createPluginDir(tmpBase, 'time', '''
{"name": "time", "description": "time", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      final registry = Registry();
      PluginBridge.registerAll(registry, pluginsDir);
      expect(registry.enabled().length, 1);

      // 第二次调用不新增
      PluginBridge.registerAll(registry, pluginsDir);
      expect(registry.enabled().length, 1);
    });

    test('refresh adds new and removes deleted', () {
      _createPluginDir(tmpBase, 'time', '''
{"name": "time", "description": "time", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      final registry = Registry();
      PluginBridge.registerAll(registry, pluginsDir);
      expect(registry.has('time'), isTrue);

      // 删除 time 插件目录，新增 date
      Directory('$tmpBase${Platform.pathSeparator}time').deleteSync(recursive: true);
      _createPluginDir(tmpBase, 'date', '''
{"name": "date", "description": "date", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      PluginBridge.refresh(registry, pluginsDir);
      expect(registry.has('time'), isFalse); // removed
      expect(registry.has('date'), isTrue); // added
    });

    test('refresh does not remove non-PluginTool tools', () {
      _createPluginDir(tmpBase, 'time', '''
{"name": "time", "description": "time", "schema": {"type":"object","properties":{}}, "readOnly": true}''');

      final registry = Registry();
      // 手动注册一个非 PluginTool 的工具
      registry.register(SimpleTool(
        name: 'builtin',
        description: 'builtin',
        schema: {'type': 'object', 'properties': {}},
        execute: (_) async => 'ok',
      ));
      PluginBridge.registerAll(registry, pluginsDir);

      PluginBridge.refresh(registry, pluginsDir);
      expect(registry.has('builtin'), isTrue); // non-PluginTool preserved
      expect(registry.has('time'), isTrue);
    });

    test('discover returns empty for non-existent dir', () {
      final tools = PluginBridge.discover(
        Directory('$tmpBase${Platform.pathSeparator}nonexistent'),
      );
      expect(tools, isEmpty);
    });
  });

  // ═══════ PluginTool ═══════

  group('PluginTool', () {
    test('properties from manifest', () {
      final m = PluginManifest.fromJson(
        '{"name":"test","description":"desc","schema":{"type":"object","properties":{}},"readOnly":true}',
      );
      final pt = PluginTool(exePath: '/fake/test.exe', manifest: m);
      expect(pt.name, 'test');
      expect(pt.description, 'desc');
      expect(pt.readOnly, isTrue);
    });

    test('schema is forwarded from manifest', () {
      final m = PluginManifest.fromJson(
        '{"name":"t","description":"d","schema":{"type":"object","properties":{"x":{"type":"string"}}},"readOnly":false}',
      );
      final pt = PluginTool(exePath: '/fake/t.exe', manifest: m);
      final props = pt.schema['properties'] as Map<String, dynamic>;
      expect(props.containsKey('x'), isTrue);
    });
  });
}

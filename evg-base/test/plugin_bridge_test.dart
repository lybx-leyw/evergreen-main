/// PluginBridge discover 测试 —— 验证 11 个新增插件可发现、可执行。
import 'dart:io';

import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:path/path.dart' as p;

void main() async {
  // ── 找项目根 ──
  final testDir = Directory.current.path;
  String projectRoot = testDir;
  var dir = Directory(testDir);
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      projectRoot = dir.path;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  final pluginsDir = Directory(p.join(projectRoot, 'plugins'));
  stderr.writeln('[test] pluginBridge discover: ${pluginsDir.path}');

  if (!pluginsDir.existsSync()) {
    stderr.writeln('[test] FAIL: plugins/ directory does not exist');
    exit(1);
  }

  final tools = PluginBridge.discover(pluginsDir);
  stderr.writeln('[test] discovered ${tools.length} tools');

  final names = tools.map((t) => t.name).toList();
  names.sort();
  stderr.writeln('[test] tool names: $names');

  // ── 预期 11 个新增 + 可能有已存在的 ──
  const expected = [
    'base64',
    'calculator',
    'color_convert',
    'json_format',
    'password_gen',
    'qr_text',
    'text_utils',
    'unit_convert',
    'url_encode',
    'uuid_gen',
    'word_count',
  ];

  final missing = <String>[];
  for (final name in expected) {
    if (!names.contains(name)) {
      missing.add(name);
    }
  }

  if (missing.isNotEmpty) {
    stderr.writeln('[test] FAIL: missing tools: $missing');
    exit(1);
  }

  // ── 执行一个工具验证通路 ──
  final registry = Registry();
  for (final t in tools) {
    registry.register(t);
  }

  // Test calculator (stdin)
  stderr.writeln('[test] running calculator...');
  final calcResult = await registry.callWithArgs('calculator', {
    'operation': 'add',
    'a': 10,
    'b': 20,
  });
  stderr.writeln('[test] calculator result: $calcResult');
  if (!calcResult.contains('30')) {
    stderr.writeln('[test] FAIL: calculator expected 30 but got: $calcResult');
    exit(1);
  }

  // Test text_utils (flag args)
  stderr.writeln('[test] running text_utils...');
  final textResult = await registry.callWithArgs('text_utils', {
    'text': 'Hello World',
    'operation': 'count',
  });
  stderr.writeln('[test] text_utils result: $textResult');
  if (!textResult.contains('字符数')) {
    stderr.writeln('[test] FAIL: text_utils did not return expected output');
    exit(1);
  }

  // Test uuid_gen (positional args)
  stderr.writeln('[test] running uuid_gen...');
  final uuidResult = await registry.callWithArgs('uuid_gen', {
    'version': 4,
    'count': 2,
  });
  stderr.writeln('[test] uuid_gen result: $uuidResult');
  if (!uuidResult.contains('-')) {
    stderr.writeln('[test] FAIL: uuid_gen did not return UUID');
    exit(1);
  }

  // Test color_convert (domain logic)
  stderr.writeln('[test] running color_convert...');
  final colorResult = await registry.callWithArgs('color_convert', {
    'color': '#ff5733',
    'target': 'all',
  });
  stderr.writeln('[test] color_convert result: $colorResult');
  if (!colorResult.contains('rgb(255')) {
    stderr.writeln('[test] FAIL: color_convert did not return RGB');
    exit(1);
  }

  stderr.writeln('[test] ALL TESTS PASSED ✓');
  exit(0);
}

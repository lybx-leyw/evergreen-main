/// PluginBridge discover 测试 —— 验证 11 个插件可发现、可执行。
///
/// 前置条件：plugins/*/agent/ 下需要有编译好的 .exe 文件。
/// 如果 .exe 不存在，测试会跳过（skip）而非失败。
library;
import 'dart:io';

import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/agent/tools/plugin_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late String projectRoot;
  late Directory pluginsDir;

  setUpAll(() {
    // ── 找项目根 ──
    final testDir = Directory.current.path;
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

    pluginsDir = Directory(p.join(projectRoot, 'plugins'));
  });

  test('discover 不抛异常且可执行', () async {
    stderr.writeln('[test] pluginBridge discover: ${pluginsDir.path}');

    if (!pluginsDir.existsSync()) {
      stderr.writeln('[test] SKIP: plugins/ directory does not exist');
      return;
    }

    final tools = PluginBridge.discover(pluginsDir);
    stderr.writeln('[test] discovered ${tools.length} tools');

    final names = tools.map((t) => t.name).toList();
    names.sort();
    stderr.writeln('[test] tool names: $names');

    if (tools.isEmpty) {
      stderr.writeln('[test] SKIP: no compiled .exe plugins found (run build first)');
      return;
    }

    // ── 预期 11 个插件 ──
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
      fail('missing tools: $missing');
    }

    // ── 执行工具验证通路 ──
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
    expect(calcResult, contains('30'));

    // Test text_utils (flag args)
    stderr.writeln('[test] running text_utils...');
    final textResult = await registry.callWithArgs('text_utils', {
      'text': 'Hello World',
      'operation': 'count',
    });
    stderr.writeln('[test] text_utils result: $textResult');
    expect(textResult, contains('字符数'));

    // Test uuid_gen (positional args)
    stderr.writeln('[test] running uuid_gen...');
    final uuidResult = await registry.callWithArgs('uuid_gen', {
      'version': 4,
      'count': 2,
    });
    stderr.writeln('[test] uuid_gen result: $uuidResult');
    expect(uuidResult, contains('-'));

    // Test color_convert (domain logic)
    stderr.writeln('[test] running color_convert...');
    final colorResult = await registry.callWithArgs('color_convert', {
      'color': '#ff5733',
      'target': 'all',
    });
    stderr.writeln('[test] color_convert result: $colorResult');
    expect(colorResult, contains('rgb(255'));

    stderr.writeln('[test] ALL TESTS PASSED ✓');
  });
}

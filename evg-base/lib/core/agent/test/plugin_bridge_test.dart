/// PluginBridge 测试 — 覆盖 discover/registerAll/refresh、PluginManifest 解析、ArgSpec。
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';

import '../tools/plugin_bridge.dart';
import '../tools/agent_process_registry.dart';
import '../tool.dart';

// ═══════ helpers ═══════

/// 创建临时插件目录结构：`tmp/plugins/<name>/agent/<name>.exe` + `manifest.json`。
Directory _createPluginDir(String base, String name, String manifestJson) {
  final agentDir = Directory(
      '$base${Platform.pathSeparator}$name${Platform.pathSeparator}agent');
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
      const json =
          '{"name": "t", "description": "d", "schema": {}, "argMode": "args"}';
      final m = PluginManifest.fromJson(json);
      expect(m.argSpec.style, 'json'); // default when no argSpec
    });

    // ═══════ vision 插件 manifest（Task R3-5） ═══════

    test('vision manifest：多 mode stdin 工具解析合法', () {
      const json = '''
{
  "name": "vision",
  "description": "多模态视觉工具",
  "schema": {
    "type": "object",
    "properties": {
      "mode": {"type": "string", "enum": ["ocr", "describe", "generate"]},
      "file_path": {"type": "string"}
    },
    "required": []
  },
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once"
}''';
      final m = PluginManifest.fromJson(json);
      expect(m.name, 'vision');
      expect(m.argMode, 'stdin');
      expect(m.runtime, 'python');
      expect(m.lifetime, 'once');
      expect(m.readOnly, isTrue);
      expect(m.isValid, isTrue);
      // mode enum 透出（供 LLM schema 展示）
      final mode = m.schema['properties']['mode'] as Map<String, dynamic>;
      expect(mode['enum'], ['ocr', 'describe', 'generate']);
    });

    // ═══════ lifetime（Task 三决策 3.1） ═══════

    test('lifetime 缺省 → once（向后兼容：旧插件无字段行为不变）', () {
      const json = '{"name": "t", "description": "d", "schema": {}}';
      expect(PluginManifest.fromJson(json).lifetime, 'once');
    });

    test('lifetime "once" 显式声明 → once', () {
      const json =
          '{"name": "t", "description": "d", "schema": {}, "lifetime": "once"}';
      expect(PluginManifest.fromJson(json).lifetime, 'once');
    });

    test('lifetime "resident" 显式声明 → resident', () {
      const json =
          '{"name": "t", "description": "d", "schema": {}, "lifetime": "resident"}';
      expect(PluginManifest.fromJson(json).lifetime, 'resident');
    });

    test('lifetime 未知值 → 静默回退 once（项目铁律「未知静默忽略」）', () {
      const json =
          '{"name": "t", "description": "d", "schema": {}, "lifetime": "forever"}';
      expect(PluginManifest.fromJson(json).lifetime, 'once');
    });

    test('lifetime 非字符串（如数字）→ 静默回退 once', () {
      const json =
          '{"name": "t", "description": "d", "schema": {}, "lifetime": 123}';
      expect(PluginManifest.fromJson(json).lifetime, 'once');
    });

    // ═══════ preprocess（Task R3-6） ═══════

    test('preprocess "pdf_split" 解析（vision 插件声明）', () {
      const json =
          '{"name":"vision","description":"d","schema":{},"preprocess":"pdf_split"}';
      expect(PluginManifest.fromJson(json).preprocess, 'pdf_split');
    });

    test('preprocess 缺省 → ""（旧插件无字段行为不变，不预处理）', () {
      expect(
        PluginManifest.fromJson('{"name":"t","description":"d","schema":{}}')
            .preprocess,
        '',
      );
    });

    test('preprocess 未知值原样保留（仅 pdf_split 触发预处理，其余不处理）', () {
      expect(
        PluginManifest.fromJson(
                '{"name":"t","description":"d","schema":{},"preprocess":"other"}')
            .preprocess,
        'other',
      );
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
      tmpBase =
          '${Directory.systemTemp.path}${Platform.pathSeparator}agent_pb_test_${DateTime.now().millisecondsSinceEpoch}';
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
      final d = Directory(
          '$tmpBase${Platform.pathSeparator}noexe${Platform.pathSeparator}agent');
      d.createSync(recursive: true);
      File('${d.path}${Platform.pathSeparator}manifest.json').writeAsStringSync(
        '{"name":"noexe","description":"","schema":{}}',
      );

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools, isEmpty);
    });

    test('.py preferred over .exe when both present（统一 python 路径）', () {
      // 目录同时含 <name>.py 与 <name>.exe → 选 .py（即使 .exe 同名）
      final agentDir = Directory(
          '$tmpBase${Platform.pathSeparator}dual${Platform.pathSeparator}agent');
      agentDir.createSync(recursive: true);
      File('${agentDir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync(
        '{"name":"dual","description":"","schema":{},"runtime":"python"}',
      );
      File('${agentDir.path}${Platform.pathSeparator}dual.py')
          .writeAsStringSync('print(1)');
      File('${agentDir.path}${Platform.pathSeparator}dual.exe')
          .writeAsStringSync('dummy');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools.length, 1);
      final pt = tools.first as PluginTool;
      expect(pt.name, 'dual');
      expect(pt.entryPath, endsWith('.py'));
    });

    test('.py-only plugin discovered（无 .exe）', () {
      final agentDir = Directory(
          '$tmpBase${Platform.pathSeparator}pyonly${Platform.pathSeparator}agent');
      agentDir.createSync(recursive: true);
      File('${agentDir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync(
        '{"name":"pyonly","description":"","schema":{},"runtime":"python"}',
      );
      File('${agentDir.path}${Platform.pathSeparator}pyonly.py')
          .writeAsStringSync('print(1)');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools.length, 1);
      expect((tools.first as PluginTool).entryPath, endsWith('.py'));
    });

    test('runtime:"python" + only .exe → 跳过（声明错配不误跑）', () {
      final agentDir = Directory(
          '$tmpBase${Platform.pathSeparator}mis${Platform.pathSeparator}agent');
      agentDir.createSync(recursive: true);
      File('${agentDir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync(
        '{"name":"mis","description":"","schema":{},"runtime":"python"}',
      );
      File('${agentDir.path}${Platform.pathSeparator}mis.exe')
          .writeAsStringSync('dummy');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools, isEmpty);
    });

    test('legacy .exe fallback：无 .py 且 runtime 缺省/native → 仍发现', () {
      // 与 _createPluginDir 相同形态：只有 <name>.exe，runtime 缺省 → legacy 回退
      final agentDir = Directory(
          '$tmpBase${Platform.pathSeparator}legacy${Platform.pathSeparator}agent');
      agentDir.createSync(recursive: true);
      File('${agentDir.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync(
        '{"name":"legacy","description":"","schema":{}}',
      );
      File('${agentDir.path}${Platform.pathSeparator}legacy.exe')
          .writeAsStringSync('dummy');

      final tools = PluginBridge.discover(pluginsDir);
      expect(tools.length, 1);
      expect((tools.first as PluginTool).entryPath, endsWith('.exe'));
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
      Directory('$tmpBase${Platform.pathSeparator}time')
          .deleteSync(recursive: true);
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

    test('platformArgs 注入：stdin 模式 argv 透传 --project-root / --greenix-config'
        '（安卓 vision 配置读取机制）', () async {
      // 真实 python 子进程回显 sys.argv：验证 platformArgs 在 stdin 模式也进入 argv
      // （Kotlin 侧从 argv 提取后设置 Python 环境变量）。
      final py = Platform.isWindows ? 'python' : 'python3';
      final scriptPath = '${Directory.systemTemp.path}'
          '${Platform.pathSeparator}argv_echo_test.py';
      File(scriptPath).writeAsStringSync(
        'import sys, json\n'
        'print("ARGS=" + json.dumps(sys.argv[1:]))\n',
      );

      final m = PluginManifest.fromJson('''
{
  "name": "argv_echo",
  "description": "e",
  "schema": {"type": "object", "properties": {"q": {"type": "string"}}},
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once"
}''');
      final pt = PluginTool(
        exePath: scriptPath,
        manifest: m,
        runner: SubprocessRunner(py),
        platformArgs: const [
          '--project-root', '/data/evergreen',
          '--greenix-config', '/data/evergreen/.greenix/config.json',
        ],
      );
      final res = await pt.execute({'q': 'x'});
      expect(res, contains('--project-root'));
      expect(res, contains('/data/evergreen'));
      expect(res, contains('--greenix-config'));
      expect(res, contains('/data/evergreen/.greenix/config.json'));
      File(scriptPath).deleteSync();
    });

    test('platformArgs 缺省为空：stdin 模式 argv 不含平台参数（桌面零行为变化）',
        () async {
      final py = Platform.isWindows ? 'python' : 'python3';
      final scriptPath = '${Directory.systemTemp.path}'
          '${Platform.pathSeparator}argv_echo_default_test.py';
      File(scriptPath).writeAsStringSync(
        'import sys, json\n'
        'print("ARGS=" + json.dumps(sys.argv[1:]))\n',
      );

      final m = PluginManifest.fromJson('''
{
  "name": "argv_echo2",
  "description": "e",
  "schema": {"type": "object", "properties": {}},
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once"
}''');
      final pt = PluginTool(
        exePath: scriptPath,
        manifest: m,
        runner: SubprocessRunner(py),
      );
      final res = await pt.execute({});
      expect(res, contains('ARGS=[]'));
      File(scriptPath).deleteSync();
    });

    test('preprocess=pdf_split：非安卓（测试环境）原参透传——fail-open，'
        '桌面零行为变化', () async {
      // 真实 python 子进程回显 stdin JSON：验证预拆分钩子未改动参数
      // （测试环境 Platform.isAndroid=false → trySplitPdf 返回 null）。
      final py = Platform.isWindows ? 'python' : 'python3';
      final scriptPath = '${Directory.systemTemp.path}'
          '${Platform.pathSeparator}vision_echo_pdf_test.py';
      File(scriptPath).writeAsStringSync(
        'import sys, json\n'
        'd = json.loads(sys.stdin.read())\n'
        'print(json.dumps(d, ensure_ascii=False))\n',
      );

      final m = PluginManifest.fromJson('''
{
  "name": "vision",
  "description": "v",
  "schema": {"type": "object", "properties": {"mode": {"type": "string"}, "file_path": {"type": "string"}}},
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "once",
  "preprocess": "pdf_split"
}''');
      final pt = PluginTool(
        exePath: scriptPath,
        manifest: m,
        runner: SubprocessRunner(py),
      );
      final res =
          await pt.execute({'mode': 'ocr', 'file_path': '/tmp/doc.pdf'});
      expect(res, contains('"mode"'));
      expect(res, contains('"file_path"'));
      expect(res, contains('/tmp/doc.pdf'));
      expect(res, isNot(contains('pages_dir'))); // 未注入 pages_dir
      File(scriptPath).deleteSync();
    });

    test('schema is forwarded from manifest', () {
      final m = PluginManifest.fromJson(
        '{"name":"t","description":"d","schema":{"type":"object","properties":{"x":{"type":"string"}}},"readOnly":false}',
      );
      final pt = PluginTool(exePath: '/fake/t.exe', manifest: m);
      final props = pt.schema['properties'] as Map<String, dynamic>;
      expect(props.containsKey('x'), isTrue);
    });

    test('lifetime 缺省/once → execute 走一次性路径（占位结果不出现）', () async {
      // 用不会真正运行的 exe 路径 + once manifest：若走了 runOnce，启动会失败
      // 并返回 error 文本；绝不出现「后台已启动」占位。
      final m = PluginManifest.fromJson(
        '{"name":"t","description":"d","schema":{}}',
      );
      expect(m.lifetime, 'once');
      final pt = PluginTool(exePath: '/fake/never_run.exe', manifest: m);
      final res = await pt.execute({});
      expect(res, isNot(contains('后台已启动')));
    });

    test('lifetime resident → execute 后台启动占位 + 登记注册表 + 输出回填', () async {
      // 真实 python 子进程（读 stdin JSON 后挂起模拟常驻）。
      final py = Platform.isWindows ? 'python' : 'python3';
      final scriptPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}resident_plugin_test.py';
      File(scriptPath).writeAsStringSync(
        'import sys, time\n'
        "data = sys.stdin.read()\n"
        "print('got:' + data.strip(), flush=True)\n"
        'time.sleep(5)\n',
      );

      final m = PluginManifest.fromJson('''
{
  "name": "current_time_res",
  "description": "常驻时间工具（测试）",
  "schema": {"type": "object", "properties": {"tz": {"type": "integer"}}},
  "readOnly": true,
  "runtime": "python",
  "argMode": "stdin",
  "lifetime": "resident"
}''');
      expect(m.lifetime, 'resident');

      // 注入显式 runner（python 解释器），不依赖 sharedPluginRunner 探测。
      final pt = PluginTool(
        exePath: scriptPath,
        manifest: m,
        runner: SubprocessRunner(py),
      );

      final res = await pt.execute({'tz': 8});
      expect(res, contains('后台已启动'));
      expect(res, contains('current_time_res'));

      // 已登记到全局注册表，输出自动累积回填。
      expect(agentProcessRegistry.isRunning('current_time_res'), isTrue);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var out = '';
      while (DateTime.now().isBefore(deadline) && !out.contains('got:')) {
        out = await agentProcessRegistry.readOutput('current_time_res');
        await Future.delayed(const Duration(milliseconds: 50));
      }
      expect(out, contains('got:'));
      expect(out, contains('tz'));

      // 幂等：再次调用不重复启动。
      final again = await pt.execute({'tz': 9});
      expect(again, contains('后台已运行'));

      // 清理：结束常驻进程，避免残留。
      await agentProcessRegistry.disposeAll();
      expect(agentProcessRegistry.isRunning('current_time_res'), isFalse);
      File(scriptPath).deleteSync();
    });
  });
}

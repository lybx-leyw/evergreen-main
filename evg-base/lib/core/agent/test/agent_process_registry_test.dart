/// AgentProcessRegistry 测试 — 覆盖 startResident 幂等 / activeNames / count /
/// readOutput 累积 / kill 移除 / disposeAll 清空，以及内置工具
/// list_processes / kill_process 的注册表接线。
///
/// 子进程用 `python3`（Windows 回退 `python`）跑短命脚本，不依赖 Dart VM
/// 子进程（内存友好）；脚本打印若干行后挂起（模拟常驻），所有
/// kill/disposeAll 在用例结束前完成，不留孤儿进程。
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tools/agent_process_registry.dart';
import '../tools/agent_process_tools.dart';

// ═══════ helpers ═══════

late String _tmpBase;

/// 当前平台的 python 命令（linux/macOS 优先 python3，Windows 回退 python）。
List<String> get _pythonCmd => Platform.isWindows ? ['python'] : ['python3'];

/// 写一个 python 脚本：先逐行 print（模拟启动输出），随后挂起 5s（模拟常驻）。
String _writeResidentScript(String name, List<String> lines) {
  final buf = StringBuffer()
    ..writeln('import time')
    ..writeln('import sys');
  for (final l in lines) {
    buf.writeln("print('$l', flush=True)");
  }
  buf.writeln('time.sleep(5)');
  buf.writeln('sys.exit(0)');
  final f = File('$_tmpBase${Platform.pathSeparator}$name.py');
  f.writeAsStringSync(buf.toString());
  return f.path;
}

/// 启动 [registry] 下名为 [name] 的常驻脚本进程。
Future<void> _startScript(
    AgentProcessRegistry registry, String name, List<String> lines) {
  return registry.startResident(
    name,
    [..._pythonCmd, _writeResidentScript(name, lines)],
  );
}

/// 轮询 readOutput 直到非空（最多 [timeout]）。
Future<String> _waitOutput(AgentProcessRegistry registry, String name,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final out = await registry.readOutput(name);
    if (out.isNotEmpty) return out;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return registry.readOutput(name);
}

/// 轮询直到输出包含 [needle]（最多 [timeout]）。
Future<bool> _waitContains(
    AgentProcessRegistry registry, String name, String needle,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final out = await registry.readOutput(name);
    if (out.contains(needle)) return true;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

void main() {
  late AgentProcessRegistry reg;

  setUp(() {
    _tmpBase =
        '${Directory.systemTemp.path}${Platform.pathSeparator}agent_proc_test_${DateTime.now().millisecondsSinceEpoch}';
    Directory(_tmpBase).createSync(recursive: true);
    reg = AgentProcessRegistry();
  });

  tearDown(() async {
    // 兜底清理：不残留任何常驻子进程。
    await reg.disposeAll();
    if (Directory(_tmpBase).existsSync()) {
      Directory(_tmpBase).deleteSync(recursive: true);
    }
  });

  group('AgentProcessRegistry', () {
    test('startResident 幂等：同 key 已在运行则复用，不重复启动', () async {
      await _startScript(reg, 'k', ['first-run']);
      expect(await _waitOutput(reg, 'k'), contains('first-run'));
      expect(reg.isRunning('k'), isTrue);
      expect(reg.count, 1);

      // 同 key 再次启动（不同脚本内容）→ 复用原进程，不覆盖
      await _startScript(reg, 'k', ['second-run']);
      expect(reg.count, 1);
      expect(await reg.readOutput('k'), contains('first-run'));
      expect(await reg.readOutput('k'), isNot(contains('second-run')));
    });

    test('activeNames / count 反映运行中进程', () async {
      expect(reg.count, 0);
      expect(reg.activeNames(), isEmpty);

      await _startScript(reg, 'a', ['a-out']);
      await _startScript(reg, 'b', ['b-out']);
      await _waitOutput(reg, 'a');
      await _waitOutput(reg, 'b');

      expect(reg.count, 2);
      expect(reg.activeNames().toSet(), {'a', 'b'});
      expect(reg.isRunning('a'), isTrue);
      expect(reg.isRunning('missing'), isFalse);
    });

    test('readOutput 累积：多行输出按行追加', () async {
      final script = StringBuffer()
        ..writeln('import time')
        ..writeln("print('line1', flush=True)")
        ..writeln('time.sleep(0.3)')
        ..writeln("print('line2', flush=True)")
        ..writeln('time.sleep(5)');
      final scriptPath = '$_tmpBase${Platform.pathSeparator}acc.py';
      File(scriptPath).writeAsStringSync(script.toString());
      await reg.startResident('acc', [..._pythonCmd, scriptPath]);

      expect(await _waitContains(reg, 'acc', 'line1'), isTrue);
      expect(await _waitContains(reg, 'acc', 'line2'), isTrue);
      final out = await reg.readOutput('acc');
      expect(out, contains('line1'));
      expect(out, contains('line2'));
    });

    test('readOutput 未登记 key 返回空串', () async {
      expect(await reg.readOutput('nope'), '');
    });

    test('kill 后从 map 移除', () async {
      await _startScript(reg, 'k', ['hello']);
      await _waitOutput(reg, 'k');
      expect(reg.isRunning('k'), isTrue);

      final res = await reg.kill('k');
      expect(res, isNotEmpty);
      expect(reg.entry('k'), isNull); // 已从注册表移除
      expect(reg.activeNames(), isEmpty);
      expect(reg.count, 0);
    });

    test('kill 未登记 key 返回说明文本（不抛异常）', () async {
      final res = await reg.kill('ghost');
      expect(res, contains('ghost'));
    });

    test('disposeAll 清空全部条目并终止进程', () async {
      await _startScript(reg, 'a', ['a-out']);
      await _startScript(reg, 'b', ['b-out']);
      await _waitOutput(reg, 'a');
      await _waitOutput(reg, 'b');
      expect(reg.count, 2);

      await reg.disposeAll();
      expect(reg.count, 0);
      expect(reg.activeNames(), isEmpty);
      expect(reg.entries, isEmpty);
    });

    test('attach 登记外部已启动进程（PluginTool 常驻路径同构）', () async {
      final scriptPath = _writeResidentScript('ext', ['attached-out']);
      final proc = await Process.start(_pythonCmd[0], [scriptPath]);
      reg.attach('ext', proc);
      expect(reg.isRunning('ext'), isTrue);
      expect(await _waitContains(reg, 'ext', 'attached-out'), isTrue);
      await reg.kill('ext');
      expect(reg.entry('ext'), isNull);
    });
  });

  group('ListProcessesTool / KillProcessTool（经注册表操作）', () {
    test('list_processes：空注册表提示、有进程时列名称/状态/输出摘要', () async {
      final tool = ListProcessesTool(registry: reg);
      final empty = await tool.execute({});
      expect(empty, contains('没有后台常驻'));

      await _startScript(reg, 'watcher', ['watch-out']);
      await _waitContains(reg, 'watcher', 'watch-out');
      final out = await tool.execute({});
      expect(out, contains('watcher'));
      expect(out, contains('运行中'));
      expect(out, contains('watch-out'));
    });

    test('kill_process：name 必填校验 + 正常 kill', () async {
      final tool = KillProcessTool(registry: reg);
      final missing = await tool.execute({});
      expect(missing, contains('name 必填'));

      await _startScript(reg, 'victim', ['bye']);
      await _waitOutput(reg, 'victim');
      final res = await tool.execute({'name': 'victim'});
      expect(res, isNotEmpty);
      expect(reg.entry('victim'), isNull);
      expect(reg.count, 0);
    });
  });
}

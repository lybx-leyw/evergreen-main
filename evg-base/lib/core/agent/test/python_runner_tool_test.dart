/// PythonRunnerTool 测试——安卓双路径（Chaquopy）+ 桌面零变化回归（R3-3）。
///
/// 覆盖：
/// - run 模式安卓（forceAndroid: true）：code 落临时 .py 并传 entry/args/
///   workingDirectory/timeout，输出格式化（成功 → stdout 合并 stderr；
///   exitCode!=0 → `[Python exited with code N]` + stderr + stdout），
///   临时文件 finally 删除
/// - pip 模式安卓：返回构建期提示文案（不触 runner）
/// - 危险代码拦截不变（安卓同样不触 runner）
/// - sys 模式安卓：复用 Chaquopy 执行路径（sys 信息脚本落临时文件）
/// - forceAndroid: false：桌面路径不触 runner（Process.start 失败 → 可读错误）
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:evergreen_base/core/plugin/plugin_runner.dart';

import '../tools/python_runner_tool.dart';

// ═══════ fake runner ═══════

/// 记录 runOnce 调用并返回可配置结果的假 PluginRunner。
class FakePluginRunner implements PluginRunner {
  final List<({String entry, List<String> args, String? workingDirectory, Duration? timeout})>
      calls = [];

  RunResult result = const RunResult('', '', 0);

  /// runOnce 执行时捕获的入口文件内容（临时文件随后被工具 finally 删除）。
  String? lastEntryContent;

  @override
  Future<RunResult> runOnce(
    String entry,
    List<String> args, {
    Map<String, dynamic>? stdinJson,
    String? workingDirectory,
    String? runtime,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    calls.add((
      entry: entry,
      args: List.of(args),
      workingDirectory: workingDirectory,
      timeout: timeout,
    ));
    try {
      lastEntryContent = File(entry).readAsStringSync();
    } catch (_) {
      lastEntryContent = null;
    }
    return result;
  }

  @override
  Future<Process> startLong(
    String entry,
    List<String> args, {
    String? workingDirectory,
    int preferredPort = 0,
    String? runtime,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  late Directory tmp;
  late Directory ws;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('py_runner_test_');
    ws = Directory(p.join(tmp.path, 'ws'))..createSync(recursive: true);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  PythonRunnerTool buildTool(FakePluginRunner fake, {bool forceAndroid = true}) {
    return PythonRunnerTool(
      pythonExePath: 'chaquopy',
      pythonWorkDir: tmp.path,
      workspaceDir: ws.path,
      runner: fake,
      forceAndroid: forceAndroid,
    );
  }

  group('安卓双路径（forceAndroid: true）', () {
    test('run 模式：code 落临时 .py → runner.runOnce(entry/args/workDir/timeout)，成功输出 stdout', () async {
      final fake = FakePluginRunner()..result = const RunResult('2', '', 0);
      final tool = buildTool(fake);

      final out = await tool.execute({'mode': 'run', 'code': 'print(1+1)'});

      expect(fake.calls, hasLength(1));
      final call = fake.calls.single;
      expect(p.basename(call.entry), startsWith('python_runner_'));
      expect(call.entry, endsWith('.py'));
      // code 已写入临时文件（fake 在执行期间捕获内容）
      expect(fake.lastEntryContent, 'print(1+1)');
      expect(call.args, isEmpty);
      expect(call.workingDirectory, ws.path);
      expect(call.timeout, const Duration(seconds: 30));
      // finally 已删除临时文件
      expect(File(call.entry).existsSync(), isFalse);
      expect(out, '2');
    });

    test('run 模式：exitCode!=0 → [Python exited with code N] + stderr + stdout', () async {
      final fake = FakePluginRunner()..result = const RunResult('trace', 'boom', 3);
      final tool = buildTool(fake);

      final out = await tool.execute({'mode': 'run', 'code': 'raise ValueError("x")'});

      expect(fake.calls, hasLength(1));
      expect(out, contains('[Python exited with code 3]'));
      expect(out, contains('[stderr]'));
      expect(out, contains('boom'));
      expect(out, contains('[stdout]'));
      expect(out, contains('trace'));
    });

    test('run 模式：成功且 stderr 非空 → stdout 合并 [stderr] 段', () async {
      final fake = FakePluginRunner()..result = const RunResult('out1', 'warn-line', 0);
      final tool = buildTool(fake);

      final out = await tool.execute({'mode': 'run', 'code': 'print(1)'});

      expect(out, contains('out1'));
      expect(out, contains('[stderr]'));
      expect(out, contains('warn-line'));
    });

    test('危险代码拦截不变：不触 runner，返回 warning', () async {
      final fake = FakePluginRunner();
      final tool = buildTool(fake);

      final out = await tool.execute(
          {'mode': 'run', 'code': 'import os; os.system("ls")'});

      expect(out, contains('[warning: python_runner 拒绝执行'));
      expect(fake.calls, isEmpty);
    });

    test('pip 模式：返回安卓构建期提示文案，不触 runner', () async {
      final fake = FakePluginRunner();
      final tool = buildTool(fake);

      final out =
          await tool.execute({'mode': 'pip', 'pip_cmd': 'install', 'package': 'numpy'});

      expect(out, contains('Chaquopy 无运行时 pip'));
      expect(out, contains('chaquopy.pip {}'));
      expect(out, contains('requests 全家桶 + pycryptodome'));
      expect(out, contains('重新打包 APK'));
      expect(fake.calls, isEmpty);
    });

    test('sys 模式：复用 Chaquopy 执行路径（sys 信息脚本落临时文件）', () async {
      final fake = FakePluginRunner()..result = const RunResult('sys-info', '', 0);
      final tool = buildTool(fake);

      final out = await tool.execute({'mode': 'sys'});

      expect(fake.calls, hasLength(1));
      final call = fake.calls.single;
      expect(call.entry, endsWith('.py'));
      expect(call.workingDirectory, ws.path);
      final script = fake.lastEntryContent!;
      expect(script, contains('=== Python 系统信息 ==='));
      expect(script, contains('importlib.metadata'));
      // importlib.metadata 异常时降级分支存在
      expect(script, contains('except Exception'));
      expect(File(call.entry).existsSync(), isFalse);
      expect(out, 'sys-info');
    });
  });

  group('桌面路径（forceAndroid: false 回归）', () {
    test('run 模式：不触 runner，走 Process.start（exe 不存在 → 可读错误）', () async {
      final fake = FakePluginRunner();
      final tool = PythonRunnerTool(
        pythonExePath: p.join(tmp.path, 'no_such_python'),
        pythonWorkDir: tmp.path,
        workspaceDir: ws.path,
        runner: fake,
        forceAndroid: false,
      );

      final out = await tool.execute({'mode': 'run', 'code': 'print(1)'});

      expect(fake.calls, isEmpty);
      expect(out, contains('[error: python_runner:'));
    });

    test('pip 模式：不返回安卓提示（走桌面 pip 子进程 → 启动失败可读错误）', () async {
      final fake = FakePluginRunner();
      final tool = PythonRunnerTool(
        pythonExePath: p.join(tmp.path, 'no_such_python'),
        pythonWorkDir: tmp.path,
        workspaceDir: ws.path,
        runner: fake,
        forceAndroid: false,
      );

      final out = await tool.execute({'mode': 'pip', 'pip_cmd': 'list'});

      expect(out, isNot(contains('Chaquopy 无运行时 pip')));
      expect(out, contains('[error: python_runner:'));
      expect(fake.calls, isEmpty);
    });
  });
}

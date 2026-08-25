/// PluginRunner.runOnce 超时语义测试（T4）。
///
/// 覆盖：
/// - `timeout` 超时后**杀死子进程**（而非丢下孤儿）并抛 [TimeoutException]
/// - 无 `timeout` 时行为不变（正常收集 stdout/exitCode）
/// - 在 `timeout` 内完成则不误杀
///
/// 用 Python「fake 慢脚本」（`time.sleep(30)`）模拟挂起；`python3` 是直接解释器，
/// kill 直接终止睡眠进程（无子进程转发/孤儿），与 CLI 数据源 `.py` 场景一致。
/// 无 `python3` 时相关用例跳过。

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';

void main() {
  late Directory tmp;
  late bool pythonAvailable;

  setUpAll(() async {
    try {
      final r = await Process.run('python3', ['--version']);
      pythonAvailable = r.exitCode == 0;
    } catch (_) {
      pythonAvailable = false;
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin_runner_t');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('runOnce 超时后 kill 子进程并抛 TimeoutException（fake 慢脚本）', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');

    final script = File('${tmp.path}/slow.py');
    script.writeAsStringSync('import time\ntime.sleep(30)\nprint("done")\n');

    const runner = SubprocessRunner('python3');
    final sw = Stopwatch()..start();
    await expectLater(
      runner.runOnce(
        script.path,
        const [],
        timeout: const Duration(milliseconds: 800),
      ),
      throwsA(isA<TimeoutException>()),
    );
    sw.stop();
    // 若超时未 kill 子进程，会等满 30s 且不抛 TimeoutException。
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('runOnce 未传 timeout 时正常返回（回归）', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');

    final script = File('${tmp.path}/fast.py');
    script.writeAsStringSync('print("hello")\n');

    const runner = SubprocessRunner('python3');
    final res = await runner.runOnce(script.path, const []);
    expect(res.exitCode, 0);
    expect(res.stdout, contains('hello'));
  });

  test('runOnce 在 timeout 内完成则正常返回（不误杀）', () async {
    if (!pythonAvailable) return markTestSkipped('python3 不可用');

    final script = File('${tmp.path}/quick.py');
    script.writeAsStringSync('print("quick")\n');

    const runner = SubprocessRunner('python3');
    final res = await runner.runOnce(
      script.path,
      const [],
      timeout: const Duration(seconds: 10),
    );
    expect(res.exitCode, 0);
    expect(res.stdout, contains('quick'));
  });
}

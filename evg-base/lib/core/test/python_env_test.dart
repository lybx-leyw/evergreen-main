/// PythonInterpreter 统一解释器解析测试——单例收敛 / 哨兵改造 / 双真理源合并。
///
/// 覆盖：
/// - [PythonRuntime] 结构化结果（kind / isAvailable / isAndroidChaquopy /
///   legacyExePath 哨兵）
/// - [PythonInterpreter.resolve]：configuredPath 优先、greenix 目录（可绑定）、
///   成功缓存语义、resetForTest
/// - [bindGreenixPythonDir]：单一真理来源（消除 cwd 内联路径双真理）
/// - [PythonInterpreter.bundledPathSync]：同步探测
///
/// ⚠️ 本机存在 `.greenix/python/python.exe`（嵌入式 Python）时，未绑定/未指定
/// 的解析会命中 greenix 分支——测试一律通过临时目录 + 绑定/指定路径控制确定性。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../utils/python_env.dart';

void main() {
  group('PythonRuntime', () {
    test('bundled：exePath 非空、isAvailable、非安卓哨兵', () {
      const rt = PythonRuntime(
          kind: PythonRuntimeKind.bundled, exePath: r'C:\x\python.exe');
      expect(rt.isAvailable, isTrue);
      expect(rt.isAndroidChaquopy, isFalse);
      expect(rt.legacyExePath, r'C:\x\python.exe');
    });

    test('system：exePath 为命令名', () {
      const rt = PythonRuntime(kind: PythonRuntimeKind.system, exePath: 'python');
      expect(rt.isAvailable, isTrue);
      expect(rt.exePath, 'python');
      expect(rt.legacyExePath, 'python');
    });

    test('androidChaquopy：哨兵收敛为常量，不可当命令执行', () {
      const rt = PythonRuntime(kind: PythonRuntimeKind.androidChaquopy);
      expect(rt.isAvailable, isTrue);
      expect(rt.isAndroidChaquopy, isTrue);
      expect(rt.exePath, isNull);
      // legacyExePath 只返回显式常量，杜绝字符串散落
      expect(rt.legacyExePath, kChaquopySentinel);
      expect(rt.legacyExePath, 'chaquopy');
    });

    test('none：不可用、exePath 为 null', () {
      const rt = PythonRuntime.none();
      expect(rt.isAvailable, isFalse);
      expect(rt.isAndroidChaquopy, isFalse);
      expect(rt.exePath, isNull);
      expect(rt.legacyExePath, isNull);
    });

    test('toJson / toString 可序列化', () {
      const rt = PythonRuntime(
          kind: PythonRuntimeKind.bundled, exePath: '/p/python.exe');
      expect(rt.toJson(), {'kind': 'bundled', 'exePath': '/p/python.exe'});
      expect(rt.toString(), contains('bundled'));
    });
  });

  group('PythonInterpreter.resolve', () {
    late Directory tmp;

    setUp(() {
      PythonInterpreter.resetForTest();
      tmp = Directory.systemTemp.createTempSync('pyenv_test_');
    });

    tearDown(() {
      PythonInterpreter.resetForTest();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('configuredPath 存在 → bundled，返回该路径（最高优先级）', () async {
      final exe = File(p.join(tmp.path, 'python.exe'))..writeAsStringSync('x');
      final rt = await PythonInterpreter.instance.resolve(configuredPath: exe.path);
      expect(rt.kind, PythonRuntimeKind.bundled);
      expect(rt.exePath, exe.path);
    });

    test('configuredPath 不存在 → 不采纳（文件存在才采纳）', () async {
      final missing =
          p.join(tmp.path, 'no_such', 'python.exe');
      final rt = await PythonInterpreter.instance.resolve(configuredPath: missing);
      // 不应返回 configuredPath 本身
      expect(rt.exePath, isNot(missing));
    });

    test('bindGreenixPythonDir 绑定后 → 优先使用该目录（双真理源合并）', () async {
      Directory(p.join(tmp.path, 'python')).createSync(recursive: true);
      final exe = File(p.join(tmp.path, 'python', 'python.exe'))
        ..writeAsStringSync('x');
      bindGreenixPythonDir(() => p.join(tmp.path, 'python'));

      final rt = await PythonInterpreter.instance.resolve();
      expect(rt.kind, PythonRuntimeKind.bundled);
      expect(rt.exePath, exe.path);
    });

    test('无参解析成功结果缓存；resetForTest 后重新探测', () async {
      Directory(p.join(tmp.path, 'python')).createSync(recursive: true);
      final exe = File(p.join(tmp.path, 'python', 'python.exe'))
        ..writeAsStringSync('x');
      bindGreenixPythonDir(() => p.join(tmp.path, 'python'));

      final rt1 = await PythonInterpreter.instance.resolve();
      expect(rt1.exePath, exe.path);

      // 成功缓存：即使文件被删除，缓存仍返回旧结果
      exe.deleteSync();
      final rt2 = await PythonInterpreter.instance.resolve();
      expect(rt2.exePath, exe.path);

      // resetForTest 清空缓存 → 重新探测（greenix 已空 → 不再 bundled）
      PythonInterpreter.resetForTest();
      final rt3 = await PythonInterpreter.instance.resolve();
      expect(rt3.isBundled, isFalse);
    });

    test('configuredPath 传参跳过缓存（显式指定不被缓存污染）', () async {
      Directory(p.join(tmp.path, 'python')).createSync(recursive: true);
      final bundled = File(p.join(tmp.path, 'python', 'python.exe'))
        ..writeAsStringSync('x');
      bindGreenixPythonDir(() => p.join(tmp.path, 'python'));
      await PythonInterpreter.instance.resolve(); // 缓存 bundled

      // 显式指定另一路径 → 应返回该路径而非缓存
      final custom = File(p.join(tmp.path, 'custom', 'python.exe'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      final rt = await PythonInterpreter.instance.resolve(configuredPath: custom.path);
      expect(rt.kind, PythonRuntimeKind.bundled);
      expect(rt.exePath, custom.path);
      expect(rt.exePath, isNot(bundled.path));
    });
  });

  group('PythonInterpreter.bundledPathSync', () {
    late Directory tmp;

    setUp(() {
      PythonInterpreter.resetForTest();
      tmp = Directory.systemTemp.createTempSync('pyenv_sync_');
    });

    tearDown(() {
      PythonInterpreter.resetForTest();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('greenix 目录有 python.exe → 返回该路径', () {
      Directory(p.join(tmp.path, 'python')).createSync(recursive: true);
      final exe = File(p.join(tmp.path, 'python', 'python.exe'))
        ..writeAsStringSync('x');
      bindGreenixPythonDir(() => p.join(tmp.path, 'python'));
      expect(PythonInterpreter.bundledPathSync(), exe.path);
    });

    test('greenix 目录无 python.exe → null', () {
      bindGreenixPythonDir(() => p.join(tmp.path, 'empty'));
      expect(PythonInterpreter.bundledPathSync(), isNull);
    });
  });

  group('resolvePythonExe 兼容包装', () {
    late Directory tmp;

    setUp(() {
      PythonInterpreter.resetForTest();
      tmp = Directory.systemTemp.createTempSync('pyenv_wrap_');
    });

    tearDown(() {
      PythonInterpreter.resetForTest();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('configuredPath 存在 → 返回该路径（旧签名行为不变）', () async {
      final exe = File(p.join(tmp.path, 'python.exe'))..writeAsStringSync('x');
      expect(await resolvePythonExe(configuredPath: exe.path), exe.path);
    });

    test('安卓哨兵经常量返回（legacyExePath == kChaquopySentinel）', () {
      // 直接构造安卓运行时，验证兼容层语义（无需真实 Android 平台）
      const rt = PythonRuntime(kind: PythonRuntimeKind.androidChaquopy);
      expect(rt.legacyExePath, kChaquopySentinel);
    });
  });
}

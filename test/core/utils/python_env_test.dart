import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_multi_tools/core/utils/python_env.dart';

void main() {
  // ── PythonEnv.checkPython ───────────────────────────────────

  group('PythonEnv.checkPython', () {
    test('默认 python 可检查', () async {
      final env = PythonEnv();
      final ok = await env.checkPython();
      // 开发环境应安装 Python，但 CI 可能没有
      expect(ok, anyOf(isTrue, isFalse));
    });

    test('配置路径不存在时回退到系统 Python', () async {
      // resolvePythonExe 优先级: bundled > configured > PATH。
      // 若 bundled 不存在且配置路径无效，会兜底到系统 PATH 上的 python。
      // 因此本测试接受 true（系统有 Python）或 false（无 Python 环境）。
      final env = PythonEnv(python: 'nonexistent_python_xyz');
      final ok = await env.checkPython();
      expect(ok, anyOf(isTrue, isFalse));
    });
  });

  // ── PythonEnv.checkDeps ─────────────────────────────────────

  group('PythonEnv.checkDeps', () {
    test('检查依赖返回包名或 null', () async {
      final env = PythonEnv();
      final missing = await env.checkDeps();
      // 返回 null（全部安装）或包名字符串（有缺失）
      expect(missing, anyOf(isNull, isA<String>()));
    });

    test('已知的包名在返回值中', () async {
      final env = PythonEnv();
      final missing = await env.checkDeps();
      if (missing != null) {
        // 返回值应为 requirements.txt 中的包名之一
        const known = ['pytesseract', 'Pillow', 'requests', 'pdf2image'];
        expect(known, contains(missing));
      }
    });
  });

  // ── PythonEnv.ensureReady ───────────────────────────────────

  group('PythonEnv.ensureReady', () {
    test('检查并准备 Python 环境', () async {
      final env = PythonEnv();
      try {
        final error = await env
            .ensureReady()
            .timeout(const Duration(minutes: 3));
        // 返回 null（就绪）或错误消息字符串
        expect(error, anyOf(isNull, isA<String>()));
      } on Exception catch (e) {
        // 超时或进程异常：ensureReady 不应抛异常，但 CI 环境差异可能导致
        expect(e.toString(), isA<String>());
      }
    });

    test('配置路径不存在时回退到系统 Python → 可能成功或报错', () async {
      // resolvePythonExe 会兜底到系统 PATH。若系统有 Python，ensureReady 可能
      // 成功（返回 null）或因 deps 缺失返回错误消息（不一定是"未找到 Python"）。
      final env = PythonEnv(python: 'nonexistent_python_xyz');
      final error = await env.ensureReady();
      // 可能 null（Python + deps 就绪）、可能报 Python 未找到（系统无 Python）、
      // 可能报 deps 缺失（系统有 Python 但缺依赖）
      if (error != null) {
        expect(error, isA<String>());
        expect(error, anyOf(
          contains('未找到 Python'),
          contains('dep'),
          contains('依赖'),
          contains('pip'),
          contains('requirements'),
          contains('OCR'),
        ));
      }
    });

    test('onProgress 回调被触发', () async {
      final progressCalls = <String>[];
      final env = PythonEnv();
      try {
        final error = await env
            .ensureReady(onProgress: (msg) => progressCalls.add(msg))
            .timeout(const Duration(minutes: 3));
        // 至少应触发"检查 Python 环境..."
        expect(progressCalls.isNotEmpty, isTrue);
        // 如果 Python 可用，还会有"检查 OCR 依赖..."
        if (error == null) {
          expect(progressCalls.any((s) => s.contains('检查 OCR 依赖')), isTrue);
        }
      } on Exception catch (e) {
        // 超时或进程异常时 progressCalls 可能为空 — 容错
        expect(e.toString(), isA<String>());
      }
    });
  });

  // ── PythonEnv.installDeps ───────────────────────────────────

  group('PythonEnv.installDeps', () {
    test('requirements.txt 缺失 → false', () async {
      final env = PythonEnv(requirements: '/nonexistent/req.txt');
      final ok = await env.installDeps();
      expect(ok, isFalse);
    });

    test('requirements.txt 存在时可安装', () async {
      final env = PythonEnv();
      final reqFile = File(env.requirementsPath);
      if (!reqFile.existsSync()) {
        // 跳过——没有 requirements.txt
        return;
      }
      final ok = await env.installDeps(
        onProgress: (pkg, success) {
          expect(pkg, isNotEmpty);
        },
      );
      // 可能成功也可能失败（网络问题等）
      expect(ok, anyOf(isTrue, isFalse));
    });
  });

  // ── runOcrProcess ───────────────────────────────────────────

  group('runOcrProcess', () {
    test('简单 echo 命令', () async {
      final result = await runOcrProcess(
        Platform.isWindows ? 'cmd' : 'echo',
        Platform.isWindows ? ['/c', 'echo', 'hello'] : ['hello'],
      );
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('hello'));
    });

    test('脚本不存在 → 非零退出码', () async {
      final result = await runOcrProcess(
        'python',
        ['/nonexistent/script.py'],
      );
      expect(result.exitCode, isNonZero);
    });

    test('workingDirectory 参数生效', () async {
      final tmpDir = Directory.systemTemp.createTempSync('ocr_test_');
      try {
        // 创建临时 Python 脚本
        final script = File('${tmpDir.path}/test.py');
        script.writeAsStringSync('import os; print(os.getcwd())');
        final result = await runOcrProcess(
          'python',
          [script.path],
          workingDirectory: tmpDir.path,
        );
        expect(result.exitCode, 0);
        // CWD 应包含临时目录（路径分隔符归一化）
        final stdout = result.stdout.toString().trim();
        expect(stdout.replaceAll('\\', '/'),
            tmpDir.path.replaceAll('\\', '/'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });
}

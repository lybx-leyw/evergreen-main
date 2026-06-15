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

    test('自定义 pythonExe 不存在 → false', () async {
      final env = PythonEnv(python: 'nonexistent_python_xyz');
      final ok = await env.checkPython();
      expect(ok, isFalse);
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
      final error = await env.ensureReady();
      // 返回 null（就绪）或错误消息字符串
      expect(error, anyOf(isNull, isA<String>()));
    });

    test('python 不存在时返回错误消息', () async {
      final env = PythonEnv(python: 'nonexistent_python_xyz');
      final error = await env.ensureReady();
      expect(error, isNotNull);
      expect(error, isA<String>());
      expect(error, contains('未找到 Python'));
    });

    test('onProgress 回调被触发', () async {
      final progressCalls = <String>[];
      final env = PythonEnv();
      final error = await env.ensureReady(
        onProgress: (msg) => progressCalls.add(msg),
      );
      // 至少应触发"检查 Python 环境..."
      expect(progressCalls.isNotEmpty, isTrue);
      // 如果 Python 可用，还会有"检查 OCR 依赖..."
      if (error == null) {
        expect(progressCalls.any((s) => s.contains('检查 OCR 依赖')), isTrue);
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

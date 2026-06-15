/// Python 环境管理 — 检查依赖、自动安装。以及 OCR 子进程执行。
///
/// 提供给 OCR 脚本调用方使用，确保 Python 依赖在子进程运行前已就绪，
/// 并将 HuggingFace Token/Endpoint 正确传递给子进程。

import 'dart:io';
import 'package:path/path.dart' as p;

/// 运行 OCR 相关 Python 子进程，自动继承 HF_TOKEN 等环境变量。
///
/// 用法:
/// ```dart
/// final result = await runOcrProcess('python', [script, '--path', path]);
/// ```
///
/// 子进程自动继承父进程环境变量（包括 HF_TOKEN、HF_ENDPOINT 等），
/// 所以用户在终端设置好环境变量即可，无需额外配置。
Future<ProcessResult> runOcrProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    includeParentEnvironment: true,
  );
}

/// Python 依赖管理。
class PythonEnv {
  final String pythonExe;
  final String requirementsPath;

  PythonEnv({
    String? python,
    String? requirements,
  })  : pythonExe = python ?? 'python',
        requirementsPath = requirements ??
            p.join(Directory.current.path, 'scripts', 'requirements.txt');

  /// 检查 Python 是否可执行。
  Future<bool> checkPython() async {
    try {
      final result = await Process.run(pythonExe, ['--version'])
          .timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 检查所有 OCR 依赖是否已安装。
  ///
  /// 返回缺失的包名，全部已安装则返回 null。
  Future<String?> checkDeps() async {
    // 包名 → verify 代码，确保导入路径与脚本实际使用的模块一致
    const packages = <String, String>{
      'pytesseract': 'import pytesseract',
      'Pillow': 'from PIL import Image',
      'requests': 'import requests',
      'pdf2image': 'from pdf2image import convert_from_path',
    };

    for (final entry in packages.entries) {
      try {
        final result = await Process.run(
          pythonExe,
          ['-c', entry.value],
        ).timeout(const Duration(seconds: 10));
        if (result.exitCode != 0) return entry.key;
      } catch (_) {
        return entry.key;
      }
    }
    return null;
  }

  /// 自动安装 OCR 依赖。
  Future<bool> installDeps({
    void Function(String pkg, bool success)? onProgress,
  }) async {
    if (!await File(requirementsPath).exists()) return false;

    try {
      final result = await Process.run(
        pythonExe,
        ['-m', 'pip', 'install', '-r', requirementsPath, '--user'],
      ).timeout(const Duration(seconds: 120));

      final success = result.exitCode == 0;
      onProgress?.call('requirements.txt', success);
      return success;
    } catch (_) {
      onProgress?.call('pip', false);
      return false;
    }
  }

  /// 检查 Python + 安装依赖，一步完成。
  Future<String?> ensureReady({
    void Function(String msg)? onProgress,
  }) async {
    onProgress?.call('检查 Python 环境...');
    final hasPython = await checkPython();
    if (!hasPython) return '未找到 Python ($pythonExe)，请安装 Python 3.8+';

    onProgress?.call('检查 OCR 依赖...');
    final missing = await checkDeps();
    if (missing == null) return null;

    onProgress?.call('正在安装 $missing...');
    final installed = await installDeps();
    if (!installed) {
      return 'OCR 依赖安装失败，请手动执行: pip install -r "$requirementsPath"';
    }

    final stillMissing = await checkDeps();
    if (stillMissing != null) {
      return '依赖 $stillMissing 安装后仍不可用，请手动安装';
    }

    return null;
  }
}

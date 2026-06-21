/// Python 环境管理 — 检查依赖、自动安装。以及 OCR 子进程执行。
///
/// 提供给 OCR 脚本调用方使用，确保 Python 依赖在子进程运行前已就绪，
/// 并将 HuggingFace Token/Endpoint 正确传递给子进程。

import 'dart:io';
import 'package:path/path.dart' as p;
import '../log.dart';

/// 按优先级自动发现 Python 可执行文件路径。
///
/// 1. `scripts/python/python.exe`（安装包自带的嵌入 Python）
/// 2. 用户手动配置的 [configuredPath]
/// 3. 系统 PATH：`python3` → `python` → `py -3`
///
/// 返回 null 表示未找到任何可用的 Python。
Future<String?> resolvePythonExe({String? configuredPath}) async {
  // 1. 自带嵌入 Python（最高优先级）
  try {
    final bundled = p.join(
      Directory.current.path, 'scripts', 'python', 'python.exe');
    final bundledFile = File(bundled);
    if (await bundledFile.exists()) {
      Log().info('PythonEnv: using bundled Python', data: {'path': bundled});
      return bundled;
    }
  } catch (_) {}

  // 2. 用户手动配置
  if (configuredPath != null && configuredPath.isNotEmpty) {
    final configuredFile = File(configuredPath);
    if (await configuredFile.exists()) {
      Log().info('PythonEnv: using configured Python',
          data: {'path': configuredPath});
      return configuredPath;
    }
    Log().debug('PythonEnv: configured Python not found',
        data: {'path': configuredPath});
  }

  // 3. 系统 PATH
  for (final candidate in ['python3', 'python', 'py']) {
    try {
      final checkArgs = candidate == 'py' ? ['-3', '--version'] : ['--version'];
      final result = await Process.run(candidate, checkArgs)
          .timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        Log().info('PythonEnv: using system Python', data: {'path': candidate});
        return candidate;
      }
    } catch (_) {}
  }

  Log().warn('PythonEnv: no Python found');
  return null;
}

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
  final String? _configuredPython;
  final String requirementsPath;

  PythonEnv({
    String? python,
    String? requirements,
  })  : _configuredPython = python,
        requirementsPath = requirements ??
            p.join(Directory.current.path, 'scripts', 'requirements.txt');

  /// 获取可用的 Python 路径（自动检测或使用配置）。
  Future<String?> get pythonExe async {
    return await resolvePythonExe(configuredPath: _configuredPython);
  }

  /// 检查 Python 是否可执行。
  Future<bool> checkPython() async {
    try {
      final exe = await pythonExe;
      if (exe == null) return false;
      final result = await Process.run(exe, ['--version'])
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
    final exe = await pythonExe;
    if (exe == null) return 'python (未找到 Python)';

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
          exe,
          ['-c', entry.value],
        ).timeout(const Duration(seconds: 10));
        if (result.exitCode != 0) return entry.key;
      } catch (_) {
        return entry.key;
      }
    }
    return null;
  }

  /// 检查 pdf2zh 翻译依赖是否已安装。
  ///
  /// [scriptsDir] 为 scripts/ 目录路径（pdf2zh_next 所在位置）。
  /// 返回 null 表示全部就绪，否则返回错误描述。
  Future<String?> checkPdf2zhDeps(String scriptsDir) async {
    final exe = await pythonExe;
    if (exe == null) return '未找到 Python，请安装 Python 3.10+';

    const verifyCode = r'''
import sys; sys.path.insert(0, r'__SCRIPTS_DIR__')
from pdf2zh_next.high_level import do_translate_async_stream
from pdf2zh_next.config.model import SettingsModel
from pdf2zh_next.config.translate_engine_model import DeepSeekSettings
''';

    final code = verifyCode.replaceAll('__SCRIPTS_DIR__',
        scriptsDir.replaceAll('\\', '\\\\'));

    try {
      final result = await Process.run(
        exe,
        ['-c', code],
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        if (stderr.isNotEmpty) return 'pdf2zh: $stderr';
        return 'pdf2zh 依赖不可用';
      }
      return null;
    } on ProcessException catch (e) {
      return '无法执行 Python: ${e.message}';
    } catch (_) {
      return 'pdf2zh 检查超时';
    }
  }

  /// 安装 pdf2zh 所需的外部依赖。
  ///
  /// 等价于 `pip install babeldoc pymupdf openai`。
  Future<bool> installPdf2zhDeps({
    void Function(String msg)? onProgress,
  }) async {
    final exe = await pythonExe;
    if (exe == null) {
      onProgress?.call('未找到 Python，无法安装依赖');
      return false;
    }
    onProgress?.call('正在安装 pdf2zh 依赖 (babeldoc, pymupdf, openai)...');
    try {
      final result = await Process.run(
        exe,
        ['-m', 'pip', 'install', 'babeldoc', 'pymupdf', 'openai'],
      ).timeout(const Duration(seconds: 300));
      return result.exitCode == 0;
    } on ProcessException {
      onProgress?.call('pip 安装失败：无法执行 python');
      return false;
    } catch (_) {
      onProgress?.call('pip 安装超时');
      return false;
    }
  }

  /// 一步检查并安装 pdf2zh 环境。
  ///
  /// [scriptsDir] 为 scripts/ 目录路径（内含 pdf2zh_next/）。
  Future<String?> ensurePdf2zhReady(String scriptsDir, {
    void Function(String msg)? onProgress,
  }) async {
    onProgress?.call('检查 Python 环境...');

    // 如果显式配置了 Python 路径但文件不存在，直接报错
    if (_configuredPython != null && _configuredPython!.isNotEmpty) {
      if (!await File(_configuredPython!).exists()) {
        return '未找到 Python ($_configuredPython)，请确认路径正确';
      }
    }

    final exe = await pythonExe;
    final hasPython = await checkPython();
    if (!hasPython) {
      final label = exe ?? 'python';
      return '未找到 Python ($label)，请安装 Python 3.10+';
    }

    onProgress?.call('检查 pdf2zh 依赖...');
    final missing = await checkPdf2zhDeps(scriptsDir);
    if (missing == null) return null;

    onProgress?.call(missing);
    final installed = await installPdf2zhDeps(onProgress: onProgress);
    if (!installed) {
      return 'pdf2zh 依赖安装失败，请手动执行: pip install babeldoc pymupdf openai';
    }

    final stillMissing = await checkPdf2zhDeps(scriptsDir);
    if (stillMissing != null) {
      return 'pdf2zh 依赖安装后仍不可用: $stillMissing';
    }

    return null;
  }

  /// 自动安装 OCR 依赖。
  Future<bool> installDeps({
    void Function(String pkg, bool success)? onProgress,
  }) async {
    final exe = await pythonExe;
    if (exe == null) return false;
    if (!await File(requirementsPath).exists()) return false;

    try {
      final result = await Process.run(
        exe,
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

    // 如果显式配置了 Python 路径但文件不存在，直接报错（不降级到系统 Python）
    if (_configuredPython != null && _configuredPython!.isNotEmpty) {
      if (!await File(_configuredPython!).exists()) {
        return '未找到 Python ($_configuredPython)，请确认路径正确';
      }
    }

    final exe = await pythonExe;
    final hasPython = await checkPython();
    if (!hasPython) {
      final label = exe ?? 'python';
      return '未找到 Python ($label)，请安装 Python 3.8+';
    }

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

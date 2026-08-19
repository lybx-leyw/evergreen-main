/// 爬虫导出工具——导出 Python 脚本或 PyInstaller 打包为 .exe。
library scraper_exporter;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/python_env.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart'; // InferredSchema

/// 导出结果。
class ExportResult {
  final bool success;
  final String message;
  final String? filePath;

  const ExportResult({
    required this.success,
    required this.message,
    this.filePath,
  });
}

/// 锁定配置模板——强制注入到每个 scraper.py 中。
///
/// **AI 不可修改此模板的任何代码逻辑。**
/// 模板包含三级降级：
///   策略1（主）：.greenix/config.json 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 指定）
///   策略2（降级）：HTTP 从 ConfigHttpServer 读取
///   策略3（兜底）：系统环境变量
///
/// AI 只能填充 `{CREDENTIAL_PLACEHOLDER}` 占位符，填入具体的凭证变量声明。
const String scraperConfigTemplate = r'''
# ═══════════════════════════════════════════════════════════
# EVERGREEN CONFIG TEMPLATE (LOCKED — DO NOT MODIFY)
# ═══════════════════════════════════════════════════════════
import json, os, urllib.request, urllib.error
from pathlib import Path

def _get_config(key):
    """从平台配置读取凭证（三级降级）。
    
    策略1（主）：.greenix/config.json 本地文件直接读取（路径由 GREENIX_CONFIG_PATH 环境变量指定）
    策略2（降级）：HTTP 从 ConfigHttpServer 读取
    策略3（兜底）：系统环境变量
    """
    # ── 策略1：.greenix/config.json 本地文件直接读取 ──
    greenix_path = os.environ.get('GREENIX_CONFIG_PATH')
    if greenix_path:
        try:
            config_path = Path(greenix_path)
            if config_path.exists():
                with open(config_path, 'r', encoding='utf-8') as f:
                    cfg = json.load(f)
                val = cfg.get(key, '')
                if val:
                    return val
        except Exception:
            pass
    
    # ── 策略2：HTTP 从 ConfigHttpServer 读取 ──
    try:
        port_file = None
        for base in [Path.cwd(), Path(os.environ.get('PROJECT_ROOT', '.'))]:
            try:
                for d in [base] + list(base.parents):
                    pf = d / '.config_port'
                    if pf.exists():
                        port_file = pf
                        break
            except Exception:
                continue
            if port_file:
                break
        
        if port_file:
            with open(port_file, 'r') as f:
                port = f.read().strip()
            url = f'http://127.0.0.1:{port}/config/settings/{key}'
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read())
                val = data.get('value', '')
                if val:
                    return val
    except Exception:
        pass
    
    # ── 策略3：系统环境变量 ──
    val = os.environ.get(key)
    if val:
        return val
    
    raise RuntimeError(
        f'无法获取配置 "{key}"：\n'
        f'  1. .greenix/config.json 不存在或无此 key\n'
        f'  2. ConfigHttpServer 不可用（检查 .config_port）\n'
        f'  3. 环境变量未设置\n'
        f'  → 请在设置面板注册此配置项，或设置环境变量 {key}'
    )

# ═══════════════════════════════════════════════════════════
# CREDENTIALS — AI 填空区（只允许修改以下行）
# 格式: VARIABLE_NAME = _get_config('CONFIG_KEY_NAME')
# ═══════════════════════════════════════════════════════════
{CREDENTIAL_PLACEHOLDER}
''';

/// 旧版 config_reader.py（保留兼容导出）。
const String configReaderPy = scraperConfigTemplate;

/// manifest 自动生成配置 — 传给 [exportAsPython] / [exportAsExe] 的可选参数。
///
/// 提供后，.py 或 .exe 导出成功时自动调用 [exportDataManifest]。
class ExportManifestConfig {
  final String name;
  final InferredSchema schema;

  const ExportManifestConfig({required this.name, required this.schema});
}

/// 导出爬虫为 .py 文件（含配置模板）。
///
/// 将 [pythonCode] 写入 [outputDir] 目录：
/// - `scraper.py` — AI 生成的爬虫代码（强制注入配置模板）
/// - `config_reader.py` — 配置模板独立副本（供外部引用）
///
/// 若提供 [manifestConfig]，则在 .py 写入成功后自动调用 [exportDataManifest]。
Future<ExportResult> exportAsPython(
  String pythonCode,
  String outputDir, {
  ExportManifestConfig? manifestConfig,
}) async {
  try {
    // 回退：若 pythonCode 为空，尝试从已有的 scraper.py 读取
    if (pythonCode.isEmpty) {
      final existingPath = p.join(outputDir, 'scraper.py');
      final existingFile = File(existingPath);
      if (existingFile.existsSync()) {
        pythonCode = existingFile.readAsStringSync();
        debugPrint('[ScraperExporter] 从已有 scraper.py 读取代码 (${pythonCode.length} chars)');
      }
    }

    if (pythonCode.isEmpty) {
      return const ExportResult(
        success: false,
        message: '导出失败：爬虫代码为空。请先完成 AI 代码生成和执行验证。',
      );
    }

    // 若代码不含 _get_config，强制注入锁定模板
    if (!pythonCode.contains('def _get_config(key)')) {
      debugPrint('[ScraperExporter] ⚠ 代码中未包含 _get_config 模板，强制注入');
      final injected = scraperConfigTemplate
        .replaceFirst(
          '{CREDENTIAL_PLACEHOLDER}',
          '# TODO: 在此填入凭证变量声明，格式: VAR = _get_config(\'KEY_NAME\')',
        );
      pythonCode = '$injected\n$pythonCode';
    }

    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // 写入 config_reader.py（独立副本）
    final readerPath = p.join(outputDir, 'config_reader.py');
    final readerContent = scraperConfigTemplate
      .replaceFirst(
        '{CREDENTIAL_PLACEHOLDER}',
        '# 使用示例:\n# USERNAME = _get_config(\'ZJU_USERNAME\')\n# PASSWORD = _get_config(\'ZJU_PASSWORD\')',
      );
    await File(readerPath).writeAsString(readerContent);
    debugPrint('[ScraperExporter] 写入 config_reader.py: $readerPath');

    // 写入 scraper.py
    final scraperPath = p.join(outputDir, 'scraper.py');
    await File(scraperPath).writeAsString(pythonCode);
    debugPrint('[ScraperExporter] 写入 scraper.py: $scraperPath');

    final result = ExportResult(
      success: true,
      message: '导出成功:\n- $scraperPath\n- $readerPath',
      filePath: scraperPath,
    );

    // 可选：自动生成 data/manifest.json
    if (manifestConfig != null) {
      debugPrint('[ScraperExporter] 📝 auto manifest → ${manifestConfig.name}');
      await exportDataManifest(
        name: manifestConfig.name,
        fetcherScript: 'scraper.py',
        schema: manifestConfig.schema,
        outputDir: outputDir,
      );
    }

    return result;
  } catch (e) {
    debugPrint('[ScraperExporter] ❌ 导出 .py 失败: $e');
    return ExportResult(
      success: false,
      message: '导出失败: $e',
    );
  }
}

/// 生成 data 插件的 manifest.json（对齐 `_scanAndRegisterDataSources` 真实契约）。
///
/// 输出到 `{outputDir}/data/manifest.json`，格式：
/// ```json
/// {
///   "type": "data-source",
///   "runtime": "python",
///   "script": "scraper.py",
///   "dataTypes": [
///     {
///       "name": "...",
///       "typeArg": "...",
///       "ttl": "5m",
///       "persistentKey": "custom-{name}:...",
///       "category": "...",
///       "displayName": "..."
///     }
///   ]
/// }
/// ```
///
/// [name]: 插件英文标识
/// [fetcherScript]: 脚本文件名（相对 data/ 目录），如 'scraper.py' 或 'scraper.exe'
/// [schema]: 推断的数据结构
/// [outputDir]: 插件根目录（如 plugins/my-scraper/）
Future<ExportResult> exportDataManifest({
  required String name,
  required String fetcherScript,
  required InferredSchema schema,
  required String outputDir,
  /// 显式指定的数据类型名称（如用户命名）。null 时回退到 [schema.title ?? name]。
  String? dataTypeName,
  /// Phase 4：探索模式显式归类（manifest category，D3 细粒度归类）。
  String? category,
  /// Phase 4：探索模式显式展示名（manifest displayName）。
  String? displayName,
  /// Phase 6：字段 schema（探索模式候选字段，落盘供下游/校验复用）。
  List<Map<String, dynamic>>? fields,
}) async {
  try {
    debugPrint('[ScraperExporter] 📝 生成 data manifest: $name → $outputDir');

    // 1) 确保 data/ 目录存在
    final dataDir = Directory(p.join(outputDir, 'data'));
    if (!dataDir.existsSync()) {
      dataDir.createSync(recursive: true);
      debugPrint('[ScraperExporter] 创建目录: ${dataDir.path}');
    }

    // 2) 构建 manifest（严格对齐 _scanAndRegisterDataSources 契约）
    final resolvedDataTypeName = dataTypeName ?? schema.title ?? name;
    final dataTypeEntry = <String, dynamic>{
      'name': resolvedDataTypeName,
      'typeArg': resolvedDataTypeName,
      'ttl': '5m',
      'persistentKey': 'custom-$name:$resolvedDataTypeName',
      'category': category ?? dataTypeName ?? schema.title ?? '数据采集',
      'displayName': displayName ?? dataTypeName ?? schema.title ?? name,
      // Phase 6：字段 schema 落盘（缺省时仍留空列表占位，保持结构可预期）。
      'fields': (fields == null || fields.isEmpty)
          ? <Map<String, dynamic>>[]
          : fields,
    };
    final manifest = {
      'type': 'data-source',
      // 统一 .py 插件契约：script 指向 .py，由解释器（桌面）/ Chaquopy（安卓）
      // 执行，不再依赖 PyInstaller 编译的 .exe（安卓无法 exec PE 格式）。
      'runtime': 'python',
      'script': fetcherScript,
      'dataTypes': [dataTypeEntry],
    };

    // 3) 写入 manifest.json
    final manifestPath = p.join(dataDir.path, 'manifest.json');
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    debugPrint('[ScraperExporter] ✅ data manifest 已写入: $manifestPath');
    return ExportResult(
      success: true,
      message: 'data manifest 已生成: $manifestPath',
      filePath: manifestPath,
    );
  } catch (e) {
    debugPrint('[ScraperExporter] ❌ data manifest 生成失败: $e');
    return ExportResult(
      success: false,
      message: 'data manifest 生成失败: $e',
    );
  }
}

/// 使用 PyInstaller 将爬虫打包为 .exe。
///
/// 要求系统已安装 PyInstaller（`pip install pyinstaller`）。
/// 返回生成的可执行文件路径。
Future<ExportResult> exportAsExe(
  String pythonCode,
  String outputDir,
  Future<String?> Function() resolvePython, {
  ExportManifestConfig? manifestConfig,
}) async {
  try {
    // 1) 先导出 .py
    final pyResult = await exportAsPython(pythonCode, outputDir, manifestConfig: manifestConfig);
    if (!pyResult.success) return pyResult;

    // 2) 发现 Python
    final pyExe = await resolvePython();
    if (pyExe == null) {
      return const ExportResult(
        success: false,
        message: '未找到 Python 解释器，无法执行 PyInstaller。请确保 Python 3.8+ 已安装。',
      );
    }

    // 3) 检查 PyInstaller
    final checkResult = await Process.run(
      pyExe,
      ['-m', 'pip', 'show', 'pyinstaller'],
    ).timeout(const Duration(seconds: 15));

    if (checkResult.exitCode != 0) {
      debugPrint('[ScraperExporter] PyInstaller 未安装，正在安装...');
      final installResult = await Process.run(
        pyExe,
        ['-m', 'pip', 'install', 'pyinstaller'],
      ).timeout(const Duration(seconds: 120));

      if (installResult.exitCode != 0) {
        return ExportResult(
          success: false,
          message: 'PyInstaller 安装失败: ${installResult.stderr}',
        );
      }
    }

    // 4) 执行 PyInstaller
    final scraperPath = p.join(outputDir, 'scraper.py');
    final distDir = p.join(outputDir, 'dist');
    debugPrint('[ScraperExporter] 运行 PyInstaller: $scraperPath');

    final result = await Process.run(
      pyExe,
      [
        '-m',
        'PyInstaller',
        '--onefile',
        '--console',
        '--distpath',
        distDir,
        '--workpath',
        p.join(outputDir, 'build'),
        '--specpath',
        outputDir,
        scraperPath,
      ],
      workingDirectory: outputDir,
    ).timeout(const Duration(seconds: 300));

    if (result.exitCode != 0) {
      final err = (result.stderr as String).length > 500
          ? '${(result.stderr as String).substring(0, 500)}...'
          : (result.stderr as String);
      debugPrint('[ScraperExporter] ❌ PyInstaller 失败: $err');
      return ExportResult(
        success: false,
        message: 'PyInstaller 打包失败:\n$err',
      );
    }

    final exePath = p.join(distDir, 'scraper.exe');
    if (File(exePath).existsSync()) {
      debugPrint('[ScraperExporter] ✅ .exe 生成完毕: $exePath');
      return ExportResult(
        success: true,
        message: '导出成功:\n$exePath',
        filePath: exePath,
      );
    } else {
      return ExportResult(
        success: false,
        message: 'PyInstaller 执行完成但未找到输出文件。请检查 $distDir 目录。',
      );
    }
  } catch (e) {
    debugPrint('[ScraperExporter] 💥 导出 .exe 异常: $e');
    return ExportResult(
      success: false,
      message: '导出异常: $e',
    );
  }
}

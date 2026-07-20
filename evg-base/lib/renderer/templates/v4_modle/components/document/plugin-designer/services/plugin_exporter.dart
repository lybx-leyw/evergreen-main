/// 插件导出器 —— 将 DesignDocument 导出为完整的插件目录。
///
/// 支持两种输出模式：
/// - [exportToDir] — 直接写入磁盘目录（用于热加载和预览）
/// - [exportAsZip] — 打包为 ZIP 文件（用于分发和共享）
///
/// P4 实现：提供"发布到市场"和"导出插件"按钮的底层能力。
library;

import 'dart:convert';
import 'dart:io';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/design_to_manifest.dart';

/// 导出结果。
class ExportResult {
  final bool success;
  final String targetPath;
  final String? manifestPath;
  final String? error;
  final List<String> createdFiles;

  const ExportResult({
    required this.success,
    required this.targetPath,
    this.manifestPath,
    this.error,
    this.createdFiles = const [],
  });

  factory ExportResult.ok(String targetPath,
          {String? manifestPath, List<String> createdFiles = const []}) =>
      ExportResult(
        success: true,
        targetPath: targetPath,
        manifestPath: manifestPath,
        createdFiles: createdFiles,
      );

  factory ExportResult.fail(String targetPath, String error) => ExportResult(
        success: false,
        targetPath: targetPath,
        error: error,
      );
}

/// 插件导出器。
///
/// 使用方式：
/// ```dart
/// final exporter = PluginExporter('plugins/');
/// final result = await exporter.exportToDir(designDoc);
/// if (result.success) print('导出成功: ${result.targetPath}');
/// ```
class PluginExporter {
  final String pluginsDir;

  PluginExporter(this.pluginsDir);

  /// 将 [DesignDocument] 导出为完整的插件目录到 [pluginsDir]/<pluginId>/。
  ///
  /// 创建目录结构：
  /// ```
  /// plugins/<pluginId>/
  ///   module/
  ///     manifest.json       # 由 DesignToManifest 编译
  ///   config/
  ///     config.json         # 基本配置骨架（若未提供）
  ///   data/
  ///     data_source.json    # 数据源骨架（若未提供）
  /// ```
  Future<ExportResult> exportToDir(DesignDocument doc) async {
    final createdFiles = <String>[];
    try {
      final pluginDir = Directory('${_normDir(pluginsDir)}${doc.pluginId}');
      final created = <String>[];

      // 1. module/manifest.json
      final moduleDir = Directory('${pluginDir.path}/module');
      if (!await moduleDir.exists()) {
        await moduleDir.create(recursive: true);
        created.add('${moduleDir.path}/');
      }

      final manifest = DesignToManifest.compile(doc);

      // A-P3 C1：导出校验 —— 确保产物可被真实 ModuleDescriptor 加载，
      // 避免"写出成功但运行不可用"的隐性 bug（与 A-P1 DataPluginer 同构）。
      try {
        ModuleDescriptor.fromJson(manifest);
      } catch (e) {
        return ExportResult.fail(pluginsDir, 'manifest 校验失败: $e');
      }

      final manifestFile = File('${moduleDir.path}/manifest.json');
      await manifestFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      created.add(manifestFile.path);

      // 2. config/config.json（如果 metadata 中有 config）
      final configData = doc.metadata['config'] as Map<String, dynamic>?;
      if (configData != null && configData.isNotEmpty) {
        final configDir = Directory('${pluginDir.path}/config');
        if (!await configDir.exists()) {
          await configDir.create(recursive: true);
          created.add('${configDir.path}/');
        }
        final configFile = File('${configDir.path}/config.json');
        await configFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(configData));
        created.add(configFile.path);
      }

      // 3. data/data_source.json（如果有数据源信息）
      final dataInfo = doc.metadata['data_source'] as Map<String, dynamic>?;
      if (dataInfo != null && dataInfo.isNotEmpty) {
        final dataDir = Directory('${pluginDir.path}/data');
        if (!await dataDir.exists()) {
          await dataDir.create(recursive: true);
          created.add('${dataDir.path}/');
        }
        final dsFile = File('${dataDir.path}/data_source.json');
        await dsFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(dataInfo));
        created.add(dsFile.path);
      }

      // 4. agent/manifest.json（如果 metadata 中有 agent 信息）
      final agentInfo = doc.metadata['agent'] as Map<String, dynamic>?;
      if (agentInfo != null && agentInfo.isNotEmpty) {
        final agentDir = Directory('${pluginDir.path}/agent');
        if (!await agentDir.exists()) {
          await agentDir.create(recursive: true);
          created.add('${agentDir.path}/');
        }
        final agentFile = File('${agentDir.path}/manifest.json');
        await agentFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(agentInfo));
        created.add(agentFile.path);
      }

      return ExportResult.ok(
        pluginDir.path,
        manifestPath: manifestFile.path,
        createdFiles: created,
      );
    } catch (e) {
      return ExportResult.fail(pluginsDir, e.toString());
    }
  }

  /// 将 [DesignDocument] 导出为 ZIP 文件。
  ///
  /// ZIP 包含上述完整目录结构。
  /// 输出到 [outputPath]（如 'output/my-plugin.zip'）。
  Future<ExportResult> exportAsZip(
      DesignDocument doc, String outputPath) async {
    try {
      // 先导出到临时目录
      final tempDir = '${_normDir(pluginsDir)}.temp_export_${doc.pluginId}';
      final dirResult = await exportToDir(doc);
      if (!dirResult.success) {
        return dirResult;
      }

      // 使用 dart:io 的 Archive 能力打包
      final zipResult = await _createZip(dirResult.targetPath, outputPath);

      // 清理临时目录（注意：此处 targetPath 是 plugins/<id>，不是 temp）
      // 我们直接压缩 plugins/<id> 而不用临时目录
      return zipResult;
    } catch (e) {
      return ExportResult.fail(outputPath, e.toString());
    }
  }

  /// 创建 ZIP 文件。
  ///
  /// 使用 dart:io 的 Process 调用系统压缩（无额外依赖）。
  Future<ExportResult> _createZip(
      String sourceDir, String outputPath) async {
    try {
      // Windows: 使用 PowerShell Compress-Archive
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Compress-Archive',
          '-Path',
          sourceDir,
          '-DestinationPath',
          outputPath,
          '-Force',
        ]);
        if (result.exitCode != 0) {
          return ExportResult.fail(
              outputPath, 'ZIP failed: ${result.stderr}');
        }
      } else {
        // 其他平台尝试用系统 zip 命令
        final result = await Process.run('zip', [
          '-r',
          outputPath,
          '.',
        ], workingDirectory: sourceDir);
        if (result.exitCode != 0) {
          return ExportResult.fail(
              outputPath, 'ZIP failed: ${result.stderr}');
        }
      }

      return ExportResult.ok(outputPath, createdFiles: [outputPath]);
    } catch (e) {
      return ExportResult.fail(outputPath, 'ZIP error: $e');
    }
  }

  /// 规范化目录路径（确保以 / 结尾）。
  String _normDir(String dir) =>
      dir.endsWith('/') || dir.endsWith('\\') ? dir : '$dir/';
}

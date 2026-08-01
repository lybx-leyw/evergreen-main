/// HTML 插件导出服务 —— 支持双目录同步。
///
/// 导出到两个目标：
/// 1. `{pluginsDir}/{pluginId}/module/` — 运行期插件目录
/// 2. `{assetsBundleDir}/{pluginId}/module/` — 内置插件资产目录
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';

class ExportResult {
  final bool success;
  final String message;
  final List<String> createdFiles;
  final List<String> bundleFiles;

  const ExportResult({
    required this.success,
    required this.message,
    this.createdFiles = const [],
    this.bundleFiles = const [],
  });
}

/// 将 [HtmlProject] 导出为完整的 HTML 模板插件目录。
///
/// 同时写入两个目标目录，确保插件在开发期和运行期都可用。
class HtmlExportService {
  final String pluginsDir;
  final String? assetsBundleDir;

  HtmlExportService(this.pluginsDir, {this.assetsBundleDir});

  /// 导出项目到磁盘：
  ///   {pluginsDir}/{id}/module/manifest.json + index.html
  ///   {assetsBundleDir}/{id}/module/manifest.json + index.html (可选)
  Future<ExportResult> export(HtmlProject project) async {
    final created = <String>[];
    final bundleFiles = <String>[];

    try {
      // ── 目标 1：运行期插件目录 ──
      final pluginResult = await _exportTo(
        pluginsDir,
        project,
        created,
        label: 'plugins',
      );

      if (!pluginResult) {
        return ExportResult(success: false, message: '导出到 plugins/ 失败', createdFiles: created);
      }

      // ── 目标 2：内置插件资产目录 ──
      if (assetsBundleDir != null) {
        final bundleOk = await _exportTo(
          assetsBundleDir!,
          project,
          bundleFiles,
          label: 'assets_bundle',
        );
        if (!bundleOk) {
          debugPrint('[HtmlExport] ⚠ 导出到 assets/plugins_bundle/ 失败（非致命）');
        }
      }

      return ExportResult(
        success: true,
        message: '已导出到 $pluginsDir${project.pluginId}/'
            '${assetsBundleDir != null ? ' + assets/plugins_bundle/' : ''}',
        createdFiles: created,
        bundleFiles: bundleFiles,
      );
    } catch (e) {
      return ExportResult(success: false, message: '导出失败: $e', createdFiles: created);
    }
  }

  Future<bool> _exportTo(
    String rootDir,
    HtmlProject project,
    List<String> fileLog, {
    String label = '',
  }) async {
    try {
      final pluginDir = Directory('${_normDir(rootDir)}${project.pluginId}');
      final moduleDir = Directory('${pluginDir.path}/module');

      if (!await moduleDir.exists()) {
        await moduleDir.create(recursive: true);
        fileLog.add('[${label}] ${moduleDir.path}/');
      }

      // manifest.json
      final manifest = _buildManifest(project);
      final manifestFile = File('${moduleDir.path}/manifest.json');
      await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      fileLog.add('[${label}] ${manifestFile.path}');

      // index.html
      final indexFile = File('${moduleDir.path}/index.html');
      await indexFile.writeAsString(project.htmlContent);
      fileLog.add('[${label}] ${indexFile.path}');

      debugPrint('[HtmlExport] ✅ ${label}: ${moduleDir.path}');
      return true;
    } catch (e) {
      debugPrint('[HtmlExport] ❌ ${label}: $e');
      return false;
    }
  }

  Map<String, dynamic> _buildManifest(HtmlProject project) => {
        'schemaVersion': '2.0',
        'type': 'module',
        'id': project.pluginId,
        'name': project.pluginName,
        if (project.description != null) 'description': project.description,
        if (project.icon != null) 'icon': project.icon,
        'template': 'html',
        'version': '1.0.0',
        'route': '/${project.pluginId}',
        'nav': {
          'sidebar': {
            'section': project.navSection,
            'sectionOrder': 99,
            'order': 99,
          },
        },
      };

  String _normDir(String d) => d.endsWith('/') || d.endsWith('\\') ? d : '$d/';
}

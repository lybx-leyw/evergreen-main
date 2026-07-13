/// 插件生成器 —— 全流程插件生成编排。
///
/// P1 实现：爬虫输出 → DataPluginer → ConfigRegister → 完整插件目录。
///
/// 用法：
/// ```dart
/// final generator = PluginGenerator();
/// final result = await generator.generateFromScraper(
///   name: 'my-scraper',
///   outputDir: 'plugins/my-scraper/',
///   schema: inferredSchema,
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'config_register.dart';
import 'data_pluginer.dart';

/// 插件生成阶段。
enum PluginGeneratePhase {
  /// 等待开始。
  idle,

  /// 正在生成 data 插件。
  generatingData,

  /// 正在生成配置。
  generatingConfig,

  /// 正在写入 module manifest。
  generatingModule,

  /// 生成完成。
  done,

  /// 生成失败。
  failed,
}

/// 插件生成状态。
class PluginGenerateStatus {
  final PluginGeneratePhase phase;
  final double progress; // 0.0 ~ 1.0
  final String? message;

  const PluginGenerateStatus({
    required this.phase,
    this.progress = 0.0,
    this.message,
  });

  const PluginGenerateStatus.idle()
      : phase = PluginGeneratePhase.idle,
        progress = 0.0,
        message = null;

  PluginGenerateStatus copyWith({
    PluginGeneratePhase? phase,
    double? progress,
    String? message,
  }) =>
      PluginGenerateStatus(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        message: message,
      );
}

/// 插件生成结果。
class PluginGenerateResult {
  final bool success;
  final String message;
  final String? pluginDir;
  final String? dataManifestPath;
  final String? configPath;
  final String? moduleManifestPath;

  const PluginGenerateResult({
    required this.success,
    required this.message,
    this.pluginDir,
    this.dataManifestPath,
    this.configPath,
    this.moduleManifestPath,
  });
}

/// 插件生成器 —— 编排完整生成流程。
///
/// 流程：
/// 1. DataPluginer 注册 data 插件（生成 data/manifest.json）
/// 2. ConfigRegister 分析字段 → 生成 config/config.json
/// 3. 写入 module/manifest.json（占位 P2 编排 → 完整 P2 更新）
/// 4. 通知 PluginPreloader 热加载
///
/// 通过 [onStatusChanged] 回调报告进度。
class PluginGenerator {
  final DataPluginer _dataPluginer = DataPluginer();
  final ConfigRegister _configRegister = ConfigRegister();

  PluginGenerateStatus _status = const PluginGenerateStatus.idle();
  PluginGenerateStatus get status => _status;

  /// 状态变更回调 —— 由 UI 层设置以触发 [setState]。
  void Function(PluginGenerateStatus)? onStatusChanged;

  void _updateStatus(PluginGeneratePhase phase, {double? progress, String? message}) {
    _status = _status.copyWith(phase: phase, progress: progress, message: message);
    onStatusChanged?.call(_status);
  }

  /// 从爬虫输出生成完整插件。
  ///
  /// - [name]: 插件名称
  /// - [outputDir]: 插件根目录（如 `plugins/my-scraper/`）
  /// - [schema]: 爬虫推断的数据结构
  /// - [endpoint]: 数据端点（默认 `/data/{name}`）
  Future<PluginGenerateResult> generateFromScraper({
    required String name,
    required String outputDir,
    required InferredSchema schema,
    String? endpoint,
  }) async {
    try {
      debugPrint('[PluginGenerator] 🚀 开始生成插件 "$name"');
      _updateStatus(PluginGeneratePhase.generatingData, progress: 0.1, message: '生成 data 插件...');

      // ── 第1步：DataPluginer ──
      final dataResult = await _dataPluginer.registerDataPlugin(
        name: name,
        outputDir: outputDir,
        schema: schema,
        endpoint: endpoint,
      );

      if (!dataResult.success) {
        return _fail('data 插件注册失败: ${dataResult.message}');
      }

      _updateStatus(PluginGeneratePhase.generatingConfig, progress: 0.4, message: '生成配置...');

      // ── 第2步：ConfigRegister ──
      final fieldMaps = schema.fields.map((f) => f.toJson()).toList();
      final configResult = await _configRegister.generateConfig(
        pluginDir: outputDir,
        fields: fieldMaps,
      );

      if (!configResult.success) {
        debugPrint('[PluginGenerator] ⚠ 配置生成失败（非致命）: ${configResult.message}');
      }

      _updateStatus(PluginGeneratePhase.generatingModule, progress: 0.7, message: '生成 module manifest...');

      // ── 第3步：写入 module/manifest.json ──
      final moduleResult = await _writeModuleManifest(
        outputDir: outputDir,
        name: name,
        schema: schema,
      );

      _updateStatus(PluginGeneratePhase.done, progress: 1.0, message: '插件生成完毕');

      debugPrint('[PluginGenerator] ✅ 插件 "$name" 生成完成');
      return PluginGenerateResult(
        success: true,
        message: '插件 "$name" 生成完成',
        pluginDir: outputDir,
        dataManifestPath: dataResult.manifestPath,
        configPath: configResult.success ? configResult.configPath : null,
        moduleManifestPath: moduleResult,
      );
    } catch (e) {
      return _fail('插件生成异常: $e');
    }
  }

  /// 写入 module/manifest.json（含数据绑定引用）。
  ///
  /// P1: 占位骨架（单页全屏）。
  /// P2: 将被编排面板更新为完整的多页布局。
  Future<String> _writeModuleManifest({
    required String outputDir,
    required String name,
    required InferredSchema schema,
  }) async {
    final moduleDir = Directory(p.join(outputDir, 'module'));
    if (!moduleDir.existsSync()) {
      moduleDir.createSync(recursive: true);
    }

    final manifest = {
      'schemaVersion': '2.0',
      'id': 'custom-$name',
      'name': schema.title ?? name,
      'description': '由爬虫生成器自动创建: ${schema.sourceUrl}',
      'version': '1.0.0',
      'dataBindings': {
        'default': 'data/$name',
      },
      'pages': [
        {
          'label': '主页',
          'layout': {
            'preset': 'fullscreen',
            'slots': <Map<String, dynamic>>[],
          },
        }
      ],
    };

    final manifestPath = p.join(moduleDir.path, 'manifest.json');
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    debugPrint('[PluginGenerator] module manifest 已写入: $manifestPath');
    return manifestPath;
  }

  PluginGenerateResult _fail(String message) {
    _updateStatus(PluginGeneratePhase.failed, progress: 0.0, message: message);
    debugPrint('[PluginGenerator] ❌ $message');
    return PluginGenerateResult(success: false, message: message);
  }

  /// 释放资源。
  void dispose() {
    onStatusChanged = null;
  }
}

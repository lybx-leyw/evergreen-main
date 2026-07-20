/// 数据插件注册器 —— 将爬虫输出包装为标准 data 插件。
///
/// P1 实现：生成 data manifest.json + 注册插件目录。
///
/// 用法：
/// ```dart
/// final pluginer = DataPluginer();
/// final result = await pluginer.registerDataPlugin(
///   name: 'my-scraper',
///   outputDir: 'plugins/my-scraper/',
///   fields: [...],
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// data 插件注册结果。
class DataPluginResult {
  final bool success;
  final String message;
  final String? manifestPath;

  const DataPluginResult({
    required this.success,
    required this.message,
    this.manifestPath,
  });
}

/// 推断的字段定义（来自爬虫输出分析）。
class InferredField {
  final String name;
  final String type; // string / number / boolean / date
  final String? description;

  const InferredField({
    required this.name,
    required this.type,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    if (description != null) 'description': description,
  };

  factory InferredField.fromJson(Map<String, dynamic> json) => InferredField(
    name: json['name'] as String,
    type: json['type'] as String? ?? 'string',
    description: json['description'] as String?,
  );
}

/// 推断的数据结构（爬虫输出 → AI 分析结果）。
class InferredSchema {
  final String sourceUrl;
  final String? title;
  final List<InferredField> fields;

  const InferredSchema({
    required this.sourceUrl,
    this.title,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
    'sourceUrl': sourceUrl,
    if (title != null) 'title': title,
    'fields': fields.map((f) => f.toJson()).toList(),
  };

  factory InferredSchema.fromJson(Map<String, dynamic> json) => InferredSchema(
    sourceUrl: json['sourceUrl'] as String,
    title: json['title'] as String?,
    fields: (json['fields'] as List)
        .map((f) => InferredField.fromJson(f as Map<String, dynamic>))
        .toList(),
  );
}

/// data 插件注册器。
///
/// 职责：将爬虫输出包装为标准 data 插件目录结构：
/// ```
/// plugins/<name>/
/// ├── data/
/// │   ├── manifest.json    ← 由本类生成
/// │   ├── scraper.py       ← 由 ScraperExporter 写入
/// │   └── scraper.exe      ← 由 PyInstaller 编译（可选）
/// ```
class DataPluginer {
  /// 注册一个 data 插件。
  ///
  /// - [name]: 插件名称（英文标识，如 `my-scraper`）
  /// - [outputDir]: 插件根目录（如 `plugins/my-scraper/`）
  /// - [schema]: 爬虫输出的推断数据结构
  ///
  /// 生成的 manifest.json 对齐 `_scanAndRegisterDataSources` 真实契约：
  /// - `type`: "data-source"
  /// - `script`: 脚本文件名（相对 data/ 目录）
  /// - `dataTypes[]`: 含 name/typeArg/ttl/persistentKey/category/displayName
  Future<DataPluginResult> registerDataPlugin({
    required String name,
    required String outputDir,
    required InferredSchema schema,
  }) async {
    try {
      // 1) 创建 data/ 目录
      final dataDir = Directory(p.join(outputDir, 'data'));
      if (!dataDir.existsSync()) {
        dataDir.createSync(recursive: true);
        debugPrint('[DataPluginer] 创建目录: ${dataDir.path}');
      }

      // 2) 推断 script 文件名（.exe 存在则优先，否则 .py）
      final exePath = p.join(dataDir.path, 'scraper.exe');
      final script = File(exePath).existsSync() ? 'scraper.exe' : 'scraper.py';
      debugPrint('[DataPluginer] script 默认: $script (exe exists: ${File(exePath).existsSync()})');

      // 3) 生成 data manifest.json（对齐 _scanAndRegisterDataSources 契约）
      final manifest = _buildDataManifest(
        name: name,
        schema: schema,
        script: script,
      );

      // 4) 写入 manifest.json
      final manifestPath = p.join(dataDir.path, 'manifest.json');
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      debugPrint('[DataPluginer] ✅ data manifest 已写入: $manifestPath');

      // 5) 确保 module/ 根目录存在一个占位 module manifest（后续 P2 编排会更新）
      _ensureModuleManifest(outputDir, name);

      return DataPluginResult(
        success: true,
        message: 'data 插件 "$name" 注册成功',
        manifestPath: manifestPath,
      );
    } catch (e) {
      debugPrint('[DataPluginer] ❌ 注册失败: $e');
      return DataPluginResult(
        success: false,
        message: 'data 插件注册失败: $e',
      );
    }
  }

  /// 生成 data manifest.json（对齐 `_scanAndRegisterDataSources` 真实契约）。
  ///
  /// 关键字段：
  /// - `script`: 脚本文件名（相对 data/ 目录，如 scraper.py 或 scraper.exe）
  /// - `dataTypes[]`: DataOrchestrator 注册的数据类型列表
  Map<String, dynamic> _buildDataManifest({
    required String name,
    required InferredSchema schema,
    required String script,
  }) {
    final dataTypeName = schema.title ?? name;
    return {
      'type': 'data-source',
      'script': script,
      'dataTypes': [
        {
          'name': dataTypeName,
          'typeArg': dataTypeName,
          'ttl': '5m',
          'persistentKey': 'custom-$name:$dataTypeName',
          'category': schema.title ?? '数据采集',
          'displayName': schema.title ?? name,
        }
      ],
    };
  }

  /// 确保 module/ 目录下有占位 manifest.json。
  ///
  /// 如果 module/manifest.json 不存在，则创建一个最小占位 manifest。
  /// P2 编排阶段会将其更新为完整的多页面 manifest。
  void _ensureModuleManifest(String outputDir, String name) {
    final moduleDir = Directory(p.join(outputDir, 'module'));
    if (!moduleDir.existsSync()) {
      moduleDir.createSync(recursive: true);
    }

    final manifestPath = p.join(moduleDir.path, 'manifest.json');
    if (!File(manifestPath).existsSync()) {
      final placeholder = {
        'schemaVersion': '2.0',
        'id': 'custom-$name',
        'name': name,
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
      File(manifestPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(placeholder),
      );
      debugPrint('[DataPluginer] 创建 module manifest 占位: $manifestPath');
    }
  }
}

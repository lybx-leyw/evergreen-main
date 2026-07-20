/// 配置自动注册器 —— 分析 data 插件字段 → 生成 config.json。
///
/// P1 实现：从 data manifest 推断配置项。
///
/// 用法：
/// ```dart
/// final register = ConfigRegister();
/// final result = await register.generateConfig(
///   pluginDir: 'plugins/my-scraper/',
///   fields: [...],
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 配置注册结果。
class ConfigRegisterResult {
  final bool success;
  final String message;
  final String? configPath;
  final Map<String, String>? settingsKeyMap; // field → config key

  const ConfigRegisterResult({
    required this.success,
    required this.message,
    this.configPath,
    this.settingsKeyMap,
  });
}

/// 配置项定义。
class ConfigItem {
  final String key; // config key (如 API_KEY)
  final String label; // 显示标签
  final String type; // string / password / number / toggle
  final String? defaultValue;
  final String? description;

  const ConfigItem({
    required this.key,
    required this.label,
    this.type = 'string',
    this.defaultValue,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type,
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (description != null) 'description': description,
  };

  factory ConfigItem.fromJson(Map<String, dynamic> json) => ConfigItem(
    key: json['key'] as String,
    label: json['label'] as String,
    type: json['type'] as String? ?? 'string',
    defaultValue: json['defaultValue'] as String?,
    description: json['description'] as String?,
  );
}

/// 配置注册器。
///
/// 职责：
/// 1. 分析 data 插件导出的字段列表
/// 2. 识别需要凭证/配置的字段（如 API_KEY, PASSWORD 等）
/// 3. 生成 config.json 设置面板配置
/// 4. 建立 field → config key 的映射关系
///
/// 生成目录结构：
/// ```
/// plugins/<name>/
/// ├── config/
/// │   └── config.json    ← 由本类生成
/// ```
class ConfigRegister {
  /// 敏感字段关键词（用于自动识别需要配置的字段）。
  static const _sensitiveKeywords = [
    'api_key', 'apikey', 'token', 'secret',
    'password', 'passwd', 'credential',
    'auth', 'authorization', 'bearer',
  ];

  /// 从字段列表生成配置。
  ///
  /// - [pluginDir]: 插件根目录
  /// - [fields]: 爬虫输出的字段定义（from DataPluginer/InferredField）
  /// - [existingConfig]: 已有配置项（新增时保留）
  Future<ConfigRegisterResult> generateConfig({
    required String pluginDir,
    required List<Map<String, dynamic>> fields,
    List<ConfigItem>? existingConfig,
  }) async {
    try {
      // 1) 创建 config/ 目录
      final configDir = Directory(p.join(pluginDir, 'config'));
      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
        debugPrint('[ConfigRegister] 创建目录: ${configDir.path}');
      }

      // 2) 识别需要配置的字段
      final configItems = <ConfigItem>[];
      final settingsKeyMap = <String, String>{};

      // 保留已有配置（非字段自动推断的）
      if (existingConfig != null) {
        configItems.addAll(existingConfig);
      }

      for (final field in fields) {
        final name = (field['name'] as String?)?.toLowerCase() ?? '';
        // 只对敏感字段生成配置项
        if (!_isSensitiveField(name)) continue;

        final key = _toConfigKey(name);
        final label = _toConfigLabel(field);

        // 避免重复 key
        if (configItems.any((c) => c.key == key)) continue;

        configItems.add(ConfigItem(
          key: key,
          label: label,
          type: name.contains('password') || name.contains('secret') ? 'password' : 'string',
          description: field['description'] as String?,
        ));

        settingsKeyMap[field['name'] as String] = key;
      }

      // 3) 生成 config.json
      final configJson = {
        'schemaVersion': '2.0',
        'settings': configItems.map((c) => c.toJson()).toList(),
      };

      final configPath = p.join(configDir.path, 'config.json');
      await File(configPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(configJson),
      );
      debugPrint('[ConfigRegister] ✅ config.json 已写入: $configPath (${configItems.length} 项)');

      return ConfigRegisterResult(
        success: true,
        message: '配置注册成功 (${configItems.length} 项)',
        configPath: configPath,
        settingsKeyMap: settingsKeyMap,
      );
    } catch (e) {
      debugPrint('[ConfigRegister] ❌ 失败: $e');
      return ConfigRegisterResult(
        success: false,
        message: '配置注册失败: $e',
      );
    }
  }

  /// 从已有的 data manifest.json 读取字段并生成配置。
  ///
  /// 支持两种 manifest 格式：
  /// - 旧格式: `fields[]` 数组
  /// - 新格式: `dataTypes[]` 数组（name + typeArg = field name/type）
  Future<ConfigRegisterResult> generateFromDataManifest(String pluginDir) async {
    try {
      final dataManifestPath = p.join(pluginDir, 'data', 'manifest.json');
      final file = File(dataManifestPath);
      if (!file.existsSync()) {
        return ConfigRegisterResult(
          success: false,
          message: 'data/manifest.json 不存在: $dataManifestPath',
        );
      }

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      var fields = (json['fields'] as List?)
          ?.cast<Map<String, dynamic>>() ?? [];

      // 兼容新格式: 若 fields 为空，从 dataTypes 推断
      if (fields.isEmpty) {
        final dataTypes = (json['dataTypes'] as List<dynamic>?) ?? [];
        fields = dataTypes
            .whereType<Map<String, dynamic>>()
            .map((dt) => {
                  'name': dt['name'] as String? ?? '',
                  'type': dt['typeArg'] as String? ?? 'string',
                  'description': dt['displayName'] as String?,
                })
            .toList();
      }

      return generateConfig(pluginDir: pluginDir, fields: fields);
    } catch (e) {
      debugPrint('[ConfigRegister] ❌ 从 manifest 读取失败: $e');
      return ConfigRegisterResult(
        success: false,
        message: '读取 data manifest 失败: $e',
      );
    }
  }

  /// 判断字段是否为敏感字段（需要凭据）。 
  bool _isSensitiveField(String name) {
    final lowered = name.toLowerCase();
    return _sensitiveKeywords.any((kw) => lowered.contains(kw));
  }

  /// 字段名 → 配置 key（全大写+下划线）。 
  String _toConfigKey(String name) {
    // snake_case → SCREAMING_SNAKE_CASE
    return name.toUpperCase().replaceAll(' ', '_');
  }

  /// 字段 → 配置标签（人类可读）。 
  String _toConfigLabel(Map<String, dynamic> field) {
    final name = field['name'] as String? ?? '';
    final description = field['description'] as String?;
    if (description != null && description.isNotEmpty) return description;
    // 将 snake_case 或 camelCase 转为可读标签
    return name
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .replaceAll('_', ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }
}

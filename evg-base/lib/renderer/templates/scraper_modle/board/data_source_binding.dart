/// 数据源 ↔ 画板绑定数据层（D2-D4）。
///
/// - [DataSourceInfo]：一个已注册数据源插件的扫描结果（插件目录 +
///   manifest 溯源字段 + 摘要/弹窗序列化）。
/// - [scanDataSourcePlugins]：扫描 `<pluginsRoot>/*/data/manifest.json`，
///   `type == 'data-source'` 才收录（与运行期注册契约一致）。
///
/// 溯源字段约定（D1 写入，本层消费）：
/// - manifest 顶层 `boardId`：创建该数据源的画板（scraper-explore/capture）
/// - manifest 顶层 `boundBoardId`：用户手动建板绑定（优先于 boardId）
/// - manifest 顶层 `createdBy`：scraper-explore / scraper-capture / null（非爬虫创建）
library data_source_binding;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 单个已注册数据源插件的信息（D2 数据层）。
class DataSourceInfo {
  /// 数据源类型名：data-xxx 目录的 xxx，兜底 dataTypes[0].name。
  final String name;

  /// 插件根目录绝对路径（含 data/manifest.json）。
  final String pluginDir;

  /// 展示名：dataTypes[0].displayName 兜底 name。
  final String displayName;

  /// 分类：dataTypes[0].category。
  final String category;

  /// 绑定画板 id：manifest.boundBoardId ?? manifest.boardId（创建画板）。
  final String? boardId;

  /// 创建来源：scraper-explore / scraper-capture / null（非爬虫创建）。
  final String? createdBy;

  /// 原始 manifest（弹窗展示真实 JSON 用）。
  final Map<String, dynamic> rawManifest;

  DataSourceInfo({
    required this.name,
    required this.pluginDir,
    required this.displayName,
    required this.category,
    this.boardId,
    this.createdBy,
    required this.rawManifest,
  });

  /// 从插件目录 + 已解析 manifest 构造。
  factory DataSourceInfo.fromPluginDir(
    String pluginDir,
    Map<String, dynamic> rawManifest,
  ) {
    final dataTypes = (rawManifest['dataTypes'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    final first = dataTypes.isEmpty ? null : dataTypes.first;

    // 名称：data-xxx 目录的 xxx；manifest dataTypes[0].name 兜底
    final dirName = p.basename(pluginDir);
    final dirDerived = dirName.startsWith('data-')
        ? dirName.substring('data-'.length)
        : dirName;
    final manifestName = (first?['name'] as String?)?.trim();
    final name = (manifestName != null && manifestName.isNotEmpty)
        ? manifestName
        : dirDerived;

    final manifestDisplay = (first?['displayName'] as String?)?.trim();
    final displayName = (manifestDisplay != null && manifestDisplay.isNotEmpty)
        ? manifestDisplay
        : name;

    return DataSourceInfo(
      name: name,
      pluginDir: pluginDir,
      displayName: displayName,
      category: (first?['category'] as String?) ?? '',
      // 绑定优先于创建（D4 建板时回写 boundBoardId，创建者字段不动）
      boardId: (rawManifest['boundBoardId'] as String?)
              ?.isNotEmpty ==
          true
          ? rawManifest['boundBoardId'] as String
          : (rawManifest['boardId'] as String?)?.isNotEmpty == true
              ? rawManifest['boardId'] as String
              : null,
      createdBy: rawManifest['createdBy'] as String?,
      rawManifest: rawManifest,
    );
  }

  /// 是否爬虫创建（scraper-explore / scraper-capture）。
  bool get scraperMade => (createdBy ?? '').startsWith('scraper');

  /// 真实 JSON 截断（弹窗用）：完整 manifest 美化 JSON，超长截断并标注。
  String truncatedJson({int maxChars = 2000}) {
    final encoded = const JsonEncoder.withIndent('  ').convert(rawManifest);
    if (encoded.length <= maxChars) return encoded;
    return '${encoded.substring(0, maxChars)}\n…(截断，原 ${encoded.length} 字符)';
  }

  /// 摘要（bound_sources.json 用，向画板 AI 告知数据状态）：
  /// 名称 / 类型 / 字段 / 脚本存在性。
  Map<String, dynamic> toSummaryJson() {
    final dataTypes = (rawManifest['dataTypes'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    final script = rawManifest['script'] as String?;
    final scriptPath =
        script == null ? null : p.join(pluginDir, 'data', script);
    final scriptExists = scriptPath != null && File(scriptPath).existsSync();

    return {
      'name': name,
      'displayName': displayName,
      'category': category,
      'type': dataTypes.isEmpty
          ? name
          : (dataTypes.first['typeArg'] as String? ?? name),
      'fields': _readConfigFields(),
      'script': script ?? '',
      'scriptExists': scriptExists,
      'pluginDir': pluginDir,
      if (boardId != null) 'boardId': boardId,
      if (createdBy != null) 'createdBy': createdBy,
      'scraperMade': scraperMade,
    };
  }

  /// 可配置字段：config/config.json 的 settings 列表（key/label/type）。
  List<Map<String, dynamic>> _readConfigFields() {
    try {
      final file = File(p.join(pluginDir, 'config', 'config.json'));
      if (!file.existsSync()) return const [];
      final json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final settings = (json['settings'] as List<dynamic>?) ?? const [];
      return settings.whereType<Map<String, dynamic>>().map((s) {
        final key = (s['key'] as String?) ?? '';
        return {
          'key': key,
          'label': (s['label'] as String?) ?? key,
          'type': (s['type'] as String?) ?? 'string',
        };
      }).toList();
    } catch (e) {
      debugPrint('[DataSourceInfo] ⚠ 读取 config.json 失败: $e');
      return const [];
    }
  }
}

/// 扫描全部已注册数据源插件（D2）。
///
/// 遍历 `<pluginsRoot>/*/data/manifest.json`，`type == 'data-source'` 才收录；
/// 单个插件解析失败静默跳过，绝不抛。结果按 name 排序。
List<DataSourceInfo> scanDataSourcePlugins({String? pluginsRoot}) {
  final root = pluginsRoot ?? resolvePluginsRoot();
  final result = <DataSourceInfo>[];
  try {
    final dir = Directory(root);
    if (!dir.existsSync()) return result;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final manifestFile = File(p.join(entry.path, 'data', 'manifest.json'));
      if (!manifestFile.existsSync()) continue;
      try {
        final json =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        if (json['type'] != 'data-source') continue;
        result.add(DataSourceInfo.fromPluginDir(entry.path, json));
      } catch (e) {
        debugPrint('[DataSourceInfo] ⚠ 解析插件 manifest 失败: '
            '${entry.path} → $e');
      }
    }
  } catch (e) {
    debugPrint('[DataSourceInfo] ⚠ 扫描数据源插件失败: $e');
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

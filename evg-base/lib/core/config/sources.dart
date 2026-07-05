/// 插件源管理——默认源 + 用户自定义源列表。
///
/// # 公开 API
/// | 成员 | 说明 |
/// |------|------|
/// | `PluginSource` | 插件源数据模型（url / name / isDefault） |
/// | `defaultSourceUrl` | 默认官方源 URL |
/// | `defaultSourceName` | 默认官方源名称 |
/// | `getSources(prefs)` | 获取全部源列表 |
/// | `addSource(prefs, url, name)` | 添加自定义源 |
/// | `removeSource(prefs, url)` | 删除自定义源 |
library sources;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'exceptions.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 常量
// ═══════════════════════════════════════════════════════════════════════════

/// 默认官方源 URL。
const String defaultSourceUrl = 'https://plugins.evergreen.app/index.json';

/// 默认官方源名称。
const String defaultSourceName = 'Evergreen 官方源';

/// SharedPreferences 存储键。
const _sourcesKey = '_plugin_sources';

// ═══════════════════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 一个插件源。
class PluginSource {
  /// 源 URL（必需）。
  final String url;

  /// 显示名称。
  final String name;

  /// 是否为默认官方源。
  final bool isDefault;

  const PluginSource({
    required this.url,
    required this.name,
    this.isDefault = false,
  });

  @override
  String toString() => 'PluginSource($name: $url${isDefault ? " [默认]" : ""})';
}

// ═══════════════════════════════════════════════════════════════════════════
// 公开 API
// ═══════════════════════════════════════════════════════════════════════════

/// 获取全部插件源——默认源始终在列表首位。
List<PluginSource> getSources(SharedPreferences prefs) {
  final sources = <PluginSource>[
    const PluginSource(url: defaultSourceUrl, name: defaultSourceName, isDefault: true),
  ];

  final raw = prefs.getString(_sourcesKey);
  if (raw != null && raw.isNotEmpty) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        sources.add(PluginSource(
          url: m['url'] as String,
          name: m['name'] as String? ?? '',
          isDefault: false,
        ));
      }
    } catch (e) {
      stderr.writeln('[Config] ⚠ 源列表数据损坏: $e');
    }
  }

  return sources;
}

/// 添加自定义插件源。
///
/// 重复的 URL 会抛出 [SourceDuplicateException]。
Future<void> addSource(
  SharedPreferences prefs,
  String url,
  String name,
) async {
  final existing = getSources(prefs);
  if (existing.any((s) => s.url == url)) {
    throw SourceDuplicateException(url);
  }

  final custom = existing
      .where((s) => !s.isDefault)
      .map((s) => {'url': s.url, 'name': s.name})
      .toList();
  custom.add({'url': url, 'name': name});

  await prefs.setString(_sourcesKey, jsonEncode(custom));
}

/// 删除自定义插件源。
///
/// 默认源不可删除；尝试删除默认源将抛出 [ConfigValidationException]。
Future<void> removeSource(SharedPreferences prefs, String url) async {
  if (url == defaultSourceUrl) {
    throw ConfigValidationException(
      key: '_plugin_sources',
      value: url,
      reason: '默认源不可删除',
    );
  }

  final existing = getSources(prefs);
  final custom = existing
      .where((s) => !s.isDefault && s.url != url)
      .map((s) => {'url': s.url, 'name': s.name})
      .toList();

  await prefs.setString(_sourcesKey, jsonEncode(custom));
}

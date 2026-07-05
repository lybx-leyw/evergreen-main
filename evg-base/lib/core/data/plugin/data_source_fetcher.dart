/// 远程插件清单拉取——从默认源 URL 获取 manifest 列表。
///
/// ## 公开 API
/// | 函数 | 说明 |
/// |------|------|
/// | `fetchRemoteManifestList(url)` | 从远程 URL 拉取 manifest 数组 |
/// | `fetchRemoteManifest(url)` | 从远程 URL 拉取单个 manifest |

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/log.dart';

import 'data_source_manifest.dart';

// ═══════════════════════════════════════════════════════════════════════════
// fetchRemoteManifestList
// ═══════════════════════════════════════════════════════════════════════════

/// 从远程 URL 拉取插件清单列表。返回解析后的 [DataSourceManifest] 数组。
///
/// 远程端点应返回 JSON 数组，每个元素为符合 data-source manifest schema 的对象。
/// 请求超时 10 秒，网络错误或格式异常返回空列表。
Future<List<DataSourceManifest>> fetchRemoteManifestList(String url) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) {
        Log().warn('fetchRemoteManifestList: HTTP ${response.statusCode}');
        return [];
      }
      final body = await response.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List<dynamic>;
      return list
          .map((e) =>
              DataSourceManifest.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      client.close(force: true);
    }
  } catch (e) {
    Log().warn('fetchRemoteManifestList: 拉取失败',
        data: {'url': url, 'error': e.toString()});
    return [];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// fetchRemoteManifest
// ═══════════════════════════════════════════════════════════════════════════

/// 从远程 URL 拉取单个插件清单。失败返回 null。
Future<DataSourceManifest?> fetchRemoteManifest(String url) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) {
        Log().warn('fetchRemoteManifest: HTTP ${response.statusCode}');
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return DataSourceManifest.fromJsonString(body);
    } finally {
      client.close(force: true);
    }
  } catch (e) {
    Log().warn('fetchRemoteManifest: 拉取失败',
        data: {'url': url, 'error': e.toString()});
    return null;
  }
}

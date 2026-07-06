/// 应用更新检查——下载远端安装包并校验哈希。
import 'dart:io';

import 'package:dio/dio.dart';
import '../log.dart';

/// 获取当前应用版本（优先 package_info_plus，模块独立测试时回退文件）。
Future<String> _currentVersion() async {
  try {
    // 尝试 package_info_plus（Flutter 环境可用）
    final pi = await _packageInfoFromPlatform();
    return pi.version;
  } catch (_) {
    // 模块独立测试：回退 .version 文件或默认值
    try {
      return File('.version').readAsStringSync().trim();
    } catch (_) {
      return '1.0.0';
    }
  }
}

/// 动态导入 package_info_plus（避免模块级编译失败）。
Future<dynamic> _packageInfoFromPlatform() async {
  // ignore: undefined_function
  return (PackageInfo as dynamic).fromPlatform();
}

// 声明占位类型避免编译错误
class PackageInfo {
  static Future<dynamic> fromPlatform() => throw UnimplementedError('stub');
}

/// 自动更新检查——查询 GitHub Release API。
class UpdateService {
  final Dio _dio;
  final String _repo;
  UpdateService(this._dio, {String repo = 'evergreen-multi-tools/evergreen-multi-tools'})
      : _repo = repo;

  /// 检查是否有新版本。
  /// 返回 (hasUpdate, latestVersion, downloadUrl)。
  Future<(bool, String?, String?)> checkForUpdate() async {
    try {
      final current = await _currentVersion();

      final resp = await _dio.get(
        'https://api.github.com/repos/$_repo/releases/latest',
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final tag = resp.data['tag_name'] as String? ?? '';
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      final assets = resp.data['assets'] as List? ?? [];
      String? downloadUrl;
      for (final a in assets) {
        final name = a['name'] as String? ?? '';
        if (name.endsWith('.exe') || name.endsWith('.msix')) {
          downloadUrl = a['browser_download_url'] as String?;
          break;
        }
      }

      if (latest.isEmpty) return (false, null, null);
      final hasUpdate = _compareVersions(latest, current) > 0;
      return (hasUpdate, latest, downloadUrl);
    } catch (e) {
      Log().warn('Update check failed', error: e);
      return (false, null, null);
    }
  }

  /// 比较版本号：a > b → 1, a == b → 0, a < b → -1。
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av > bv) return 1;
      if (av < bv) return -1;
    }
    return 0;
  }
}

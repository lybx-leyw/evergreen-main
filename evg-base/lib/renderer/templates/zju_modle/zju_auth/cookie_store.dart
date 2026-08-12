import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:evergreen_base/core/utils/greenix_path.dart';

/// ZJU SSO cookie 文件存储——iPlanetDirectoryPro + synjones-auth 跨重启持久化。
///
/// 自参考工程 `cp_evergreen_push/lib/core/network/cookie_manager.dart` 改造：
/// 落盘路径从 `getApplicationSupportDirectory()/zju_cookies.json` 改为
/// evg-base 的 [zjuCookiesPath]（`.greenix/zju_cookies.json`，由
/// [initGreenixPaths] 统一解析，桌面/移动端均落在可写目录）。
class CookieStore {
  static CookieStore? _instance;
  final String _filePath;
  final Map<String, String> _cookies = {};

  CookieStore._(this._filePath);

  /// 单例——落盘到 [zjuCookiesPath]（`.greenix/zju_cookies.json`）。
  static Future<CookieStore> getInstance() async {
    if (_instance != null) return _instance!;
    final instance = CookieStore._(zjuCookiesPath);
    await instance._load();
    _instance = instance;
    return instance;
  }

  /// 测试用：注入独立路径，避免污染全局单例。
  @visibleForTesting
  static Future<CookieStore> createForTesting(String path) async {
    final instance = CookieStore._(path);
    await instance._load();
    return instance;
  }

  /// 测试用：替换全局单例（如注入临时空 cookie，隔离本机真实
  /// `.greenix/zju_cookies.json`——否则「未配置凭证」测试会读到真实
  /// SSO cookie 跳过凭证检查直接走网络）。
  @visibleForTesting
  static void setInstanceForTesting(CookieStore store) {
    _instance = store;
  }

  Future<void> _load() async {
    try {
      final file = File(_filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _cookies.clear();
        map.forEach((key, value) => _cookies[key] = value as String);
      }
    } catch (_) {
      // File doesn't exist or is corrupted — start fresh
    }
  }

  Future<void> _save() async {
    try {
      final file = File(_filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_cookies));
    } catch (_) {
      // Disk write error — cookies will be in-memory only
    }
  }

  /// Get the SSO cookie value (iPlanetDirectoryPro).
  /// Handles migration from old format ("iPlanetDirectoryPro=xxx") to new format ("xxx").
  String? get ssoCookie {
    final raw = _cookies['iPlanetDirectoryPro'];
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('iPlanetDirectoryPro=')) {
      return raw.substring('iPlanetDirectoryPro='.length);
    }
    return raw;
  }

  /// Set the SSO cookie (iPlanetDirectoryPro).
  Future<void> setSsoCookie(String cookie) async {
    _cookies['iPlanetDirectoryPro'] = cookie;
    await _save();
  }

  /// Clear the SSO cookie (logout).
  Future<void> clearSsoCookie() async {
    _cookies.remove('iPlanetDirectoryPro');
    await _save();
  }

  /// Set a generic cookie by name.
  Future<void> setCookie(String name, String value) async {
    _cookies[name] = value;
    await _save();
  }

  /// Get a cookie by name.
  String? getCookie(String name) => _cookies[name];

  /// Get the BlueWare synjones-auth bearer token (if obtained during elife login).
  String? get synjonesAuthToken => _cookies['synjones-auth'];

  /// Set the BlueWare synjones-auth bearer token.
  Future<void> setSynjonesAuthToken(String token) async {
    _cookies['synjones-auth'] = token;
    await _save();
  }

  /// Clear the BlueWare synjones-auth token.
  Future<void> clearSynjonesAuthToken() async {
    _cookies.remove('synjones-auth');
    await _save();
  }

  /// Clear all cookies.
  Future<void> clearAll() async {
    _cookies.clear();
    await _save();
  }
}

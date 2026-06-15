import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Simple file-based cookie store for ZJU SSO cookies.
///
/// The Electron app stored the `iPlanetDirectoryPro` cookie in memory
/// (`_ssoCookie` variable). This provides persistent storage so the
/// SSO cookie survives app restarts.
class CookieStore {
  static CookieStore? _instance;
  final String _filePath;
  final Map<String, String> _cookies = {};

  CookieStore._(this._filePath);

  static Future<CookieStore> getInstance() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationSupportDirectory();
    final filePath = p.join(dir.path, 'zju_cookies.json');
    _instance = CookieStore._(filePath);
    await _instance!._load();
    return _instance!;
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

  /// Clear all cookies.
  Future<void> clearAll() async {
    _cookies.clear();
    await _save();
  }
}

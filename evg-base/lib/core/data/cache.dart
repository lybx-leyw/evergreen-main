/// 持久化缓存
///
/// ## Cache
/// | 方法 | 说明 |
/// |------|------|
/// | `read(key)` | 读缓存，返回 `(data, cachedAt)`；无数据返回 null |
/// | `write(key, data)` | 写缓存，返回 `bool` 表示成功/失败 |
/// | `evict(key)` | 删除单条缓存 |
/// | `clear()` | 清空全部缓存 |

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// _CacheEntry
// ═══════════════════════════════════════════════════════════════════════════
class _CacheEntry {
  final String data;
  final DateTime cachedAt;
  const _CacheEntry({required this.data, required this.cachedAt});

  Map<String, dynamic> toJson() => {
        'cachedAt': cachedAt.toIso8601String(),
        'data': data,
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) {
    return _CacheEntry(
      data: json['data'] as String,
      cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ??
          DateTime(2000),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Cache
// ═══════════════════════════════════════════════════════════════════════════
/// 持久化缓存（文件存储）
/// 缓存文件写入 `{appSupportDir}/web_cache/{key}.json`。
class Cache {
  static Cache? _instance;
  late final String _cacheDir;

  Cache._(this._cacheDir);

  /// 初始化
  /// 异步初始化单例。
  static Future<Cache> getInstance() async {
    if (_instance != null) return _instance!;
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = p.join(appDir.path, 'web_cache');
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _instance = Cache._(cacheDir);
    return _instance!;
  }
  /// 同步获取已初始化的实例。未初始化时返回 null。
  static Cache? get instanceOrNull => _instance;

  /// 读缓存。返回 `(data, cachedAt)`，无数据则返回 null。
  (String, DateTime)? read(String key) {
    final entry = _getEntry(key);
    if (entry == null) return null;
    return (entry.data, entry.cachedAt);
  }

  /// 写缓存，自动记录当前时间为写入时间。返回 `true` 表示写入成功。
  Future<bool> write(String key, String data) async {
    try {
      final entry = _CacheEntry(data: data, cachedAt: DateTime.now());
      final file = File(p.join(_cacheDir, '$key.json'));
      await file.writeAsString(jsonEncode(entry.toJson()));
      return true;
    } catch (e) {
      stderr.writeln('[Cache] 写入失败: $key → $e');
      return false;
    }
  }

  /// 删除指定 key 的缓存。
  Future<void> evict(String key) async {
    try {
      final file = File(p.join(_cacheDir, '$key.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// 清空全部缓存。
  Future<void> clear() async {
    try {
      final dir = Directory(_cacheDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  _CacheEntry? _getEntry(String key) {
    try {
      final file = File(p.join(_cacheDir, '$key.json'));
      if (!file.existsSync()) return null;
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return _CacheEntry.fromJson(raw);
    } catch (_) {
      return null;
    }
  }
}
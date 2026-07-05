import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 缓存条目——携带写入时间戳。
class _CacheEntry {
  final String data;
  final DateTime cachedAt;
  const _CacheEntry({required this.data, required this.cachedAt});

  /// TTL 内为新鲜数据。
  bool isFresh(Duration ttl) =>
      DateTime.now().difference(cachedAt) < ttl;

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

/// ZDBK 缓存 TTL 配置。
class CacheTtl {
  CacheTtl._();
  static const transcript = Duration(hours: 1);
  static const majorGrade = Duration(hours: 1);
  static const exams = Duration(hours: 1);
  static const courseOfferings = Duration(hours: 24);
  static const notifications = Duration(minutes: 30);
  static const trainingPlans = Duration(hours: 24);
  static const timetable = Duration(hours: 1);
  static const practiceScores = Duration(hours: 6);
}

/// Lightweight file-based cache database for ZDBK responses.
class WebCacheDatabase {
  static WebCacheDatabase? _instance;

  /// 同步获取已初始化的实例。在 [zdbkServiceInstanceProvider] 完成前为 null。
  static WebCacheDatabase? get instanceOrNull => _instance;

  late final String _cacheDir;

  WebCacheDatabase._(this._cacheDir);

  static Future<WebCacheDatabase> getInstance() async {
    if (_instance != null) return _instance!;
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = p.join(appDir.path, 'zdbk_cache');
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _instance = WebCacheDatabase._(cacheDir);
    return _instance!;
  }

  /// 缓存 API 响应（JSON 字符串）。
  Future<void> setCachedWebPage(String key, String jsonString) async {
    try {
      final entry = _CacheEntry(data: jsonString, cachedAt: DateTime.now());
      final file = File(p.join(_cacheDir, '$key.json'));
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (_) {}
  }

  /// 获取缓存——TTL 内新鲜。
  String? getCachedWebPage(String key) {
    return _getEntry(key)?.data;
  }

  /// 获取缓存——如果过期返回 null，否则返回数据。
  String? getFreshCachedWebPage(String key, Duration ttl) {
    final entry = _getEntry(key);
    if (entry == null) return null;
    return entry.isFresh(ttl) ? entry.data : null;
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

  /// 获取缓存 JSON 解码列表。
  List<dynamic> getCachedList(String key) {
    final cached = getCachedWebPage(key);
    if (cached == null || cached.isEmpty) return [];
    try {
      final decoded = jsonDecode(cached);
      if (decoded is List) return decoded;
    } catch (_) {}
    return [];
  }

  /// 获取缓存写入时间（供数据状态面板展示"上次更新时间"）。
  DateTime? getCacheTimestamp(String key) {
    return _getEntry(key)?.cachedAt;
  }

  /// 获取缓存原始条目（供 DataStatusManager 使用）。
  _CacheEntry? getEntry(String key) => _getEntry(key);

  /// 清除所有缓存。
  Future<void> clearAll() async {
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
}

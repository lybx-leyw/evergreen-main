import 'dart:convert';

/// In-memory TTL cache for ZJU API responses.
///
/// Ports the Map-based cache from electron/services/zju-api.js.
/// Each cached entry has a TTL (default 5 minutes) after which
/// it's considered stale but still returnable as fallback.
class CacheManager {
  final Map<String, _CacheEntry> _cache = {};
  final Duration defaultTtl;

  CacheManager({this.defaultTtl = const Duration(minutes: 5)});

  /// Get a cached value. Returns null if not cached.
  /// If expired, returns the stale value but marks it as expired.
  String? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    return entry.value;
  }

  /// Check if a key has a fresh (non-expired) cached value.
  bool isFresh(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    return !entry.isExpired;
  }

  /// Set a cached value with the default TTL.
  void set(String key, String value, {Duration? ttl}) {
    _cache[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl ?? defaultTtl),
    );
  }

  /// Set a cached value with a custom TTL in minutes.
  void setWithTtlMinutes(String key, String value, int minutes) {
    _cache[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(Duration(minutes: minutes)),
    );
  }

  /// Get parsed JSON from cache.
  dynamic getJson(String key) {
    final value = get(key);
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  /// Set JSON-serializable value.
  void setJson(String key, dynamic value, {Duration? ttl}) {
    set(key, jsonEncode(value), ttl: ttl);
  }

  /// Remove a cached entry.
  void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cached entries.
  void clear() {
    _cache.clear();
  }

  /// Get the number of cached entries.
  int get length => _cache.length;
}

class _CacheEntry {
  final String value;
  final DateTime expiresAt;

  _CacheEntry({required this.value, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

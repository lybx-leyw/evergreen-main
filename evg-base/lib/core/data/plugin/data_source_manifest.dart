/// 外部数据源清单模型——解析 manifest.json，声明 .exe 插件的数据类型。
///
/// # 公开 API
///
/// | 成员 | 说明 |
/// |------|------|
/// | `DataSourceManifest.fromJson(json)` | 从 JSON 解析；校验 `type == "data-source"` |
/// | `DataSourceManifest.fromJsonString(str)` | 从 JSON 字符串解析 |
/// | `DataSourceTypeDecl.fromJson(json)` | 从 JSON 解析 |
/// | `.toJson()` | 序列化回 JSON |
/// | `DataSourceManifest`: `id` / `name` / `process` / `preferredPort` / `dataTypes` | 清单字段 |
/// | `DataSourceTypeDecl`: `name` / `category` / `displayName` / `ttl` / `persistentKey` / `endpoint` | 类型字段 |
/// | `.toDataType()` | 转换为 [DataType] |
/// | `.buildUrl(port)` | 将 `{port}` 占位符替换为实际端口 |

import 'dart:convert';
import '../type.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceManifest
// ═══════════════════════════════════════════════════════════════════════════

/// 外部数据源插件清单。
class DataSourceManifest {
  final String id;
  final String name;
  final String process;
  final int preferredPort;
  final List<DataSourceTypeDecl> dataTypes;

  const DataSourceManifest({
    required this.id,
    required this.name,
    required this.process,
    this.preferredPort = 0,
    required this.dataTypes,
  });

  factory DataSourceManifest.fromJson(Map<String, dynamic> json) {
    _requireField(json, 'type', 'data-source');
    return DataSourceManifest(
      id: _require(json, 'id'),
      name: _require(json, 'name'),
      process: _require(json, 'process'),
      preferredPort: json['preferredPort'] as int? ?? 0,
      dataTypes: _requireList(json, 'dataTypes')
          .map((d) => DataSourceTypeDecl.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }

  factory DataSourceManifest.fromJsonString(String jsonString) =>
      DataSourceManifest.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'type': 'data-source',
        'id': id,
        'name': name,
        'process': process,
        'preferredPort': preferredPort,
        'dataTypes': dataTypes.map((d) => d.toJson()).toList(),
      };

  @override
  String toString() => 'DataSourceManifest($id, ${dataTypes.length} types)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceTypeDecl
// ═══════════════════════════════════════════════════════════════════════════

/// 单个数据类型声明。
class DataSourceTypeDecl {
  final String name;
  final String category;
  final String? displayName;
  final Duration ttl;
  final String? persistentKey;

  /// HTTP 接口路径。`{port}` 由 Loader 自动替换为实际端口。
  final String endpoint;

  const DataSourceTypeDecl({
    required this.name,
    this.category = '未分类',
    this.displayName,
    this.ttl = const Duration(minutes: 5),
    this.persistentKey,
    required this.endpoint,
  });

  factory DataSourceTypeDecl.fromJson(Map<String, dynamic> json) {
    return DataSourceTypeDecl(
      name: _require(json, 'name'),
      category: json['category'] as String? ?? '未分类',
      displayName: json['displayName'] as String?,
      ttl: _parseDuration(json['ttl']) ?? const Duration(minutes: 5),
      persistentKey: json['persistentKey'] as String?,
      endpoint: _require(json, 'endpoint'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'displayName': displayName,
        'ttl': _fmtDuration(ttl),
        'persistentKey': persistentKey,
        'endpoint': endpoint,
      };

  /// 转换为 DataOrchestrator 可用的 [DataType]。
  DataType<dynamic> toDataType() => DataType<dynamic>(
        name: name,
        category: category,
        displayName: displayName,
        ttl: ttl,
        persistentKey: persistentKey,
      );

  /// 用实际端口替换 `{port}` 占位符。
  String buildUrl(int port) => endpoint.replaceAll('{port}', '$port');

  @override
  String toString() =>
      'DataSourceTypeDecl($name → $endpoint, ttl: ${_fmtDuration(ttl)})';
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部
// ═══════════════════════════════════════════════════════════════════════════

String _require(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || (value is String && value.isEmpty)) {
    throw FormatException('缺少必填字段: $key');
  }
  return value as String;
}

void _requireField(Map<String, dynamic> json, String key, String expected) {
  final value = json[key] as String?;
  if (value != expected) {
    throw FormatException('$key 必须为 "$expected"，实际为: $value');
  }
}

List<dynamic> _requireList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.isEmpty) {
    throw FormatException('缺少必填字段: $key (需要非空数组)');
  }
  return value;
}

Duration? _parseDuration(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return Duration(seconds: raw);
  final s = raw.toString().trim();
  final m = RegExp(r'^(\d+)\s*(h|m|s|ms)$').firstMatch(s);
  if (m == null) {
    final secs = int.tryParse(s);
    return secs != null ? Duration(seconds: secs) : null;
  }
  final v = int.parse(m.group(1)!);
  return switch (m.group(2)) {
    'h' => Duration(hours: v),
    'm' => Duration(minutes: v),
    's' => Duration(seconds: v),
    'ms' => Duration(milliseconds: v),
    _ => null,
  };
}

String _fmtDuration(Duration d) {
  final sec = d.inMicroseconds ~/ Duration.microsecondsPerSecond;
  if (sec >= 3600 && sec % 3600 == 0) return '${sec ~/ 3600}h';
  if (sec >= 60 && sec % 60 == 0) return '${sec ~/ 60}m';
  if (sec > 0) return '${sec}s';
  return '${d.inMilliseconds}ms';
}

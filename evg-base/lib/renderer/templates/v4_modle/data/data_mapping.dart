/// 声明式数据字段映射 — 外部字段名 → 组件内部字段名。
///
/// 对应 HTML 生态中 "数据绑定声明" 层：外部 JSON 的 `course_name` 和组件内部的 `title`
/// 是通过显式映射关联的，而非硬编码在组件里。
library;

import 'normalized_data.dart';

/// 数据字段映射声明。
///
/// 示例：
/// ```dart
/// const courseMapping = DataMapping(
///   fieldMap: {
///     'course_name': 'title',   // 外部 'course_name' → 组件 'title'
///     'credit': 'body',
///     'teacher': 'subtitle',
///   },
///   targetKey: 'cards',
/// );
/// ```
class DataMapping {
  /// 外部字段名 → 组件内部字段名的映射表。空 Map = 不映射（透传）。
  final Map<String, String> fieldMap;

  /// 从 resolved 中取值的 JSON path（'' = 取根，'data' = resolved['data']）。
  final String sourcePath;

  /// 写入 config 的哪个 key（如 'cards', 'data', 'root'）。
  final String targetKey;

  /// resolved 为 null 时是否跳过（避免 null 覆盖静态配置）。
  final bool skipIfNull;

  /// resolved 为 Map 时是否**逐项合并**进 config（旧 mergeData 语义）。
  ///
  /// true：`{'value': '42', 'subtitle': 'x'}` → config 的 value/subtitle 分别注入
  /// （stat-tile 等 KPI 卡片）；false（默认）：整个 Map 作为整体注入 [targetKey]
  /// （tree 的根节点 map 注入 'root'、chart 的 series map 注入 'data' 等）。
  final bool mergeMap;

  const DataMapping({
    this.fieldMap = const {},
    this.sourcePath = '',
    this.targetKey = 'data',
    this.skipIfNull = true,
    this.mergeMap = false,
  });

  /// 应用字段映射：将行数据中的外部字段名替换为内部字段名。
  /// 未在 fieldMap 中声明的字段保留原字段名（透传）。
  List<Map<String, dynamic>> applyFieldMap(List<Map<String, dynamic>> rows) {
    if (fieldMap.isEmpty) return rows;
    return rows.map((row) {
      final mapped = <String, dynamic>{};
      for (final entry in row.entries) {
        final targetName = fieldMap[entry.key] ?? entry.key;
        mapped[targetName] = entry.value;
      }
      return mapped;
    }).toList();
  }

  /// 按点路径从 resolved 中取值。
  static dynamic resolvePath(dynamic obj, String path) {
    if (path.isEmpty) return obj;
    final segments = path.split('.');
    dynamic current = obj;
    for (final seg in segments) {
      if (current is Map) {
        current = current[seg];
      } else {
        return null;
      }
    }
    return current;
  }
}

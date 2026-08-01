/// 归一化数据结构 — 所有数据源经管道处理后统一为此形态。
///
/// 对应 HTML 生态中 "CSV/XML/API → JSON" 的统一中间格式层。
library;

/// 归一化后的数据结构。
class NormalizedData {
  /// 结构化形状。
  final DataShape shape;

  /// 标准化负载。
  final dynamic payload;

  /// 原始来源格式（调试/日志用）。
  final DataFormat? sourceFormat;

  const NormalizedData({required this.shape, required this.payload, this.sourceFormat});

  /// 是否为空/无数据。
  bool get isEmpty => payload == null || (payload is List && payload.isEmpty);

  /// payload 作为 List<Map>（仅 simpleList / table.rows 时有效）。
  List<Map<String, dynamic>> get asList {
    if (payload is List) {
      return (payload as List).whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  /// payload 作为 Map（仅 map/tree/labeledSeries 时有效）。
  Map<String, dynamic>? get asMap => payload is Map<String, dynamic> ? payload as Map<String, dynamic> : null;
}

/// 数据结构性形状 — 组件声明期望的形状。
enum DataShape {
  /// 行列表：[{...}, {...}] — 最常见，card-list / data-table 等
  simpleList,

  /// 表结构：{columns: [...], rows: [...]}
  table,

  /// 标量：42 / "hello" / null
  scalar,

  /// 树：{name, children: [...]}
  tree,

  /// 标签序列：{labels: [...], series: [{name, data: [...]}]}
  labeledSeries,

  /// 地理位置：{center: {lat, lng}, markers: [...]}
  geo,

  /// 未知/兜底
  unknown,
}

/// 数据来源格式（用于调试和归一化策略选择）。
enum DataFormat { json, csv, xml, text, unknown }

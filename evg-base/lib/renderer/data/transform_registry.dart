/// transform 转换注册表——把拉取到的原始数据规整为各展示组件可消费的标准形态。
///
/// 命名集中管理，新增转换函数统一在此登记（扩展点：插件可 [registerTransform]）。
/// 所有函数对异常输入均返回安全兜底（空集合 / 原样），不抛。
typedef TransformFn = dynamic Function(dynamic raw);

dynamic _toNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

final Map<String, TransformFn> transformRegistry = {
  /// 原样返回。
  'identity': (r) => r,

  /// 单值/单 Map → List；已是 List 则原样；其余 → 空 List。
  'toList': (r) => r is List
      ? r
      : (r is Map
          ? [r]
          : (r == null ? [] : [r])),

  /// → List<Map<String, dynamic>>（表格行）。
  'toRows': (r) {
    if (r is List) {
      return r.whereType<Map<String, dynamic>>().toList();
    }
    if (r is Map) return [r];
    return [];
  },

  /// → 标准图表结构 {labels: List<String>, series: List<Map>{name,data:List<num>}}。
  'toChart': (r) {
    if (r is Map && r['series'] is List) return r; // 已是标准结构
    if (r is List) {
      final labels = <String>[];
      final data = <num>[];
      for (final item in r) {
        if (item is Map) {
          labels.add((item['label'] ?? item['name'] ?? '').toString());
          data.add(_toNum(item['value'] ?? item['y'] ?? item['data']));
        }
      }
      return {
        'labels': labels,
        'series': [
          {'name': 'series', 'data': data}
        ],
      };
    }
    return {
      'labels': <String>[],
      'series': <Map<String, dynamic>>[],
    };
  },

  /// → {events: List<Map<String, dynamic>>}，每个事件至少含 date/title。
  'toCalendar': (r) {
    if (r is Map && r['events'] is List) return r; // 已是标准结构
    if (r is List) {
      return {
        'events': r.whereType<Map<String, dynamic>>().toList(),
      };
    }
    return {'events': <Map<String, dynamic>>[]};
  },
};

/// 应用命名转换；未知名称回退到 identity（不抛）。
dynamic applyTransform(String name, dynamic raw) {
  final fn = transformRegistry[name] ?? transformRegistry['identity']!;
  try {
    return fn(raw);
  } catch (_) {
    return raw; // 转换异常时保留原始数据，交由组件层兜底
  }
}

/// 扩展点：插件注册自定义转换。
void registerTransform(String name, TransformFn fn) {
  transformRegistry[name] = fn;
}

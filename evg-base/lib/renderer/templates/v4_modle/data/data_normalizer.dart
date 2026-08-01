/// 数据归一化管道 — 将任意形状/格式的原始数据归一化为 [NormalizedData]。
///
/// 对应 HTML 生态的 "PapaParse(CSV) / DOMParser(XML) / JSON.parse(API) → 统一对象" 层。
///
/// 组件不需要知道数据从哪里来——管道在组件之前完成格式检测和结构推断。
library;

import 'dart:convert';
import 'normalized_data.dart';

class DataNormalizer {
  /// 归一化入口：任意形状 → NormalizedData。
  static NormalizedData normalize(dynamic raw, {DataFormat? hint}) {
    if (raw == null) return const NormalizedData(shape: DataShape.unknown, payload: null);

    // 1. 字符串 → 可能是 CSV / XML / JSON 文本
    if (raw is String) return _normalizeString(raw, hint);

    // 2. 已经是解析后的集合 → 结构推断
    if (raw is List) return _inferList(raw);

    if (raw is Map<String, dynamic>) return _inferMap(raw);

    // 3. 标量
    return NormalizedData(shape: DataShape.scalar, payload: raw);
  }

  // ═══════ 字符串解析 ═══════

  static NormalizedData _normalizeString(String raw, DataFormat? hint) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const NormalizedData(shape: DataShape.unknown, payload: null);

    // CSV 检测
    if (hint == DataFormat.csv || _looksLikeCsv(trimmed)) {
      return _parseCsv(trimmed);
    }

    // XML 检测
    if (hint == DataFormat.xml || trimmed.startsWith('<')) {
      return _parseXml(trimmed);
    }

    // JSON 检测
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return normalize(jsonDecode(trimmed), hint: DataFormat.json);
      } catch (_) {}
    }

    // fallback: 纯文本 → scalar
    return NormalizedData(shape: DataShape.scalar, payload: raw, sourceFormat: DataFormat.text);
  }

  static bool _looksLikeCsv(String s) {
    final lines = s.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return false;
    final firstComma = lines[0].split(',').length;
    return firstComma > 1 && lines.every((l) => l.split(',').length == firstComma);
  }

  static NormalizedData _parseCsv(String raw) {
    final lines = raw.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return NormalizedData(shape: DataShape.simpleList, payload: []);
    final headers = lines[0].split(',').map((h) => h.trim()).toList();
    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final values = lines[i].split(',').map((v) => v.trim()).toList();
      final row = <String, dynamic>{};
      for (var j = 0; j < headers.length && j < values.length; j++) {
        row[headers[j]] = _tryParseNumber(values[j]);
      }
      rows.add(row);
    }
    return NormalizedData(shape: DataShape.simpleList, payload: rows, sourceFormat: DataFormat.csv);
  }

  static NormalizedData _parseXml(String raw) {
    // 最简 XML 解析：逐行提取 <item><key>val</key>...</item>
    final rows = <Map<String, dynamic>>[];
    final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final kvRegex = RegExp(r'<(\w+)>(.*?)</\w+>', dotAll: true);
    for (final m in itemRegex.allMatches(raw)) {
      final row = <String, dynamic>{};
      for (final kv in kvRegex.allMatches(m.group(1)!)) {
        row[kv.group(1)!] = _tryParseNumber(kv.group(2)!.trim());
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isNotEmpty) {
      return NormalizedData(shape: DataShape.simpleList, payload: rows, sourceFormat: DataFormat.xml);
    }
    return NormalizedData(shape: DataShape.scalar, payload: raw, sourceFormat: DataFormat.xml);
  }

  // ═══════ 结构推断 ═══════

  static NormalizedData _inferList(List raw) {
    if (raw.isEmpty) return NormalizedData(shape: DataShape.simpleList, payload: raw);
    if (raw.first is Map) return NormalizedData(shape: DataShape.simpleList, payload: raw);
    return NormalizedData(shape: DataShape.unknown, payload: raw);
  }

  static NormalizedData _inferMap(Map<String, dynamic> raw) {
    // {labels, series} → labeledSeries
    if (raw.containsKey('labels') && raw.containsKey('series')) {
      return NormalizedData(shape: DataShape.labeledSeries, payload: raw);
    }
    // {columns, rows} → table
    if (raw.containsKey('columns') && raw.containsKey('rows')) {
      return NormalizedData(shape: DataShape.table, payload: raw);
    }
    // {name, children} → tree
    if (raw.containsKey('children')) {
      return NormalizedData(shape: DataShape.tree, payload: raw);
    }
    // {center} → geo
    if (raw.containsKey('center')) {
      return NormalizedData(shape: DataShape.geo, payload: raw);
    }
    // 常见包装键 → 解包
    for (final key in ['items', 'data', 'rows', 'results']) {
      if (raw[key] is List) {
        return NormalizedData(shape: DataShape.simpleList, payload: raw[key]);
      }
    }
    return NormalizedData(shape: DataShape.scalar, payload: raw);
  }

  // ═══════ 辅助 ═══════

  /// 尝试将字符串解析为数字，失败则保留原字符串。
  static dynamic _tryParseNumber(String s) {
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    return d ?? s;
  }
}

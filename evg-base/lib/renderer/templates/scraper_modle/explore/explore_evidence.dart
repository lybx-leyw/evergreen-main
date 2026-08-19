/// 探索数据源证据绑定（P0-2 · Evidence → CandidateDataSource）。
///
/// 移植自 reverse-skill evidence-finding-path.md：候选数据源的 url 必须能在
/// 捕获日志中找到来源（正面证明）；每个字段可附响应 JSON 路径证据
/// （sourceJsonPath），注册前逐条校验。
///
/// 判定规则（2026-08-18 放宽）：
/// - **仅警告**：数据源 url 无任何捕获日志匹配 → 不阻断，仅提示；
///   数据分类交给 AI 自主，不强制要求 GET 日志证据。
/// - **仅警告**：字段 sourceJsonPath 解析失败 / 未标注 / 字段与源引用日志
///   不一致 → 不阻断，在输出中列出供 AI 修正。
///
/// 纯 Dart 无 Flutter 依赖，可独立单测。
library explore_evidence;

import 'dart:convert';

import '../workflow/scraper_workflow.dart';
import 'explore_workflow.dart';

// ═══════ JSON Path 求值器（本仓库无可复用实现，P0-2 自带）══════

/// JSON Path 解析结果。
class JsonPathResult {
  final bool found;
  final List<dynamic> values;
  final String? error;

  const JsonPathResult({
    required this.found,
    this.values = const [],
    this.error,
  });

  /// 首个命中值（无命中为 null）。
  dynamic get first => found && values.isNotEmpty ? values.first : null;
}

/// 求值受限 JSON Path：$ 根、.key、['key']/["key"]、[i]、[*]。
///
/// 约束：
/// - 通配段 [*] 仅支持出现在路径末尾（中段 fan-out 不支持，会报语法错误）；
/// - 下标仅非负整数；
/// - 容错：非法 path / 中间节点缺失 / root 非 JSON 容器 → found=false + error，
///   永不抛异常（供守卫层直接消费）。
JsonPathResult resolveJsonPath(dynamic root, String path) {
  try {
    final segments = _parseJsonPath(path);
    if (segments == null) {
      return JsonPathResult(found: false, error: 'JSON 路径语法非法: "\$path"');
    }
    var current = root;
    for (final seg in segments) {
      if (seg is _KeySeg) {
        if (current is Map) {
          current = current.containsKey(seg.key) ? current[seg.key] : _missing;
        } else if (current is List) {
          final idx = int.tryParse(seg.key);
          if (idx == null) {
            return JsonPathResult(
                found: false,
                error: '路径段 ".${seg.key}" 不可达（当前是数组，仅支持数字下标）');
          }
          if (idx < 0 || idx >= current.length) {
            return JsonPathResult(
                found: false, error: '索引 $idx 越界（数组长度 ${current.length}）');
          }
          current = current[idx];
        } else {
          return JsonPathResult(
              found: false,
              error: '路径段 ".${seg.key}" 不可达（当前节点既非对象也非数组）');
        }
      } else if (seg is _IndexSeg) {
        if (current is! List) {
          return JsonPathResult(
              found: false, error: '下标段不可达（当前节点不是数组）');
        }
        if (seg.index < 0 || seg.index >= current.length) {
          return JsonPathResult(
              found: false,
              error: '索引 ${seg.index} 越界（数组长度 ${current.length}）');
        }
        current = current[seg.index];
      } else if (seg is _WildcardSeg) {
        if (current is List) {
          // 末尾通配：命中值 = 数组元素集合（空数组也视为存在）
        } else if (current is Map) {
          current = current.values.toList();
        } else {
          return JsonPathResult(
              found: false, error: '通配段不可达（当前节点不是容器）');
        }
      }
    }
    if (identical(current, _missing)) {
      return JsonPathResult(found: false, error: '路径 "\$path" 对应键不存在');
    }
    final lastIsWildcard =
        segments.isNotEmpty && segments.last is _WildcardSeg;
    if (lastIsWildcard && current is List) {
      return JsonPathResult(found: true, values: List<dynamic>.of(current));
    }
    return JsonPathResult(found: true, values: [current]);
  } catch (e) {
    return JsonPathResult(found: false, error: '路径求值异常: $e');
  }
}

/// 缺失值哨兵（与真实 null 区分：键不存在 vs 键存在但值为 null）。
const Object _missing = Object();

sealed class _Seg {
  const _Seg();
}

class _KeySeg extends _Seg {
  final String key;
  const _KeySeg(this.key);
}

class _IndexSeg extends _Seg {
  final int index;
  const _IndexSeg(this.index);
}

class _WildcardSeg extends _Seg {
  const _WildcardSeg();
}

/// 解析受限 JSON Path；非法返回 null。
List<_Seg>? _parseJsonPath(String raw) {
  final p = raw.trim();
  if (p.isEmpty || !p.startsWith(r'$')) return null;
  var i = 1;
  final segs = <_Seg>[];
  while (i < p.length) {
    final c = p[i];
    if (c == '.') {
      if (i + 1 >= p.length) return null;
      if (p[i + 1] == '*') {
        segs.add(const _WildcardSeg());
        i += 2;
        continue;
      }
      final start = i + 1;
      var j = start;
      while (j < p.length && p[j] != '.' && p[j] != '[') {
        j++;
      }
      if (j == start) return null; // 空 key
      segs.add(_KeySeg(p.substring(start, j)));
      i = j;
    } else if (c == '[') {
      final close = p.indexOf(']', i + 1);
      if (close < 0) return null;
      final inner = p.substring(i + 1, close).trim();
      if (inner == '*') {
        segs.add(const _WildcardSeg());
      } else if (inner.length >= 2 &&
          ((inner.startsWith("'") && inner.endsWith("'")) ||
              (inner.startsWith('"') && inner.endsWith('"')))) {
        segs.add(_KeySeg(inner.substring(1, inner.length - 1)));
      } else if (RegExp(r'^\d+$').hasMatch(inner)) {
        segs.add(_IndexSeg(int.parse(inner)));
      } else {
        return null;
      }
      i = close + 1;
    } else {
      return null;
    }
  }
  // 通配仅允许作为末尾段（中段 fan-out 不支持 → 语法错误，防歧义）
  for (var k = 0; k < segs.length - 1; k++) {
    if (segs[k] is _WildcardSeg) return null;
  }
  return segs;
}

// ═══════ 证据校验 ═══════

/// 字段级证据校验结果。
class FieldEvidenceCheck {
  final CandidateField field;

  /// path 是否在响应体中解析成功（true = 正面证据成立）。
  final bool verified;

  /// 未通过时的说明（verified=true 时为空）。
  final String? message;

  const FieldEvidenceCheck({
    required this.field,
    required this.verified,
    this.message,
  });
}

/// 数据源证据校验结果。
class EvidenceCheckResult {
  final CandidateDataSource source;

  /// url 是否匹配到捕获日志（硬阻断判据）。
  final bool urlMatched;

  /// 匹配到的日志（用于 UI 徽标/调试展示）。
  final HttpRequestLog? matchedLog;

  /// 逐字段校验结果。
  final List<FieldEvidenceCheck> fieldChecks;

  /// 硬阻断原因（非空 → 拒绝呈现/注册）。
  final List<String> errors;

  /// 不阻断的警告（回灌 AI 修正，但不拒绝）。
  final List<String> warnings;

  const EvidenceCheckResult({
    required this.source,
    required this.urlMatched,
    this.matchedLog,
    this.fieldChecks = const [],
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hardBlocked => errors.isNotEmpty;
}

/// 校验候选数据源的捕获日志证据（P0-2 正面证明，现已放宽为「仅警告」）。
///
/// 规则（放宽后）：
/// 1. url 证据：优先 [CandidateDataSource.sourceLogId] 精确引用；引用失效时按
///    URL 匹配兜底（scheme+host+path 归一，忽略 query/fragment——接口身份与
///    分页参数无关）。两者都失败 → **仅警告，不阻断**（数据分类交给 AI 自主，
///    不强制要求 GET 日志证据）。
/// 2. 字段证据：每个字段的 [CandidateField.sourceJsonPath] 在匹配日志响应体
///    中解析；失败/未标注/引用不一致 → 仅警告（不阻断）。
EvidenceCheckResult validateDataSourceEvidence(
  CandidateDataSource source,
  List<HttpRequestLog> logs,
) {
  final errors = <String>[];
  final warnings = <String>[];
  final fieldChecks = <FieldEvidenceCheck>[];

  // ── 1) url 证据（放宽：无匹配仅警告，不 hardBlocked）──
  HttpRequestLog? matched;
  final ref = source.sourceLogId;
  if (ref != null && ref.isNotEmpty) {
    for (final l in logs) {
      // 证据可来自任意方法（GET/POST/NAVIGATION…）：数据分类由 AI 自主判断，
      // 不强制要求 GET。仅按证据 id 匹配。
      if (l.id.isNotEmpty && sameLogRef(l.id, ref)) {
        matched = l;
        break;
      }
    }
    if (matched == null) {
      warnings.add('sourceLogId "$ref" 未在捕获日志中找到，已按 URL 匹配兜底');
    }
  }
  if (matched == null) {
    final target = _normEvidenceUrl(source.url);
    for (final l in logs) {
      if (_normEvidenceUrl(l.url) == target) {
        matched = l;
        break;
      }
    }
  }
  if (matched == null) {
    warnings.add('URL ${source.url} 无捕获日志证据'
        '（list_captured_requests 中不存在对应请求）。'
        '已放行：数据分类由 AI 自主判断，非 GET 或无日志也允许归类，'
        '仅需确保 scraper.py 非硬编码数据。');
  }

  // ── 2) 字段 path 证据（仅警告，不阻断）──
  dynamic resp;
  var respParsed = false;
  String? respError;
  final body = matched?.responseBody;
  if (body != null && body.trim().isNotEmpty) {
    try {
      resp = jsonDecode(body);
      respParsed = true;
    } catch (e) {
      respError = '响应体不是合法 JSON（$e）';
    }
  } else {
    respError = '对应日志未捕获响应体';
  }

  for (final f in source.fields) {
    final fPath = f.sourceJsonPath;
    if (fPath == null || fPath.isEmpty) {
      fieldChecks.add(FieldEvidenceCheck(
        field: f,
        verified: false,
        message: '未标注 sourceJsonPath（响应 JSON 路径证据）',
      ));
      warnings.add('字段 ${f.name} 未标注 sourceJsonPath，无法正面验证来源');
      continue;
    }
    if (!respParsed) {
      fieldChecks.add(FieldEvidenceCheck(
          field: f, verified: false, message: respError!));
      warnings.add('字段 ${f.name} 路径无法验证：$respError');
      continue;
    }
    final r = resolveJsonPath(resp, fPath);
    if (!r.found) {
      fieldChecks.add(FieldEvidenceCheck(
        field: f,
        verified: false,
        message: '路径 $fPath 解析失败${r.error != null ? '（${r.error}）' : ''}',
      ));
      warnings.add(
          '字段 ${f.name} 路径 $fPath 在响应体中解析失败（警告，不阻断注册）');
      continue;
    }
    fieldChecks.add(FieldEvidenceCheck(field: f, verified: true));
    // 字段级引用与源级引用不一致 → 证据链混乱提示
    final fRef = f.sourceLogId;
    if (fRef != null && fRef.isNotEmpty && ref != null && ref.isNotEmpty &&
        !sameLogRef(fRef, ref)) {
      warnings.add('字段 ${f.name} 引用日志 $fRef 与数据源引用 $ref 不一致');
    }
  }

  return EvidenceCheckResult(
    source: source,
    urlMatched: matched != null,
    matchedLog: matched,
    fieldChecks: fieldChecks,
    warnings: warnings,
  );
}

/// 归一化日志引用（log-7 / log#7 / #7 / 7 → log-7），供 AI 引用与 id 匹配。
String normalizeLogRef(String ref) {
  final t = ref.trim().toLowerCase();
  var core = t;
  if (core.startsWith('log')) {
    core = core.substring(3);
    if (core.startsWith('-') ||
        core.startsWith('#') ||
        core.startsWith(':') ||
        core.startsWith('_')) {
      core = core.substring(1);
    }
  } else if (core.startsWith('#')) {
    core = core.substring(1);
  }
  if (RegExp(r'^\d+$').hasMatch(core)) return 'log-$core';
  return t;
}

/// 两条日志引用是否指向同一日志（归一化后比较）。
bool sameLogRef(String a, String b) => normalizeLogRef(a) == normalizeLogRef(b);

/// 证据 URL 归一：小写 scheme+host+path，忽略 query/fragment（接口身份与分页
/// 参数无关；path 才是数据源身份的判据）。
String _normEvidenceUrl(String url) {
  try {
    final u = Uri.parse(url.trim());
    return u.replace(query: '', fragment: '').toString().toLowerCase();
  } catch (_) {
    return url.trim().toLowerCase();
  }
}

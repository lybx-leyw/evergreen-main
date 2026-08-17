/// 探索经验 Journal 回写（P1-2 · field-journal，移植自 reverse-skill）。
///
/// 生成插件成功后，把「域名 + 认证方式 + 关键流程 + 坑」写入
/// `.greenix/scraper_journal/{domain}.json`；新会话启动探索时注入最近经验摘要，
/// 避免同类站点（CAS 登录、RSA 加密参数）从零开始。
///
/// 设计约束（生产级）：
/// - 纯 Dart + dart:io，无 Flutter 依赖（目录路径由调用方注入，可独立单测）；
/// - 每域名最多保留 [maxEntriesPerDomain] 条（防膨胀）；
/// - 损坏文件/读写失败一律容错（读→null/跳过，写→告警不抛）；
/// - 域名 sanitize 防路径穿越。
library scraper_journal;

import 'dart:convert';
import 'dart:io';

import '../workflow/scraper_workflow.dart';

// ═══════ 经验条目模型 ═══════

/// 单条站点探索经验（field-journal 条目）。
class JournalEntry {
  /// 站点域名（探索锁定的 baseHost，如 zju.edu.cn）。
  final String domain;

  /// 认证方式（token / cookie 登录 / 无认证…）。
  final String authMethod;

  /// 关键流程摘要（探索页数 / 构建数据源 / 验证结果）。
  final String flow;

  /// 踩坑记录（上次的失败/警告，供下次规避）。
  final String pitfalls;

  /// 关键参数名（加密参数 / 关键 query key 等）。
  final List<String> keyParams;

  /// 记录时间。
  final DateTime recordedAt;

  const JournalEntry({
    required this.domain,
    this.authMethod = '',
    this.flow = '',
    this.pitfalls = '',
    this.keyParams = const [],
    required this.recordedAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
    domain: (json['domain'] as String? ?? '').trim(),
    authMethod: (json['authMethod'] as String? ?? '').trim(),
    flow: (json['flow'] as String? ?? '').trim(),
    pitfalls: (json['pitfalls'] as String? ?? '').trim(),
    keyParams: (json['keyParams'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'authMethod': authMethod,
    'flow': flow,
    'pitfalls': pitfalls,
    'keyParams': keyParams,
    'recordedAt': recordedAt.toIso8601String(),
  };

  /// 注入探索 prompt 的经验摘要（运行时注入，不硬编码案例）。
  String toPromptSummary() {
    final buf = StringBuffer()
      ..writeln('本域历史经验（${recordedAt.toIso8601String().substring(0, 10)}）：')
      ..writeln('- 认证方式：${authMethod.isEmpty ? '（未记录）' : authMethod}')
      ..writeln('- 关键流程：${flow.isEmpty ? '（未记录）' : flow}');
    if (keyParams.isNotEmpty) {
      buf.writeln('- 关键参数：${keyParams.join(', ')}');
    }
    if (pitfalls.isNotEmpty) {
      buf.writeln('- 上次踩坑：$pitfalls');
    }
    buf.writeln('经验仅供参考：本次探索仍需按完整流程验证。');
    return buf.toString();
  }
}

// ═══════ Journal 存储 ═══════

/// 探索经验 Journal（按域名一个 JSON 文件，文件内按时间倒序）。
class ScraperJournal {
  /// 存储目录（生产由 UI 层注入 `.greenix/scraper_journal`；测试注入临时目录）。
  final String baseDir;

  /// 每域名最多保留条目数（防膨胀）。
  final int maxEntriesPerDomain;

  ScraperJournal({required this.baseDir, this.maxEntriesPerDomain = 5});

  /// 读取某域名最近一条经验；无记录/损坏 → null。
  Future<JournalEntry?> loadLatest(String domain) async {
    final entries = await _loadDomain(domain);
    return entries.isEmpty ? null : entries.first;
  }

  /// 列出全部经验（跨域名，按记录时间倒序）。
  Future<List<JournalEntry>> listAll() async {
    final dir = Directory(baseDir);
    if (!dir.existsSync()) return const [];
    final out = <JournalEntry>[];
    try {
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final parsed = _tryParseFile(f);
        if (parsed != null) out.addAll(parsed);
      }
    } catch (_) {
      return const [];
    }
    out.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  /// 追加一条经验（自动建目录；写失败仅告警不抛）。
  Future<void> append(JournalEntry entry) async {
    if (entry.domain.trim().isEmpty) return;
    try {
      final dir = Directory(baseDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(_domainFile(entry.domain));
      final existing = _tryParseFile(file) ?? <JournalEntry>[];
      existing.removeWhere((e) => e.recordedAt == entry.recordedAt); // 去重
      existing.insert(0, entry);
      existing.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      final capped = existing.take(maxEntriesPerDomain).toList();
      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(capped.map((e) => e.toJson()).toList()));
    } catch (e) {
      // 只读文件系统/磁盘满等：journal 是经验增强，绝不阻断主流程
      stderr.writeln('[ScraperJournal] ⚠ append 失败（忽略）: $e');
    }
  }

  /// 读某域名文件（新→旧排序；损坏 → 空）。
  Future<List<JournalEntry>> _loadDomain(String domain) async {
    if (domain.trim().isEmpty) return const [];
    final entries = _tryParseFile(File(_domainFile(domain))) ?? const [];
    return List.of(entries);
  }

  /// 解析一个 journal 文件；损坏/格式不对 → null。
  List<JournalEntry>? _tryParseFile(File f) {
    try {
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! List) return null;
      final entries = raw.whereType<Map<String, dynamic>>()
          .map(JournalEntry.fromJson)
          .where((e) => e.domain.isNotEmpty)
          .toList();
      entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return entries;
    } catch (_) {
      return null;
    }
  }

  /// 域名 → 文件名（sanitize 防路径穿越：仅保留 [a-z0-9._-]，压平 ..）。
  String _domainFile(String domain) {
    final safe = domain.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '_')
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'^[.]+'), '');
    final name = safe.isEmpty ? 'unknown' : safe;
    return '$baseDir${Platform.pathSeparator}$name.json';
  }
}

// ═══════ 经验自动提取（从捕获日志，不依赖新一轮 AI 调用）══════

/// 从捕获日志 headers 推断认证方式。
String inferAuthMethod(List<HttpRequestLog> logs) {
  var hasToken = false;
  var hasCookie = false;
  for (final l in logs) {
    final h = l.headers;
    if (h == null) continue;
    for (final k in h.keys) {
      final lower = k.toLowerCase();
      if (lower == 'authorization' || lower == 'x-api-key') hasToken = true;
      if (lower == 'cookie' || lower == 'set-cookie') hasCookie = true;
    }
  }
  if (hasToken && hasCookie) return 'token + cookie' ;
  if (hasToken) return 'token';
  if (hasCookie) return 'cookie 登录';
  return '无认证';
}

/// 从同域 GET 日志的 query 提取关键参数名（去重、最多 [cap] 个）。
List<String> inferKeyParams(List<HttpRequestLog> logs,
    {String? domain, int cap = 20}) {
  final keys = <String>{};
  for (final l in logs) {
    if (l.method != 'GET') continue;
    final uri = Uri.tryParse(l.url);
    if (uri == null) continue;
    if (domain != null && domain.isNotEmpty) {
      final host = uri.host.toLowerCase();
      if (host != domain.toLowerCase() && !host.endsWith('.$domain')) continue;
    }
    keys.addAll(uri.queryParameters.keys);
  }
  final out = keys.toList();
  out.sort();
  return out.take(cap).toList();
}

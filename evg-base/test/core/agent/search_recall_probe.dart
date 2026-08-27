// 搜索召回测试探针（Task 二 A2 交付物 3 + R2 多来源召回 mode 维度）
//
// 用途：debug 探针——观察 AI 助手搜索工具对「全面 / 专业 / 可靠 / 时效」四类
// 关键词的召回质量。按 Task 二评估方式，本文件**不 assert 任何值**，不会
// fail/pass，输出仅供人工观察并对搜索工具做多轮迭代。
//
// 运行（需在可联网环境；沙盒 / 离线环境所有请求会失败并打印失败原因，属预期）：
//   cd evg-base
//   dart run test/core/agent/search_recall_probe.dart
//
// 说明：
//   - 预设 4 类关键词（全面 / 专业 / 可靠 / 时效），可按需修改 [keywords] 列表；
//   - 每个关键词依次调用 web_search(max_results: 8) / arxiv_search /
//     github_search / crossref_search，以及 web_search(mode: all, max_results: 6)
//     三合一召回（Task 二 R2 新增 mode 维度，真实 HTTP，无需任何 API Key）；
//   - 打印：召回条目数、来源域名分布、每条标题 + URL、失败原因。
//   - 注意 GitHub 未认证 API 限流 60 次/小时，连续跑多次探针可能触发限流。
//   - 实测提示：GitHub 仓库搜索对中文自然语言 query 几乎零命中（如
//     「Flutter 状态管理最佳实践 2025」→ total_count:0，工具本身正常）；
//     评估 github_search 时建议改用英文/技术专名（如 'flutter state
//     management'、'function calling'）或直接在 keywords 里按源定制关键词。
// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:evergreen_base/core/agent/tools/research_search.dart';
import 'package:evergreen_base/core/agent/tools/web_search.dart';

/// 预设 4 类关键词（覆盖「全面 / 专业 / 可靠 / 时效」），可按需修改。
const List<String> keywords = [
  'Flutter 状态管理最佳实践 2025', // 全面：通用技术话题，期望多源召回
  'LLM function calling 论文 arxiv', // 专业：学术检索，期望 arXiv/Crossref 命中
  'OpenAI reasoning_effort API 官方文档', // 可靠：权威站点（openai.com 等）
  '今天 AI 行业新闻', // 时效：热点新闻（可改为具体热点事件）
];

void main() async {
  final webSearch = WebSearchTool(Dio());
  final arxiv = ArxivSearchTool(Dio());
  final github = GithubSearchTool(Dio());
  final crossref = CrossrefSearchTool(Dio());

  print('搜索召回探针 — ${keywords.length} 类关键词 × 5 个检索维度（真实 HTTP）');
  print('维度：web_search / arxiv_search / github_search / crossref_search / '
      'web_search(mode: all 三合一)');
  print('结果仅供人工观察迭代，不判 pass/fail。\n');

  for (var i = 0; i < keywords.length; i++) {
    final q = keywords[i];
    print('═' * 72);
    print('关键词 ${i + 1}/${keywords.length}：「$q」');
    print('═' * 72);
    await _probe('web_search', () => webSearch.execute({'query': q, 'max_results': 8}));
    await _probe('arxiv_search', () => arxiv.execute({'query': q}));
    await _probe('github_search', () => github.execute({'query': q}));
    await _probe('crossref_search', () => crossref.execute({'query': q}));
    // Task 二 R2：mode=all 三合一召回（max_results=6 → 网络 2 / arxiv 2 / github 2）
    await _probe('web_search(all)', () => webSearch.execute({'query': q, 'max_results': 6, 'mode': 'all'}));
    print('');
  }
  print('═' * 72);
  print('探针完成。请结合召回统计评估搜索能力，并按需迭代关键词 / 工具 / 提示词。');
}

/// 单工具探测：执行 → 解析 → 打印召回统计与明细。
Future<void> _probe(String toolName, Future<String> Function() run) async {
  final sw = Stopwatch()..start();
  String raw;
  try {
    raw = await run();
  } catch (e) {
    print('[$toolName] 调用异常（${sw.elapsedMilliseconds}ms）: $e');
    return;
  }
  sw.stop();

  final (entries, failure) = _parseOutput(toolName, raw);
  if (failure != null) {
    print('[$toolName] 失败（${sw.elapsedMilliseconds}ms）: $failure');
    return;
  }

  // 来源域名分布
  final domains = <String, int>{};
  for (final (_, url) in entries) {
    final host = _hostOf(url);
    if (host.isNotEmpty) domains[host] = (domains[host] ?? 0) + 1;
  }
  final domainSummary = domains.entries
      .map((d) => '${d.key}×${d.value}')
      .join(' ')
      .padRight(60)
      .substring(0, 60);
  print('[$toolName] 召回 ${entries.length} 条（${sw.elapsedMilliseconds}ms）| '
      '域名分布: $domainSummary');
  for (final (title, url) in entries) {
    print('  - $title');
    if (url.isNotEmpty) print('    $url');
  }
}

/// 解析工具输出 → (标题+URL 条目列表, 失败原因?)。失败原因非 null 表示调用失败。
(List<(String, String)>, String?) _parseOutput(String toolName, String raw) {
  // 失败文本（web_search 的 [搜索失败: ...] 与专业工具的 [error: ...]）
  if (raw.startsWith('[') && (raw.contains('失败') || raw.contains('error'))) {
    return (const [], raw.trim());
  }
  if (toolName == 'web_search' || toolName == 'web_search(all)') {
    // 成功格式：搜索 "q" 的结果:\n\n条目1\n\n条目2...
    // mode=all 条目带 [网络]/[arxiv]/[github] 来源标记（Task 二 R2），展示时剥离。
    final parts = raw.split('\n\n');
    final entries = <(String, String)>[];
    for (final part in parts.skip(1)) {
      final lines = part.trim().split('\n');
      if (lines.isEmpty || lines.first.isEmpty) continue;
      final title = lines.first
          .trim()
          .replaceFirst(RegExp(r'^\[(网络|arxiv|github)\] '), '');
      final urlLine =
          lines.where((l) => l.trim().startsWith('http')).firstOrNull ?? '';
      entries.add((title, urlLine.trim()));
    }
    return (entries, null);
  }
  // arxiv / github / crossref：结构化 JSON（{"source":..., "results": [...]}）
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return (const [], '输出不是 JSON 对象');
    final results = decoded['results'];
    if (results is! List) return (const [], 'JSON 缺少 results 数组');
    final entries = <(String, String)>[];
    for (final r in results) {
      if (r is! Map) continue;
      final title = (r['title'] ?? r['name'] ?? '').toString();
      final url = (r['url'] ?? r['pdf'] ?? '').toString();
      if (title.isEmpty && url.isEmpty) continue;
      entries.add((title, url));
    }
    return (entries, null);
  } catch (e) {
    return (const [], 'JSON 解析失败: $e');
  }
}

/// 从 URL 提取域名（与 web_search 结果条目的「来源」同源逻辑）。
String _hostOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '';
  return uri.host;
}

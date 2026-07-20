/// AI 网络调研工具。
///
/// 封装 web_search 工具结果的解析与格式化，
/// 将原始搜索结果转化为带引用链接的 [TechEvidence] 条目。
///
/// 对应验收标准 #3："AI 调研引用来源（web_search 结果带链接）"
library;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_document.dart';

/// 单条网络调研结果。
class WebResearchItem {
  /// 结果标题。
  final String title;

  /// 摘要/片段文本。
  final String snippet;

  /// 来源 URL（可能为空）。
  final String url;

  const WebResearchItem({
    required this.title,
    required this.snippet,
    required this.url,
  });

  /// 转换为 [TechEvidence]。
  TechEvidence toEvidence() => TechEvidence(
        source: title,
        content: snippet,
        url: url.isNotEmpty ? url : null,
      );

  bool get hasUrl => url.isNotEmpty;

  @override
  String toString() => 'WebResearchItem(title: $title, url: $url)';
}

/// AI 网络调研引擎。
///
/// 负责：
/// 1. 解析 web_search 工具返回的原始文本为结构化条目
/// 2. 从技术文档中提取关键词构造搜索查询
/// 3. 将调研结果格式化为可注入 prompt 的引用块
/// 4. 将调研结果转换为 [TechEvidence] 列表
class AiWebResearch {
  AiWebResearch._();

  // ═══════ 解析：原始 web_search 输出 → WebResearchItem ═══════

  /// 从 web_search 工具的原始输出字符串中提取搜索结果。
  ///
  /// 解析格式（Bing 搜索结果）：
  /// ```
  /// 搜索 "查询词" 的结果:
  ///
  /// 结果标题1
  ///   摘要文本1
  ///   https://url1.com
  ///
  /// 结果标题2
  ///   摘要文本2
  ///   https://url2.com
  /// ```
  ///
  /// 也兼容失败格式（返回空列表）。
  static List<WebResearchItem> parseSearchOutput(String raw) {
    if (raw.isEmpty) return [];

    final items = <WebResearchItem>[];
    final lines = raw.split('\n');
    int i = 0;

    // 跳过头部 "搜索 xxx 的结果:"
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('搜索 ') && trimmed.endsWith('的结果:')) {
        i++;
        break;
      }
      i++;
    }
    // 如果没找到 header，从头开始
    if (i >= lines.length && raw.contains('的结果:')) {
      i = 0;
    }

    // 跳过 header 后的空行
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    // 逐块解析
    while (i < lines.length) {
      final item = _parseOneResult(lines, i);
      if (item == null) {
        i++;
        continue;
      }
      items.add(item.result);
      i = item.nextIndex;

      // 跳过块间空行
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
    }

    return items;
  }

  /// 解析单条搜索结果。
  ///
  /// 返回解析后的结果和下一个解析起点索引；
  /// 失败时返回 null。
  static _ParseResult? _parseOneResult(List<String> lines, int startIndex) {
    int i = startIndex;
    if (i >= lines.length) return null;

    // ── 第 1 行：标题 ──
    final title = lines[i].trim();
    if (title.isEmpty || title.startsWith('搜索 ') || title.startsWith('[')) {
      return null;
    }
    i++;

    // ── 缩进行：摘要 ──
    final snippetBuf = StringBuffer();
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      // URL 行标记摘要结束
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        break;
      }
      // 下一结果标题行（非空、非缩进、非搜索头）
      if (trimmed.isNotEmpty && !line.startsWith('  ') && !trimmed.startsWith('搜索 ')) {
        break;
      }
      // 错误行
      if (trimmed.startsWith('[') && (trimmed.contains('error') || trimmed.contains('失败'))) {
        break;
      }

      if (line.startsWith('  ')) {
        snippetBuf.writeln(trimmed);
      }
      i++;
    }

    final snippet = snippetBuf.toString().trim();

    // ── URL 行 ──
    String url = '';
    if (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        url = trimmed;
        i++;
      }
    }

    if (title.isEmpty || snippet.isEmpty) return null;

    return _ParseResult(
      WebResearchItem(title: title, snippet: snippet, url: url),
      i,
    );
  }

  // ═══════ 查询构造 ═══════

  /// 从文档内容提取技术关键词并构造搜索查询。
  ///
  /// 查询策略：
  /// 1. 检测库名/框架名 → 查询方案与最佳实践
  /// 2. 检测架构关键词 → 查询架构设计参考
  /// 3. 检测 perf/security → 查询优化与安全
  static List<String> buildResearchQueries(String docContent) {
    if (docContent.trim().isEmpty) return [];

    final queries = <String>[];
    final lower = docContent.toLowerCase();

    // 常用技术栈关键词
    const techKeywords = [
      'flutter', 'react', 'vue', 'angular', 'svelte',
      'django', 'spring', 'express', 'fastapi', 'gin',
      'websocket', 'grpc', 'graphql', 'rest', 'trpc',
      'postgresql', 'mysql', 'mongodb', 'redis', 'sqlite',
      'docker', 'kubernetes', 'k8s', 'aws', 'azure', 'gcp',
      'oauth', 'jwt', 'sso', 'ldap', 'oidc',
      'microservice', 'serverless', 'event-driven', 'cqrs',
      'riverpod', 'bloc', 'provider', 'redux', 'mobx',
      'riverpod', 'getx',
    ];

    final found = techKeywords.where((t) => lower.contains(t)).toList();
    // 去重：gradle vs groovy 等
    final unique = <String>{};
    for (final t in found) {
      if (unique.every((u) => !t.contains(u) && !u.contains(t))) {
        unique.add(t);
      }
    }
    final selected = unique.toList();

    // 查询 1：技术方案 + 最佳实践
    if (selected.isNotEmpty) {
      final terms = selected.take(3).join(' ');
      queries.add('$terms 技术方案 最佳实践 2025');
    }

    // 查询 2：对比选型
    if (selected.length >= 2) {
      queries.add('${selected[0]} vs ${selected[1]} 技术选型 对比');
    }

    // 查询 3：架构参考
    if (lower.contains('架构') || lower.contains('architecture') || lower.contains('系统设计')) {
      final terms = selected.take(2).join(' ');
      if (terms.isNotEmpty) {
        queries.add('$terms 系统架构设计参考');
      }
    }

    // 查询 4：性能/安全
    if (lower.contains('性能') || lower.contains('安全') || lower.contains('并发')) {
      final terms = selected.take(2).join(' ');
      if (terms.isNotEmpty) {
        queries.add('$terms 性能优化 安全性 并发处理');
      }
    }

    return queries;
  }

  // ═══════ 格式化输出 ═══════

  /// 将调研结果格式化为可附加到 AI prompt 的引用块。
  ///
  /// 输出 Markdown 格式，每个条目包含标题、摘要和可点击链接。
  static String formatAsCitationBlock(List<WebResearchItem> items) {
    if (items.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln();
    buf.writeln('## 网络调研结果（来自 web_search）');
    buf.writeln();

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      buf.writeln('### ${i + 1}. ${item.title}');
      buf.writeln();
      buf.writeln(item.snippet);
      buf.writeln();
      if (item.hasUrl) {
        buf.writeln('> 来源：<${item.url}>');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  /// 将调研结果格式化为纯文本简表（适合嵌入 prompt）。
  static String formatAsCompactReference(List<WebResearchItem> items) {
    if (items.isEmpty) return '';

    final buf = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      buf.writeln('${i + 1}. ${item.title}');
      buf.writeln('   ${item.snippet}');
      if (item.hasUrl) {
        buf.writeln('   URL: ${item.url}');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  /// 将调研项转换为 [TechEvidence] 列表。
  static List<TechEvidence> toEvidenceList(List<WebResearchItem> items) {
    return items.map((item) => item.toEvidence()).toList();
  }
}

/// 内部解析结果持有类。
class _ParseResult {
  final WebResearchItem result;
  final int nextIndex;

  const _ParseResult(this.result, this.nextIndex);
}

/// AI 探索模式自定义 Agent 工具（Phase 4 · D1-D9）。
///
/// 六个探索工具（与定向抓取的 [scraper_tools] 并列，D9 两套 harness）：
/// - `explore_page_links()` — JS 枚举当前页所有 http(s) 链接
/// - `navigate_get(url)` — 仅 GET 导航（同域/上限/1s 节流守卫）
/// - `list_captured_requests()` — 只读捕获日志中 GET 请求（POST 一律不回灌）
/// - `present_data_sources(sources)` — 呈现归类候选 → 用户多选（可改名）
/// - `build_selected_source(name, code)` — 逐源构建 data-{name} 插件
/// - `register_batch(names)` — 批量热注册 + orch.get 验证
///
/// 浏览器通道与产物流水线由 UI 层（ScraperAIPanel）注入回调；
/// 阶段白名单由 ScraperHooks 依据 [ExploreWorkflow] 强制（本文件不重复判断）。
library scraper_explore_tools;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:evergreen_base/core/agent/tool.dart';

import '../agent/python_capabilities.dart';
import '../workflow/scraper_workflow.dart';
import 'explore_evidence.dart';
import 'explore_workflow.dart';

// ═══════ JS 脚本 ═══════

/// 枚举当前页所有 `a[href]` 链接（http/https），返回 JSON：
/// `{"count": N, "links": [{"url": "...", "text": "..."}]}`。
///
/// 结果通道（见 ScraperWebViewBridge）：
/// - Windows：executeScript 不回传结果，由 postMessage 桥接回传**原始字符串**
/// - Android：runJavaScriptReturningResult 回传 **JSON 编码后的字符串**
/// 两种形态 [_decodeJsJson] 均兼容。
const String explorePageLinksScript = r'''
(function() {
  var seen = {};
  var out = [];
  var links = document.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++) {
    try {
      var href = links[i].href || '';
      if (!href || !/^https?:/i.test(href)) continue;
      if (seen[href]) continue;
      seen[href] = true;
      var text = (links[i].innerText || links[i].title || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      out.push({ url: href, text: text });
    } catch (e) {}
  }
  return JSON.stringify({ count: out.length, links: out.slice(0, 200) });
})()
''';

/// 解析 JS 通道返回的 JSON（兼容"结果本身是 JSON 字符串"与
/// "结果被 JSON 编码多包一层"两种形态）。
Map<String, dynamic>? _decodeJsJson(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  try {
    final v = jsonDecode(s);
    if (v is Map<String, dynamic>) return v;
    if (v is String) {
      final inner = jsonDecode(v);
      if (inner is Map<String, dynamic>) return inner;
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ═══════ explore_page_links ═══════

/// 工具：枚举当前页 http(s) 链接（GET 探索起点）。
class ExplorePageLinksTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;
  final Future<String?> Function(String script) evaluateJs;

  ExplorePageLinksTool({
    required this.exploreWorkflow,
    required this.evaluateJs,
  }) : super(
          name: 'explore_page_links',
          description: '枚举当前浏览页面的所有 http/https 链接（a[href]），'
              '返回链接列表（url + 文本）。用于探索模式：配合 navigate_get '
              '逐页探索同域 GET 接口。只返回链接清单，不触发任何请求。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            try {
              final raw = await evaluateJs(explorePageLinksScript);
              final json = _decodeJsJson(raw);
              if (json == null) {
                return '[error: 浏览器 JS 通道不可用或页面未就绪，请稍后重试]';
              }
              final count = json['count'] as int? ?? 0;
              final links = (json['links'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
              if (links.isEmpty) {
                return '当前页共 0 个 http(s) 链接。'
                    '可尝试 navigate_get 访问已知地址，或结束探索进入归类。';
              }
              final base = exploreWorkflow.baseHost;
              final buf = StringBuffer();
              buf.writeln('当前页共 $count 个链接'
                  '${base.isNotEmpty ? '（已锁同域: $base）' : ''}：');
              var shown = 0;
              for (final l in links) {
                final url = (l['url'] as String? ?? '').trim();
                if (url.isEmpty) continue;
                final err = validateExploreUrl(url, baseHost: base);
                if (err != null) continue; // 非同域/非 http(s) 不回灌
                final text = (l['text'] as String? ?? '').trim();
                buf.writeln('- $url${text.isNotEmpty ? '  # $text' : ''}');
                if (++shown >= 100) {
                  buf.writeln('…（其余 ${count - shown} 个链接已截断）');
                  break;
                }
              }
              if (shown == 0) {
                buf.writeln('（所有链接均为非同域/非 http(s)，已按守卫过滤）');
              }
              return buf.toString();
            } catch (e) {
              debugPrint('[ExplorePageLinks] 💥 $e');
              return '[error: 枚举链接失败: $e]';
            }
          },
        );
}

// ═══════ navigate_get ═══════

/// 工具：仅 GET 导航（同域 + 上限 + 节流守卫，D2/D7）。
class NavigateGetTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;
  final Future<void> Function(String url) navigateTo;

  NavigateGetTool({
    required this.exploreWorkflow,
    required this.navigateTo,
  }) : super(
          name: 'navigate_get',
          description: '以 GET 方式导航内嵌浏览器到指定 URL（探索模式唯一导航通道）。'
              '守卫约束：仅 http/https；同域（首次导航锁定域名）；'
              '页数上限（默认 20 页）；请求上限（默认 50）；1s 节流；'
              '空转熔断（连续 3 次导航无新页面触发，熔断期间重复访问'
              '已探索页面会被拒绝——请立即换新链接或结束探索进入归类，'
              '禁止对同一页面无意义重试）。'
              '被守卫拒绝时请换一个链接或结束探索进入归类。'
              '禁止尝试 POST/表单提交/js: 伪协议。',
          schema: const {
            'type': 'object',
            'properties': {
              'url': {
                'type': 'string',
                'description': '要 GET 导航的完整 URL（http/https）',
              },
            },
            'required': ['url'],
          },
          readOnly: false,
          execute: (args) async {
            final url = (args['url'] as String? ?? '').trim();
            if (url.isEmpty) return '[error: url 参数为空]';
            final err = exploreWorkflow.recordNavigation(url);
            if (err != null) {
              return '[error: 探索导航被守卫拒绝: $err]';
            }
            try {
              await navigateTo(url);
              return '✅ 已 GET 导航: $url\n'
                  '页数 ${exploreWorkflow.uniquePages}/${exploreWorkflow.limits.maxPages}'
                  ' · 请求 ${exploreWorkflow.requestsCaptured}/${exploreWorkflow.limits.maxRequests}'
                  '${exploreWorkflow.pagesExhausted ? '\n⚠️ 已触达页数上限，请结束探索进入归类' : ''}'
                  '${exploreWorkflow.requestsExhausted ? '\n⚠️ 已触达请求上限，请结束探索进入归类' : ''}'
                  '${exploreWorkflow.stallDetected ? '\n⚡ 空转熔断已触发：${exploreWorkflow.stallMessage}。请切换策略（换新链接或结束探索进入归类）' : ''}';
            } catch (e) {
              debugPrint('[NavigateGet] 💥 $e');
              return '[error: 导航执行失败: $e]';
            }
          },
        );
}

// ═══════ list_captured_requests ═══════

/// 工具：读取捕获日志中的**全部**请求（GET/POST/NAVIGATION/RESPONSE 等全量回灌）。
///
/// 每条请求带证据 id（`log-N`，P0-2）：归类候选数据源时可引用该 id 作为
/// `sourceLogId` 证据（可选，非强制）。数据分类由 AI 自主判断价值。
class ListCapturedRequestsTool extends SimpleTool {
  final ScraperWorkflow captureWorkflow;
  final ExploreWorkflow exploreWorkflow;

  ListCapturedRequestsTool({
    required this.captureWorkflow,
    required this.exploreWorkflow,
  }) : super(
          name: 'list_captured_requests',
          description: '读取浏览器捕获日志中的全部请求（GET/POST/导航/响应等，'
              '不做方法过滤，全量回灌）。返回 AI 友好摘要'
              '（证据 id/方法/URL/关键 headers/响应体样本），供归类候选数据源使用。'
              '每条请求带证据 id（log-N），present_data_sources 时'
              '可引用 sourceLogId 作为来源证据（可选，非强制）。'
              '数据分类由你自主判断——记录你认为有价值的内容，'
              '不强制要求必须是 GET 请求。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            final base = exploreWorkflow.baseHost;
            final logs = captureWorkflow.logs.where((l) {
              if (!l.url.startsWith('http://') &&
                  !l.url.startsWith('https://')) {
                return false;
              }
              if (base.isNotEmpty) {
                return validateExploreUrl(l.url, baseHost: base) == null;
              }
              return true;
            }).toList();
            if (logs.isEmpty) {
              return '(暂无捕获日志) 请先在浏览器中浏览/探索目标页面。';
            }
            final buf = StringBuffer();
            buf.writeln('## 捕获的请求日志（${logs.length} 条'
                '${base.isNotEmpty ? ' · 同域 $base' : ''}）\n');
            final shown = logs.length > 100 ? 100 : logs.length;
            for (var i = 0; i < shown; i++) {
              final log = logs[i];
              final idLabel =
                  log.id.isNotEmpty ? ' · 证据 id: ${log.id}' : '';
              buf.writeln('### 请求 #${i + 1}$idLabel');
              buf.writeln(log.toAiSummary());
              buf.writeln();
            }
            if (logs.length > shown) {
              buf.writeln('…（其余 ${logs.length - shown} 条已截断）');
            }
            return buf.toString();
          },
        );
}

// ═══════ list_python_capabilities（P2-1 工具事实源）══════

/// 工具：返回本机嵌入式 Python 实际可用的第三方模块清单（事实源）。
///
/// 替代 prompt 硬编码「只允许标准库 + requests」：AI 构建爬虫前先查本工具，
/// 未列出的模块禁止 import（lint 兜底拦截），从源头消除反复尝试 bs4 的浪费。
class ListPythonCapabilitiesTool extends SimpleTool {
  final List<String> Function() listCapabilities;

  ListPythonCapabilitiesTool({required this.listCapabilities})
      : super(
          name: 'list_python_capabilities',
          description: '返回本机嵌入式 Python 实际可用的第三方模块清单（运行时'
              '事实源，替代猜测）。构建爬虫代码前先调用本工具确认可 import 的'
              '模块；仅清单内模块 + Python 标准库可用，未列出的模块禁止 import'
              '（会被 lint 拦截并消耗调试轮次）。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            try {
              return pythonCapabilitiesPrompt(listCapabilities());
            } catch (e) {
              debugPrint('[ListPythonCapabilities] 💥 $e');
              return '[error: 扫描 Python 能力清单失败: $e]';
            }
          },
        );
}

// ═══════ present_data_sources ═══════

/// 工具：呈现候选数据源 → 用户多选确认（D3/D4）。
///
/// AI 传入归类 JSON 数组；呈现前逐源做证据校验（P0-2）：url 必须匹配捕获日志
/// （[CandidateDataSource.sourceLogId] 引用或 URL 匹配兜底），否则硬阻断。
/// 通过后 UI 弹出多选弹窗（勾选 + 可改名）；返回用户最终选择（含改名结果）。
class PresentDataSourcesTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;
  final ScraperWorkflow captureWorkflow;
  final Future<List<CandidateDataSource>> Function(
      List<CandidateDataSource> candidates) presentSources;

  PresentDataSourcesTool({
    required this.exploreWorkflow,
    required this.captureWorkflow,
    required this.presentSources,
  }) : super(
          name: 'present_data_sources',
          description: '把归类好的候选数据源呈现给用户做多选确认。'
              '参数 sources 为 JSON 数组，每项：'
              '{name: 英文标识(仅字母数字_-、字母开头), displayName: 展示名, '
              'category: 归类(由你自主描述), url: 数据 URL, '
              'method: 请求方法(如 GET/POST，默认 GET；请避开编辑/删除等'
              '危险操作字样，只呈现只读查询类数据源), '
              'sourceLogId: 该 url 来源日志的证据 id（可选，'
              'list_captured_requests 返回的 log-N）, '
              'fields: [{name,type,description,sourceJsonPath: 响应 JSON 字段路径}'
              '如 \$.data[0].courseName]}。'
              '数据分类由你自主判断——记录你认为有价值的内容，'
              '不强求 GET 或日志证据（无日志证据仅提示不阻断）。'
              '调用后弹出多选框（用户可勾选并改名）；返回用户确认选择的数据源'
              'JSON 数组（以用户改名为准）。用户取消时返回提示，请重新归类或询问用户。',
          schema: const {
            'type': 'object',
            'properties': {
              'sources': {
                'type': 'string',
                'description': '候选数据源 JSON 数组（序列化为字符串）',
              },
            },
            'required': ['sources'],
          },
          readOnly: false,
          execute: (args) async {
            final raw = args['sources'];
            List<dynamic> list;
            try {
              if (raw is List) {
                list = raw;
              } else if (raw is String) {
                list = jsonDecode(raw) as List<dynamic>;
              } else {
                return '[error: sources 参数缺失]';
              }
            } catch (e) {
              return '[error: sources JSON 解析失败: $e]';
            }

            final candidates = <CandidateDataSource>[];
            final evidenceWarnings = <String>[];
            for (final item in list.whereType<Map<String, dynamic>>()) {
              final c = CandidateDataSource.fromJson(item);
              final nameErr = sanitizeSourceName(c.name);
              if (nameErr != null) {
                return '[error: 数据源名称非法: $nameErr — name="${c.name}"]';
              }
              // 危险 method 提示（不阻断）：编辑/删除类操作提示 AI 避开
              final dmHint = dangerousMethodHint(c.method);
              if (dmHint != null) {
                evidenceWarnings.add('${c.name}: $dmHint');
              }
              // 数据分类放开：URL 仅校验 http/https 格式（不锁同域，不强求 GET）
              final urlErr = validateExploreUrl(c.url);
              if (urlErr != null) {
                return '[error: 数据源 ${c.name} URL 非法: $urlErr]';
              }
              if (candidates.any((x) => x.name == c.name)) {
                return '[error: 数据源名称重复: "${c.name}"]';
              }
              // P0-2 证据校验（放宽）：url 无捕获日志证据 → 仅警告，不硬阻断
              final evidence = validateDataSourceEvidence(
                  c, captureWorkflow.logs);
              for (final w in evidence.warnings) {
                evidenceWarnings.add('${c.name}: $w');
              }
              candidates.add(c.displayName.isEmpty
                  ? c.copyWith(displayName: c.name)
                  : c);
            }
            if (candidates.isEmpty) {
              return '[error: 候选数据源列表为空]';
            }
            if (candidates.length > 30) {
              return '[error: 候选数据源过多（${candidates.length} > 30），请合并归类后重试]';
            }

            debugPrint('[PresentDataSources] 呈现 ${candidates.length} 个候选'
                '（阶段: ${exploreWorkflow.phase.name}）');
            if (exploreWorkflow.phase == ExplorePhase.exploring) {
              if (!exploreWorkflow.startCategorizing()) {
                return '[error: 无法进入归类阶段]';
              }
            }
            if (!exploreWorkflow.presentCandidates(candidates)) {
              return '[error: 当前阶段（${exploreWorkflow.phase.name}）不允许呈现数据源，'
                  '请先完成探索]';
            }

            final selected = await presentSources(candidates);
            if (selected.isEmpty) {
              return '[error: 用户未选择任何数据源。请重新归类（合并/拆分候选），'
                  '或调用 ask 询问用户需求]';
            }
            if (!exploreWorkflow.confirmSelection(selected)) {
              return '[error: 选择确认失败（阶段: ${exploreWorkflow.phase.name}）]';
            }

            final out = selected.map((s) => s.toJson()).toList();
            final warnText = evidenceWarnings.isEmpty
                ? ''
                : '\n⚠️ 证据警告（不阻断，建议修正后再构建）：\n'
                    '${evidenceWarnings.map((w) => '- $w').join('\n')}\n';
            return '✅ 用户已确认 ${selected.length} 个数据源：\n'
                '${const JsonEncoder.withIndent('  ').convert(out)}\n'
                '$warnText\n'
                '下一步：对每个数据源依次调用 build_selected_source(name, code) 构建，'
                '全部构建完成后调用 register_batch(names) 批量注册。';
          },
        );
}

// ═══════ build_selected_source ═══════

/// 工具：逐源构建 data-{name} 插件（D5/D8）。
///
/// 注入 [exploreWorkflow]/[captureWorkflow] 时做 P0-2 证据复核（纵深防御）：
/// name 须在用户确认清单中（防改名漂移）；无 url 证据 → 仅警告透传（不阻断）。
/// 两者为空（独立构造/测试）时跳过证据校验，保持向后兼容。
class BuildSelectedSourceTool extends SimpleTool {
  final Future<String> Function(String name, String code) buildSource;
  final ExploreWorkflow? exploreWorkflow;
  final ScraperWorkflow? captureWorkflow;

  BuildSelectedSourceTool({
    required this.buildSource,
    this.exploreWorkflow,
    this.captureWorkflow,
  }) : super(
          name: 'build_selected_source',
          description: '为某个已确认的数据源构建插件目录 data-{name}/'
              '（scraper.py + data/manifest.json + config/config.json）。'
              'code 为该数据源的完整 Python 爬虫（必须逐字包含锁定配置模板，'
              '只允许标准库 + requests，main 用 json.dumps 输出合法 JSON）。'
              '返回构建结果日志；若含 ❌/lastError，请分析并重试（最多 3 轮后换策略）。'
              '构建完成后统一用 register_batch 批量注册。',
          schema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': '数据源名称（必须是用户确认选择中的 name）',
              },
              'code': {
                'type': 'string',
                'description': '该数据源的完整 Python 爬虫代码',
              },
            },
            'required': ['name', 'code'],
          },
          readOnly: false,
          execute: (args) async {
            final name = (args['name'] as String? ?? '').trim();
            final code = args['code'] as String? ?? '';
            if (name.isEmpty) return '[error: name 参数为空]';
            final nameErr = sanitizeSourceName(name);
            if (nameErr != null) return '[error: 数据源名称非法: $nameErr]';
            if (code.isEmpty) return '[error: code 参数为空]';

            // P0-2 证据复核（放宽：无日志证据仅警告，不阻断；防绕过仍保留清单校验）
            final notes = <String>[];
            final ew = exploreWorkflow;
            final cw = captureWorkflow;
            if (ew != null && cw != null) {
              final src = _findConfirmedSource(ew, name);
              if (src == null) {
                return '[error: 数据源 $name 不在用户确认清单中，拒绝构建]';
              }
              final evidence = validateDataSourceEvidence(src, cw.logs);
              for (final w in evidence.warnings) {
                notes.add('⚠️ $name: $w');
              }
            }

            final log = await buildSource(name, code);
            final base = log.trim().isEmpty ? '[error: 构建未产生任何日志]' : log;
            final notesText =
                notes.isEmpty ? '' : '${notes.join('\n')}\n\n';
            return '📁 **data-$name**\n\n$notesText$base';
          },
        );
}

// ═══════ register_batch ═══════

/// 工具：批量注册 + orch.get 验证（D6）。
///
/// 注入 [exploreWorkflow]/[captureWorkflow] 时做 P0-2 证据终闸（放宽）：
/// 每个 name 须在用户确认清单中（防绕过）；url 无捕获日志证据仅警告不阻断。
/// 两者为空（独立构造/测试）时跳过证据校验，保持向后兼容。
class RegisterBatchTool extends SimpleTool {
  final Future<String> Function(List<String> names) registerBatch;
  final ExploreWorkflow? exploreWorkflow;
  final ScraperWorkflow? captureWorkflow;

  RegisterBatchTool({
    required this.registerBatch,
    this.exploreWorkflow,
    this.captureWorkflow,
  }) : super(
          name: 'register_batch',
          description: '批量热注册已构建的数据源插件（data-{name}）到数据中心，'
              '并对每个类型执行 orch.get 拉取验证。'
              'names 为数据源名称数组（JSON 数组字符串，或逗号分隔）。'
              '注册前校验：数据源必须已在用户确认清单中（无日志证据仅提示，不拒绝）。'
              '返回完整结果日志（含 lastError/拉取异常/返回 null 等详情）；'
              '若有失败项，用 build_selected_source 修正后再次调用本工具（最多 3 轮）。',
          schema: const {
            'type': 'object',
            'properties': {
              'names': {
                'type': 'string',
                'description': '数据源名称数组（JSON 数组字符串，如 ["a","b"]）',
              },
            },
            'required': ['names'],
          },
          readOnly: false,
          execute: (args) async {
            final raw = args['names'];
            final names = <String>[];
            try {
              if (raw is List) {
                names.addAll(raw.whereType<String>());
              } else if (raw is String) {
                final decoded = jsonDecode(raw);
                if (decoded is List) {
                  names.addAll(decoded.whereType<String>());
                } else {
                  names.addAll(decoded.split(',').map((s) => s.trim())
                      .where((s) => s.isNotEmpty));
                }
              }
            } catch (_) {
              if (raw is String) {
                names.addAll(raw.split(',').map((s) => s.trim())
                    .where((s) => s.isNotEmpty));
              }
            }
            if (names.isEmpty) return '[error: names 参数为空]';
            for (final n in names) {
              final err = sanitizeSourceName(n);
              if (err != null) return '[error: 数据源名称非法: $err — "$n"]';
            }

            // P0-2 证据终闸（放宽：无日志证据仅警告，不阻断；未确认仍拒绝注册）
            final notes = <String>[];
            final ew = exploreWorkflow;
            final cw = captureWorkflow;
            if (ew != null && cw != null) {
              for (final n in names) {
                final src = _findConfirmedSource(ew, n);
                if (src == null) {
                  return '[error: 数据源 $n 不在用户确认清单中，拒绝注册。'
                      '请重新 present_data_sources 确认后重试]';
                }
                final evidence = validateDataSourceEvidence(src, cw.logs);
                for (final w in evidence.warnings) {
                  notes.add('⚠️ $n: $w');
                }
              }
            }

            final log = await registerBatch(names);
            final base = log.trim().isEmpty ? '[error: 注册未产生任何日志]' : log;
            final notesText =
                notes.isEmpty ? '' : '${notes.join('\n')}\n\n';
            return '🔗 **批量注册（${names.length} 个数据源）**\n\n$notesText$base';
          },
        );
}

// ═══════ 工具集工厂 ═══════

/// 在用户确认清单中查找数据源（build/register 工具的证据与清单终闸）。
CandidateDataSource? _findConfirmedSource(ExploreWorkflow ew, String name) {
  for (final s in ew.selected) {
    if (s.name == name) return s;
  }
  return null;
}

/// 为探索模式 Agent 构造全部自定义工具。
///
/// UI 层注入回调：
/// - [evaluateJs] — JS 执行通道（ScraperWebViewBridge）
/// - [navigateTo] — GET 导航通道
/// - [presentSources] — 候选多选弹窗（返回用户选择，可改名）
/// - [buildSource] — 逐源构建插件并返回完整日志
/// - [registerBatch] — 批量注册 + orch.get 验证并返回完整日志
/// - [listPythonCapabilities] — P2-1 工具事实源：本机可用第三方模块清单（可空，
///   空时工具返回仅标准库）
List<Tool> createScraperExploreTools({
  required ExploreWorkflow exploreWorkflow,
  required ScraperWorkflow captureWorkflow,
  required Future<String?> Function(String script) evaluateJs,
  required Future<void> Function(String url) navigateTo,
  required Future<List<CandidateDataSource>> Function(
      List<CandidateDataSource> candidates) presentSources,
  required Future<String> Function(String name, String code) buildSource,
  required Future<String> Function(List<String> names) registerBatch,
  List<String> Function()? listPythonCapabilities,
}) {
  return [
    ExplorePageLinksTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
    ),
    NavigateGetTool(
      exploreWorkflow: exploreWorkflow,
      navigateTo: navigateTo,
    ),
    ListCapturedRequestsTool(
      captureWorkflow: captureWorkflow,
      exploreWorkflow: exploreWorkflow,
    ),
    ListPythonCapabilitiesTool(
      listCapabilities: listPythonCapabilities ?? () => const [],
    ),
    PresentDataSourcesTool(
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
      presentSources: presentSources,
    ),
    BuildSelectedSourceTool(
      buildSource: buildSource,
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
    ),
    RegisterBatchTool(
      registerBatch: registerBatch,
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
    ),
  ];
}

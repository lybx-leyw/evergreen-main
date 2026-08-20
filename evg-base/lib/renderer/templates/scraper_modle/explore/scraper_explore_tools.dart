/// AI 探索模式自定义 Agent 工具（Phase 4 · D1-D9）。
///
/// 一组探索工具（与定向抓取的 [scraper_tools] 并列，D9 两套 harness）：
/// - `explore_page_links()` — JS 枚举当前页所有 http(s) 链接
/// - `explore_network_resources()` — JS 枚举当前页加载的网络资源
/// - `navigate_get(url)` — 仅 GET 导航（同域/上限/1s 节流守卫）
/// - `list_captured_requests()` / `read_request_by_id()` — 读取捕获日志
/// - `list_python_capabilities()` — 查询本机 Python 第三方模块
/// - `set_env_var()` / `list_env_vars()` — 写入/列出凭据环境变量
/// - `read_workspace_file()` / `guard_override()` — 工作区读取 / 门控放行
/// - `check_explore_ready()` — 环境诊断（区分 AI 行为错误与浏览器未就绪）
/// - `present_data_sources(sources)` — 呈现归类候选 → 用户多选（可改名）
/// - `verify_login_flow(code)` / `execute_built_source(name)` — 真实执行验证
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
import '../agent/tools/scraper_tools.dart'
    show GuardOverrideTool, ReadWorkspaceFileTool, SetEnvVarTool, ListEnvVarsTool;
import '../scraper_env.dart';
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

/// 枚举当前页运行时加载的资源 URL（fetch/XHR/script/img/css 等）。
///
/// 修复（Phase 8）：SPA 站点的数据接口靠 JS fetch/XHR 动态请求，页面上往往没有
/// 对应 `<a href>` 锚点，`explore_page_links` 永远枚举不到。用 Performance API
/// 的资源时间线（`initiatorType` 标识 `fetch`/`xmlhttprequest` 等）补足发现通道。
const String exploreNetworkResourcesScript = r'''
(function() {
  var seen = {};
  var out = [];
  try {
    var entries = performance.getEntriesByType('resource');
    for (var i = 0; i < entries.length; i++) {
      var u = entries[i].name || '';
      if (!u || !/^https?:/i.test(u)) continue;
      if (seen[u]) continue;
      seen[u] = true;
      out.push({ url: u, initiatorType: entries[i].initiatorType || '' });
    }
  } catch (e) {}
  return JSON.stringify({ count: out.length, resources: out.slice(0, 200) });
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

// ═══════ P1-D：页面操作前检查脚本（不触发任何副作用）═══════

/// 检查点击目标元素（**不点击**）：tag / href（`<a>` 目标）/
/// formAction（提交按钮所在表单 action）/ 可见性 / 文本。
///
/// 供 page_click 在点击前做 scope 越界校验——防御"点击指向授权范围外的链接/表单"。
String _inspectClickTargetScript(String selector) => r'''
(function() {
  var sel = ''' +
      jsonEncode(selector) +
      r''';
  try {
    var el = document.querySelector(sel);
    if (!el) return JSON.stringify({ found: false, message: '未找到元素: ' + sel });
    var out = { found: true, tag: (el.tagName || '').toLowerCase() };
    try {
      if (el.href) out.href = el.href;                        // <a> 目标 URL
      if (el.form && el.form.action) out.formAction = el.form.action; // 提交按钮所在表单
      var t = (el.innerText || el.textContent || el.title || '').replace(/\s+/g, ' ').trim().slice(0, 60);
      if (t) out.text = t;
    } catch(e) {}
    var r = el.getBoundingClientRect();
    out.visible = (r.width > 0 && r.height > 0);
    return JSON.stringify(out);
  } catch(e) {
    return JSON.stringify({ found: false, message: String(e) });
  }
})()
''';

/// 检查表单（**不提交**）：action（绝对化 URL）/ method。
///
/// 供 page_submit 在提交前校验表单 action 是否落在授权范围。
String _inspectFormScript(String formSelector) => r'''
(function() {
  var sel = ''' +
      jsonEncode(formSelector) +
      r''';
  try {
    var form = document.querySelector(sel);
    if (!form) return JSON.stringify({ found: false, message: '未找到表单: ' + sel });
    if (form.tagName.toLowerCase() !== 'form') {
      return JSON.stringify({ found: false, message: '目标不是 <form> 元素: ' + sel });
    }
    return JSON.stringify({ found: true, action: form.action || '', method: (form.method || 'get').toLowerCase() });
  } catch(e) {
    return JSON.stringify({ found: false, message: String(e) });
  }
})()
''';

/// 页面操作通道不可用的统一错误提示（浏览器未就绪/未注入操作脚本）。
String _pageOpChannelError(String tool) =>
    '[error: 页面操作通道（$tool）不可用——浏览器未就绪或未注入操作脚本。'
    '→ 先 check_explore_ready 确认 WebView 已加载页面后重试。]';

// ═══════ explore_page_snapshot（P1-C · 导航后快照判型）═══════

/// 采集当前页结构化摘要的 JS：`document.title` / 面包屑 / 导航菜单 /
/// 表单字段 / 按钮 / 分页链接 / 表格列头。
///
/// 解决 AI"导航后失明"——navigate_get 只回计数，本快照让 AI 判断页面类型
/// （列表页/详情页/登录页/占位页），据此决定下钻、填表还是放弃。
const String explorePageSnapshotScript = r'''
(function() {
  function txt(el) {
    return (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 120);
  }
  function href(el) {
    try { return el.href || ''; } catch (e) { return ''; }
  }
  var out = { title: document.title || '', url: location.href, breadcrumbs: [], navMenus: [], forms: [], buttons: [], pagination: [], tableHeaders: [] };
  try {
    // 面包屑：aria-label=breadcrumb / class 含 breadcrumb / nav
    var crumbs = document.querySelectorAll('[aria-label="breadcrumb"], .breadcrumb, nav[aria-label="面包屑"], .crumbs');
    for (var i = 0; i < crumbs.length && i < 3; i++) {
      var text = txt(crumbs[i]);
      if (text) out.breadcrumbs.push(text.slice(0, 200));
    }
    // 导航菜单：nav / header 内的链接（最多 30 条）
    var navs = document.querySelectorAll('nav, header nav, .nav, .menu');
    var seen = {};
    for (var i = 0; i < navs.length && i < 3; i++) {
      var links = navs[i].querySelectorAll('a[href]');
      var items = [];
      for (var j = 0; j < links.length && items.length < 30; j++) {
        var u = href(links[j]);
        if (!u || !/^https?:/i.test(u) || seen[u]) continue;
        seen[u] = true;
        var t = txt(links[j]);
        if (t) items.push({ url: u, text: t });
      }
      if (items.length) out.navMenus.push(items);
    }
    // 表单字段：name + type（登录/搜索/筛选表单识别）
    var forms = document.querySelectorAll('form');
    for (var i = 0; i < forms.length && i < 5; i++) {
      var fields = [];
      var els = forms[i].querySelectorAll('input, select, textarea');
      for (var j = 0; j < els.length && fields.length < 15; j++) {
        var el = els[j];
        var name = el.name || el.id || '';
        var type = el.type || el.tagName.toLowerCase();
        if (!name) continue;
        if (type === 'hidden' || type === 'submit' || type === 'button') continue;
        fields.push({ name: name, type: type });
      }
      if (fields.length) out.forms.push({ action: forms[i].action || '', fields: fields });
    }
    // 按钮文本（提交/登录/搜索等动作按钮）
    var btns = document.querySelectorAll('button, input[type="submit"], input[type="button"]');
    var bseen = {};
    for (var i = 0; i < btns.length && out.buttons.length < 20; i++) {
      var btxt = txt(btns[i]);
      if (!btxt) continue;
      if (bseen[btxt]) continue;
      bseen[btxt] = true;
      out.buttons.push(btxt.slice(0, 40));
    }
    // 分页链接：href 含 page/p/pn / 文本含 下一页|next|» | .pagination
    var pageLinks = document.querySelectorAll('a[href*="page"], a[href*="?p="], a[href*="&p="], a[href*="pn="], .pagination a[href]');
    var pseen = {};
    for (var i = 0; i < pageLinks.length && out.pagination.length < 10; i++) {
      var pu = href(pageLinks[i]);
      if (!pu || pseen[pu]) continue;
      pseen[pu] = true;
      var pt = txt(pageLinks[i]);
      out.pagination.push({ url: pu, text: pt ? pt.slice(0, 30) : '' });
    }
    // 表格列头（数据表识别）
    var ths = document.querySelectorAll('table th');
    var hseen = {};
    for (var i = 0; i < ths.length && out.tableHeaders.length < 15; i++) {
      var ht = txt(ths[i]);
      if (!ht || hseen[ht]) continue;
      hseen[ht] = true;
      out.tableHeaders.push(ht);
    }
  } catch (e) {
    out.error = String(e);
  }
  return JSON.stringify(out);
})()
''';

/// 工具：采集当前页结构化快照（标题/面包屑/导航/表单/按钮/分页/表格列头）。
///
/// P1-C：navigate_get 只回计数，AI 导航后"失明"。本工具让 AI 在导航后
/// 立即判断页面类型（列表页/详情页/登录页/占位页），据此决定深挖、
/// 填表登录还是放弃——深度下钻有了可解释依据。
class ExplorePageSnapshotTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;
  final Future<String?> Function(String script) evaluateJs;

  ExplorePageSnapshotTool({
    required this.exploreWorkflow,
    required this.evaluateJs,
  }) : super(
          name: 'explore_page_snapshot',
          description: '采集当前页面的结构化快照：标题/面包屑/导航菜单/表单字段'
              '（name+type）/按钮文本/分页链接/表格列头。用于 navigate_get 后'
              '判断页面类型（列表/详情/登录/占位），再决定深挖或放弃。'
              '只读取页面结构，不触发任何请求。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            try {
              final raw = await evaluateJs(explorePageSnapshotScript);
              final json = _decodeJsJson(raw);
              if (json == null) {
                return '[error: 浏览器 JS 通道不可用或页面未就绪。'
                    '→ 先调用 check_explore_ready 确认 WebView 是否已加载页面；'
                    '若页面尚未加载，可 navigate_get 访问目标页后再快照。]';
              }
              // P1-B：快照成功 = 二次探索产出（导航后重读页面结构不算空转）
              exploreWorkflow.noteSecondaryExploration();

              final buf = StringBuffer();
              final title = (json['title'] as String? ?? '').trim();
              final url = (json['url'] as String? ?? '').trim();
              buf.writeln('## 📄 页面快照'
                  '${title.isNotEmpty ? '\n标题: $title' : ''}'
                  '${url.isNotEmpty ? '\nURL: $url' : ''}');

              final crumbs = (json['breadcrumbs'] as List<dynamic>? ?? const [])
                  .whereType<String>();
              if (crumbs.isNotEmpty) {
                buf.writeln('面包屑: ${crumbs.join(' → ')}');
              }

              final navs = (json['navMenus'] as List<dynamic>? ?? const [])
                  .whereType<List<dynamic>>()
                  .toList();
              if (navs.isNotEmpty) {
                buf.writeln('导航菜单:');
                var shown = 0;
                for (final menu in navs) {
                  for (final item in menu.whereType<Map<String, dynamic>>()) {
                    final u = (item['url'] as String? ?? '').trim();
                    if (validateExploreUrl(u, baseHost: exploreWorkflow.baseHost) != null) continue;
                    final t = (item['text'] as String? ?? '').trim();
                    buf.writeln('- $u${t.isNotEmpty ? '  # $t' : ''}');
                    if (++shown >= 40) break;
                  }
                }
                if (shown == 0) buf.writeln('（导航链接均为非同域，已过滤）');
              }

              final forms = (json['forms'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
              if (forms.isNotEmpty) {
                buf.writeln('表单:');
                for (final f in forms) {
                  final action = (f['action'] as String? ?? '').trim();
                  final fields = (f['fields'] as List<dynamic>? ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .toList();
                  buf.writeln('- form${action.isNotEmpty ? ' action=$action' : ''}: '
                      '${fields.map((x) => '${x['name']}(${x['type']})').join(', ')}');
                }
              } else {
                buf.writeln('表单: 无');
              }

              final buttons = (json['buttons'] as List<dynamic>? ?? const [])
                  .whereType<String>()
                  .toList();
              if (buttons.isNotEmpty) {
                buf.writeln('按钮: ${buttons.join(' / ')}');
              }

              final paging = (json['pagination'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList();
              if (paging.isNotEmpty) {
                buf.writeln('分页链接:');
                for (final p in paging) {
                  final u = (p['url'] as String? ?? '').trim();
                  if (validateExploreUrl(u, baseHost: exploreWorkflow.baseHost) != null) continue;
                  final t = (p['text'] as String? ?? '').trim();
                  buf.writeln('- $u${t.isNotEmpty ? '  # $t' : ''}');
                }
              }

              final headers = (json['tableHeaders'] as List<dynamic>? ?? const [])
                  .whereType<String>()
                  .toList();
              if (headers.isNotEmpty) {
                buf.writeln('表格列头: ${headers.join(' | ')}');
              }

              if (buf.length < 30) {
                return '(页面快照为空——页面可能未加载完成或为空白/占位页。'
                    '可 navigate_get 访问已知地址后再快照，或结束探索进入归类。)';
              }
              return buf.toString();
            } catch (e) {
              debugPrint('[ExplorePageSnapshot] 💥 $e');
              return '[error: 采集页面快照失败: $e]';
            }
          },
        );
}

// ═══════ P1-D：AI 页面操作工具（点击/填表/提交/滚动）═══════

/// 工具：点击当前页面元素（菜单/按钮/翻页/懒加载触发）。
///
/// P1-D：交互型站点的数据往往在"点击后才出现"（点菜单进栏目、点加载更多
/// 触发分页请求）。点击前先检查目标元素——若目标是 `<a href>` 或提交按钮，
/// 校验其链接/form action 是否越出授权范围（越界**拒绝点击**）；
/// 点击后返回页面标题/URL 与已捕获请求数，供 AI 判断交互是否触达数据接口。
class PageClickTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;

  /// JS 执行通道（点击前检查目标元素用）。
  final Future<String?> Function(String script) evaluateJs;

  /// 页面点击通道（桥层注入合成事件）。
  final Future<String?> Function(String selector)? jsClick;

  PageClickTool({
    required this.exploreWorkflow,
    required this.evaluateJs,
    this.jsClick,
  }) : super(
          name: 'page_click',
          description: '点击当前页面上的元素（菜单/按钮/翻页/「加载更多」等）。'
              '点击前自动校验：若目标是链接/提交按钮，其 href / 表单 action '
              '越出授权范围则**拒绝点击**（不会触发越界导航）。'
              '点击后返回页面标题/URL 与已捕获请求数，可 list_captured_requests '
              '回读点击触发的数据请求。用于交互型站点：点菜单进目标栏目、'
              '点「加载更多」触发分页请求。只读操作，无需授权。',
          schema: const {
            'type': 'object',
            'properties': {
              'selector': {
                'type': 'string',
                'description': 'CSS 选择器（如 "nav a[href*=\\\"/course\\\"]"、'
                    '"button.load-more"、".pagination .next"）',
              },
            },
            'required': ['selector'],
          },
          readOnly: true,
          execute: (args) async {
            final selector = (args['selector'] as String? ?? '').trim();
            if (selector.isEmpty) return '[error: selector 参数为空]';
            if (jsClick == null) return _pageOpChannelError('page_click');
            try {
              // 1) 点击前检查目标元素（不点击、无副作用）
              final rawInspect = await evaluateJs(_inspectClickTargetScript(selector));
              final inspect = _decodeJsJson(rawInspect);
              if (inspect == null || inspect['found'] != true) {
                return '[error: 页面操作 JS 通道不可用或元素不存在'
                    '（selector="$selector"）。'
                    '→ 先 explore_page_snapshot 确认页面结构与选择器，'
                    '或 check_explore_ready 检查浏览器通道。]';
              }
              if (inspect['visible'] == false) {
                return '[error: 目标元素不可见（宽高为 0），点击无意义。'
                    '→ 可先用 page_scroll 滚动到目标区域再点击。]';
              }
              // 2) 越界校验：链接/表单 action 不得超出授权范围
              final base = exploreWorkflow.baseHost;
              final href = (inspect['href'] as String? ?? '').trim();
              final formAction = (inspect['formAction'] as String? ?? '').trim();
              for (final target in [
                if (href.isNotEmpty) href,
                if (formAction.isNotEmpty) formAction,
              ]) {
                final err = validateExploreUrl(target, baseHost: base);
                if (err != null) {
                  return '[error: 点击目标越界拒绝: $err'
                      '（page_click 不得点击指向授权范围外的链接/表单）]';
                }
                final scope = exploreWorkflow.scope;
                if (scope != null) {
                  final scopeErr = scope.validateUrl(target);
                  if (scopeErr != null) {
                    return '[error: 点击目标超出用户授权范围: $scopeErr]';
                  }
                }
              }
              // 3) 执行点击
              final raw = await jsClick!(selector);
              final json = _decodeJsJson(raw);
              if (json == null || json['ok'] != true) {
                final msg = json?['message'];
                return '[error: 点击失败${msg != null ? ': $msg' : ''}'
                    '（selector="$selector"）。'
                    '→ 换选择器，或用 explore_page_snapshot 确认页面结构。]';
              }
              // P1-D：点击 = 主动交互产出（重访/操作后不算空转）
              exploreWorkflow.noteSecondaryExploration();
              final tag = (json['tag'] as String? ?? '').trim();
              final text = (json['text'] as String? ?? '').trim();
              final title = (json['title'] as String? ?? '').trim();
              final url = (json['url'] as String? ?? '').trim();
              // 点击导致页面导航后回读：若当前 URL 越界给出警告
              var warn = '';
              if (url.isNotEmpty) {
                final uErr = validateExploreUrl(url, baseHost: base);
                final scopeErr = exploreWorkflow.scope?.validateUrl(url);
                if (uErr != null || scopeErr != null) {
                  warn = '\n⚠️ 点击后页面当前 URL 超出授权范围（$url），'
                      '请 navigate_get 返回授权页面继续探索。';
                }
              }
              return '✅ 已点击 ${tag.isNotEmpty ? '<$tag>' : '元素'}'
                  '${text.isNotEmpty ? '「$text」' : ''}（selector="$selector"）'
                  '${title.isNotEmpty ? '\n页面标题: $title' : ''}'
                  '${url.isNotEmpty ? '\n当前 URL: $url' : ''}'
                  '\n已捕获请求 ${exploreWorkflow.requestsCaptured} 条'
                  '（可 list_captured_requests / explore_network_resources 回读）'
                  '$warn';
            } catch (e) {
              debugPrint('[PageClick] 💥 $e');
              return '[error: 点击执行异常: $e]';
            }
          },
        );
}

/// 工具：向当前页面表单字段填充值（input/textarea/select）。
///
/// P1-D：登录/搜索/筛选表单填写。用原生 value setter + input/change 事件
/// （兼容 React 受控组件）。**写操作**：需用户经 guard_override 一次性授权。
class PageFillTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;

  /// 页面填充通道（桥层注入）。
  final Future<String?> Function(String selector, String value)? jsFill;

  PageFillTool({
    required this.exploreWorkflow,
    this.jsFill,
  }) : super(
          name: 'page_fill',
          description: '向当前页面的表单字段填充值（input/textarea/select；'
              '原生 value setter + input/change 事件，兼容 React 受控组件）。'
              '用于登录/搜索/筛选表单填写。'
              '⚠️ 写操作：调用前需 guard_override("page_fill", "<理由>") 请求用户'
              '一次性授权，用户同意后才能执行。',
          schema: const {
            'type': 'object',
            'properties': {
              'selector': {
                'type': 'string',
                'description': 'CSS 选择器（如 "#username"、"input[name=\\\"keyword\\\"]"）',
              },
              'value': {
                'type': 'string',
                'description': '要填充的值（账号/密码/关键词等；凭据先 set_env_var 写入）',
              },
            },
            'required': ['selector', 'value'],
          },
          readOnly: false,
          execute: (args) async {
            final selector = (args['selector'] as String? ?? '').trim();
            final value = args['value'] as String? ?? '';
            if (selector.isEmpty) return '[error: selector 参数为空]';
            if (jsFill == null) return _pageOpChannelError('page_fill');
            try {
              final raw = await jsFill!(selector, value);
              final json = _decodeJsJson(raw);
              if (json == null || json['ok'] != true) {
                final msg = json?['message'];
                return '[error: 填充失败${msg != null ? ': $msg' : ''}'
                    '（selector="$selector"）。'
                    '→ 用 explore_page_snapshot 查看表单字段（name+type）后换正确选择器。]';
              }
              // P1-D：填表 = 主动交互产出（不算空转）
              exploreWorkflow.noteSecondaryExploration();
              final tag = (json['tag'] as String? ?? '').trim();
              final type = (json['type'] as String? ?? '').trim();
              final title = (json['title'] as String? ?? '').trim();
              final url = (json['url'] as String? ?? '').trim();
              return '✅ 已填充 <$tag${type.isNotEmpty ? ' type=$type' : ''}>'
                  '（selector="$selector"）'
                  '${title.isNotEmpty ? '\n页面标题: $title' : ''}'
                  '${url.isNotEmpty ? '\n当前 URL: $url' : ''}'
                  '\n→ 如需提交表单，先 guard_override("page_submit", "<理由>") '
                  '授权后调用 page_submit。';
            } catch (e) {
              debugPrint('[PageFill] 💥 $e');
              return '[error: 填充执行异常: $e]';
            }
          },
        );
}

/// 工具：提交当前页面的表单（登录/搜索/筛选）。
///
/// P1-D：提交触发登录/搜索请求进入捕获日志（GET/POST 均记录），AI 据此
/// 读到登录接口与 Set-Cookie 登录态。提交前校验表单 action 在授权范围内
/// （越界**拒绝提交**）。**写操作**：需用户经 guard_override 一次性授权。
class PageSubmitTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;

  /// JS 执行通道（提交前检查表单 action 用）。
  final Future<String?> Function(String script) evaluateJs;

  /// 页面提交通道（桥层注入）。
  final Future<String?> Function(String formSelector)? jsSubmit;

  PageSubmitTool({
    required this.exploreWorkflow,
    required this.evaluateJs,
    this.jsSubmit,
  }) : super(
          name: 'page_submit',
          description: '提交当前页面的表单（form.requestSubmit 优先，触发校验与'
              'submit 事件）。提交前自动校验表单 action 在授权范围内（越界拒绝）；'
              '提交后返回 action/method 与已捕获请求数——登录/搜索请求会进入捕获'
              '日志，可 list_captured_requests 回读（含 200/401、Set-Cookie）。'
              '⚠️ 写操作：调用前需 guard_override("page_submit", "<理由>") 请求'
              '用户一次性授权。',
          schema: const {
            'type': 'object',
            'properties': {
              'form': {
                'type': 'string',
                'description': 'CSS 选择器（如 "form.login-form"；'
                    'explore_page_snapshot 返回的 form action 对应表单）',
              },
            },
            'required': ['form'],
          },
          readOnly: false,
          execute: (args) async {
            final formSel = (args['form'] as String? ?? '').trim();
            if (formSel.isEmpty) return '[error: form 参数为空]';
            if (jsSubmit == null) return _pageOpChannelError('page_submit');
            try {
              // 1) 提交前检查表单 action（不提交、无副作用）
              final rawInspect = await evaluateJs(_inspectFormScript(formSel));
              final inspect = _decodeJsJson(rawInspect);
              if (inspect == null || inspect['found'] != true) {
                return '[error: 页面操作 JS 通道不可用或表单不存在'
                    '（form="$formSel"）。'
                    '→ 先 explore_page_snapshot 查看表单字段后换选择器。]';
              }
              // 2) 越界校验：表单 action 必须落在授权范围
              final action = (inspect['action'] as String? ?? '').trim();
              final base = exploreWorkflow.baseHost;
              if (action.isNotEmpty) {
                final err = validateExploreUrl(action, baseHost: base);
                if (err != null) {
                  return '[error: 表单提交越界拒绝: $err'
                      '（表单 action=$action 不在授权范围内，禁止提交）]';
                }
                final scope = exploreWorkflow.scope;
                if (scope != null) {
                  final scopeErr = scope.validateUrl(action);
                  if (scopeErr != null) {
                    return '[error: 表单 action 超出用户授权范围: $scopeErr]';
                  }
                }
              }
              // 3) 执行提交
              final raw = await jsSubmit!(formSel);
              final json = _decodeJsJson(raw);
              if (json == null || json['ok'] != true) {
                final msg = json?['message'];
                return '[error: 表单提交失败${msg != null ? ': $msg' : ''}'
                    '（form="$formSel"）。'
                    '→ 检查表单选择器，或先 page_fill 填充必填字段后重试。]';
              }
              // P1-D：提交 = 主动交互产出（不算空转）
              exploreWorkflow.noteSecondaryExploration();
              final outAction = (json['action'] as String? ?? '').trim();
              final method = (json['method'] as String? ?? '').trim();
              final title = (json['title'] as String? ?? '').trim();
              final url = (json['url'] as String? ?? '').trim();
              return '✅ 已提交表单'
                  '（${method.isEmpty ? '?' : method}'
                  '${outAction.isNotEmpty ? ' action=$outAction' : ''}）'
                  '${title.isNotEmpty ? '\n页面标题: $title' : ''}'
                  '${url.isNotEmpty ? '\n当前 URL: $url' : ''}'
                  '\n已捕获请求 ${exploreWorkflow.requestsCaptured} 条'
                  '（登录/搜索接口在此，可 list_captured_requests 回读）';
            } catch (e) {
              debugPrint('[PageSubmit] 💥 $e');
              return '[error: 提交执行异常: $e]';
            }
          },
        );
}

/// 工具：滚动当前页面（bottom/top/up/down，触发懒加载）。
///
/// P1-D：列表/瀑布流页面数据靠滚动懒加载，滚动到底后新请求进入捕获日志。
/// 返回滚动前后位置与已捕获请求数。只读操作，无需授权。
class PageScrollTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;

  /// 页面滚动通道（桥层注入）。
  final Future<String?> Function(String direction)? jsScroll;

  PageScrollTool({
    required this.exploreWorkflow,
    this.jsScroll,
  }) : super(
          name: 'page_scroll',
          description: '滚动当前页面（bottom=滚到底部触发懒加载 / top=回顶部 / '
              'up / down=半屏滚动）。滚动后返回滚动位置与已捕获请求数，'
              '可 explore_network_resources / list_captured_requests 回读'
              '懒加载触发的新请求。只读操作，无需授权。',
          schema: const {
            'type': 'object',
            'properties': {
              'direction': {
                'type': 'string',
                'enum': ['bottom', 'top', 'up', 'down'],
                'description': 'bottom=到底部（触发懒加载）、top=回顶部、'
                    'up/down=半屏滚动',
              },
            },
            'required': ['direction'],
          },
          readOnly: true,
          execute: (args) async {
            final direction = (args['direction'] as String? ?? '').trim().toLowerCase();
            if (direction.isEmpty) {
              return '[error: direction 参数为空（bottom/top/up/down）]';
            }
            if (jsScroll == null) return _pageOpChannelError('page_scroll');
            try {
              final raw = await jsScroll!(direction);
              final json = _decodeJsJson(raw);
              if (json == null || json['ok'] != true) {
                final msg = json?['message'];
                return '[error: 滚动失败${msg != null ? ': $msg' : ''}]';
              }
              // P1-D：滚动 = 主动交互产出（懒加载触发不算空转）
              exploreWorkflow.noteSecondaryExploration();
              final from = json['from'];
              final to = json['to'];
              final max = json['max'];
              final title = (json['title'] as String? ?? '').trim();
              final url = (json['url'] as String? ?? '').trim();
              final dirLabel = switch (direction) {
                'bottom' => '页面底部',
                'top' => '页面顶部',
                _ => direction,
              };
              return '✅ 已滚动到 $dirLabel'
                  '（y: ${from ?? '?'} → ${to ?? '?'} / 最大 ${max ?? '?'}）'
                  '${title.isNotEmpty ? '\n页面标题: $title' : ''}'
                  '${url.isNotEmpty ? '\n当前 URL: $url' : ''}'
                  '\n已捕获请求 ${exploreWorkflow.requestsCaptured} 条'
                  '（懒加载请求可 explore_network_resources / '
                  'list_captured_requests 回读）';
            } catch (e) {
              debugPrint('[PageScroll] 💥 $e');
              return '[error: 滚动执行异常: $e]';
            }
          },
        );
}

// ═══════ explore_page_links ═══════

/// 工具：枚举当前页 http(s) 链接（GET 探索起点）。
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
                return '[error: 浏览器 JS 通道不可用或页面未就绪。'
                    '→ 先调用 check_explore_ready 确认 WebView 是否已加载页面；'
                    '若页面尚未加载，可 navigate_get 访问目标页后再枚举链接；'
                    '若持续失败，请 ask 用户确认浏览器已打开目标网站并刷新页面。]';
              }
              // P1-B：枚举成功 = 二次探索产出（重访后重新枚举不算空转）
              exploreWorkflow.noteSecondaryExploration();
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

// ═══════ explore_network_resources（Phase 8 · 动态接口发现）═══════

/// 工具：枚举当前页运行时加载的资源 URL（Performance API，含 fetch/XHR）。
class ExploreNetworkResourcesTool extends SimpleTool {
  final ExploreWorkflow exploreWorkflow;
  final Future<String?> Function(String script) evaluateJs;

  ExploreNetworkResourcesTool({
    required this.exploreWorkflow,
    required this.evaluateJs,
  }) : super(
          name: 'explore_network_resources',
          description: '枚举当前页面运行时已加载的资源 URL（fetch/XHR/script/img/css 等，'
              '经 Performance API resource 时间线）。用于发现 SPA 站点无 <a href> 锚点的'
              '动态数据接口。返回 url + initiatorType（fetch/xmlhttprequest 等），'
              '同域过滤。只返回清单，不触发新请求。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            try {
              final raw = await evaluateJs(exploreNetworkResourcesScript);
              final json = _decodeJsJson(raw);
              if (json == null) {
                return '[error: 浏览器 JS 通道不可用或页面未就绪。'
                    '→ 先调用 check_explore_ready 确认 WebView 是否已加载页面；'
                    '若页面尚未加载，可 navigate_get 访问目标页后再枚举资源；'
                    '若持续失败，请 ask 用户确认浏览器已打开目标网站并刷新页面。]';
              }
              // P1-B：资源枚举成功 = 二次探索产出（SPA 重访后重新枚举不算空转）
              exploreWorkflow.noteSecondaryExploration();
              final count = json['count'] as int? ?? 0;
              final resources =
                  (json['resources'] as List<dynamic>? ?? const [])
                      .whereType<Map<String, dynamic>>()
                      .toList();
              if (resources.isEmpty) {
                return '当前页共 0 个运行时资源。'
                    '可继续 navigate_get 探索，或结束探索进入归类。';
              }
              final base = exploreWorkflow.baseHost;
              final buf = StringBuffer();
              buf.writeln('当前页共 $count 个运行时资源'
                  '${base.isNotEmpty ? '（同域 $base）' : ''}：');
              var shown = 0;
              for (final r in resources) {
                final url = (r['url'] as String? ?? '').trim();
                if (url.isEmpty) continue;
                if (validateExploreUrl(url, baseHost: base) != null) continue;
                final initiator = (r['initiatorType'] as String? ?? '').trim();
                buf.writeln('- $url'
                    '${initiator.isNotEmpty ? '  # $initiator' : ''}');
                if (++shown >= 100) {
                  buf.writeln('…（其余 ${count - shown} 个资源已截断）');
                  break;
                }
              }
              if (shown == 0) {
                buf.writeln('（所有资源均为非同域，已按守卫过滤）');
              }
              return buf.toString();
            } catch (e) {
              debugPrint('[ExploreNetworkResources] 💥 $e');
              return '[error: 枚举运行时资源失败: $e]';
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
              '页数上限（默认 20 页，分页参数 page/p/pn/pageNum 归一同页）；'
              '请求上限（默认 50，按真实捕获日志计数）；1s 节流；'
              '空转熔断（连续 3 次导航无新页面触发，熔断期间重复访问'
              '已探索页面会被拒绝——可对当前页重新枚举链接/资源或读取日志'
              '（二次探索）解除熔断，或换新链接 / 结束探索进入归类，'
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
            'properties': {
              'offset': {
                'type': 'integer',
                'description': '分页起始下标（默认 0）。用于翻页读取超过 100 条的日志。',
              },
              'limit': {
                'type': 'integer',
                'description': '单页返回条数（默认 100，上限 200）。',
              },
            },
          },
          readOnly: true,
          execute: (args) async {
            // P1-B：读日志 = 二次探索产出（重访后重读日志不算空转）；
            // 同时按真实捕获条数同步请求计数（AI 看到的请求数 = 日志条数）
            exploreWorkflow.noteSecondaryExploration();
            exploreWorkflow.syncCapturedRequests(captureWorkflow.logs.length);
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
              return '(暂无捕获日志) 请先在浏览器中浏览/探索目标页面：'
                  '可 navigate_get 访问疑似数据接口（列表页/详情页），'
                  '页面加载后再次调用本工具读取捕获日志。'
                  '若导航后仍无日志，请调用 check_explore_ready 检查浏览器通道，'
                  '或 ask 用户确认页面已加载/已登录。';
            }
            // Phase 9：分页读取（offset/limit），默认 100，上限 200。
            final rawOffset = args['offset'];
            final rawLimit = args['limit'];
            int offset = 0;
            int limit = 100;
            if (rawOffset is num) {
              offset = rawOffset.toInt().clamp(0, logs.length).toInt();
            }
            if (rawLimit is num) {
              limit = rawLimit.toInt().clamp(1, 200).toInt();
            }
            final start = offset < logs.length ? offset : logs.length;
            final end = (start + limit).clamp(0, logs.length).toInt();
            final page = logs.sublist(start, end);

            final buf = StringBuffer();
            buf.writeln('## 捕获的请求日志（${logs.length} 条'
                '${base.isNotEmpty ? ' · 同域 $base' : ''}'
                '，第 ${start + 1}-$end 条）\n');
            for (var i = 0; i < page.length; i++) {
              final log = page[i];
              final idLabel =
                  log.id.isNotEmpty ? ' · 证据 id: ${log.id}' : '';
              buf.writeln('### 请求 #${start + i + 1}$idLabel');
              buf.writeln(log.toAiSummary());
              buf.writeln();
            }
            if (end < logs.length) {
              buf.writeln('…（其余 ${logs.length - end} 条，'
                  '用 offset=$end 继续读取）');
            }
            return buf.toString();
          },
        );
}

// ═══════ read_request_by_id（Phase 9 · 按证据 id 读全文）══════

/// 工具：按证据 id 读取单条捕获请求的完整内容（headers/body/responseBody）。
///
/// list_captured_requests 的摘要会截断响应体（toAiSummary 只保留前 2048 字符），
/// 归类大字段时证据不足。本工具按 `log-N` 证据 id 返回单条日志全文，
/// 供 AI 精确核对字段路径与响应结构。
class ReadRequestByIdTool extends SimpleTool {
  final ScraperWorkflow captureWorkflow;

  /// P1-B：读日志工具注入探索工作流——按证据 id 精读视为二次探索产出
  /// （重访后重读不算空转），并同步真实请求计数。
  final ExploreWorkflow? exploreWorkflow;

  ReadRequestByIdTool({
    required this.captureWorkflow,
    this.exploreWorkflow,
  }) : super(
          name: 'read_request_by_id',
          description: '按证据 id（log-N）读取单条捕获请求的完整内容'
              '（method/url/headers/body/responseBody 全文，不再截断）。'
              '用于归类大字段/嵌套结构时精确核对字段路径与响应体。'
              'id 来自 list_captured_requests 返回的「证据 id: log-N」。',
          schema: const {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': '证据 id（如 log-7）',
              },
            },
            'required': ['id'],
          },
          readOnly: true,
          execute: (args) async {
            // P1-B：读单条日志同样算二次探索产出（按 id 精读 = 主动分析）。
            exploreWorkflow?.noteSecondaryExploration();
            exploreWorkflow?.syncCapturedRequests(captureWorkflow.logs.length);
            final id = (args['id'] as String? ?? '').trim();
            if (id.isEmpty) return '[error: id 参数为空]';
            HttpRequestLog? found;
            for (final l in captureWorkflow.logs) {
              if (l.id.isNotEmpty && sameLogRef(l.id, id)) {
                found = l;
                break;
              }
            }
            if (found == null) {
              return '[error: 未找到证据 id "$id" 的请求日志'
                  '（可用 list_captured_requests 查看全部证据 id）]';
            }
            final buf = StringBuffer();
            buf.writeln('## 请求证据 $id（全文）');
            buf.writeln('method: ${found.method}');
            buf.writeln('url: ${found.url}');
            // P2-2：状态码/资源类型/响应头（Set-Cookie 登录态）全量返回，
            // AI 据此区分 200/401/403、识别登录态建立
            if (found.statusCode != null) {
              buf.writeln('statusCode: ${found.statusCode}');
            }
            if (found.resourceType != null &&
                found.resourceType!.isNotEmpty) {
              buf.writeln('resourceType: ${found.resourceType}');
            }
            if (found.headers != null && found.headers!.isNotEmpty) {
              buf.writeln('headers:');
              found.headers!.forEach((k, v) => buf.writeln('  $k: $v'));
            }
            if (found.responseHeaders != null &&
                found.responseHeaders!.isNotEmpty) {
              buf.writeln('responseHeaders:');
              found.responseHeaders!
                  .forEach((k, v) => buf.writeln('  $k: $v'));
            }
            if (found.body != null && found.body!.isNotEmpty) {
              buf.writeln('body (${found.body!.length} chars):\n${found.body}');
            }
            if (found.responseBody != null &&
                found.responseBody!.isNotEmpty) {
              buf.writeln(
                  'responseBody (${found.responseBody!.length} chars):\n${found.responseBody}');
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
            // Phase 10：探索充分性门槛——0 导航且无捕获日志时禁止归类。
            if (!exploreWorkflow.explorationSufficient &&
                captureWorkflow.logs.isEmpty) {
              final minPages = exploreWorkflow.limits.minPagesForCategorize;
              final minReqs = exploreWorkflow.limits.minRequestsForCategorize;
              final thresholdText = [
                if (minPages > 0) '$minPages 页',
                if (minReqs > 0) '$minReqs 请求',
              ].join(' 且 ');
              return '[error: 探索不充分，禁止过早归类'
                  '（已访问 ${exploreWorkflow.uniquePages} 页 / '
                  '${exploreWorkflow.requestsCaptured} 请求，'
                  '至少需 ${thresholdText.isEmpty ? '完成一次有效导航' : thresholdText}）。'
                  '→ 请先 navigate_get 探索目标站点，或确保已有捕获日志证据后重试；'
                  '若导航一直失败，先 check_explore_ready 检查浏览器通道是否就绪'
                  '（页面未加载/未登录），或 ask 用户确认页面状态后重试。]';
            }
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

// ═══════ verify_login_flow（Phase 2 · 登录态前置验证）═══════

/// 工具：执行 AI 生成的「登录片段」并回传结果（探索模式构建前的登录验证）。
///
/// 探索模式全程禁用 run_python_scraper（它写 scraper.py 且与探索语义冲突），
/// 因此单独提供本工具：AI 把登录代码（CAS/表单/Cookie 流程）写入临时脚本执行，
/// 依据 stdout/stderr 判断登录是否成功（如 HTTP 200 / session 建立 / 无 401），
/// 成功后才会进入 build_selected_source 写业务脚本。
class VerifyLoginFlowTool extends SimpleTool {
  /// 执行登录片段并返回 stdout/stderr 的回调（UI 层注入：写 login_check.py + 运行）。
  final Future<String> Function(String code) runLoginCheck;

  VerifyLoginFlowTool({required this.runLoginCheck})
      : super(
          name: 'verify_login_flow',
          description: '执行一段「仅登录」的 Python 代码，验证登录流程是否可复现。'
              '在构建任何数据源脚本前，若目标接口需要登录（Cookie/Token/表单/CAS），'
              '必须先用本工具跑通登录并确认成功（stdout 无 401/登录失败）。'
              'code 为完整登录片段（可含 import + 登录函数 + main 自测），'
              '凭证通过锁定模板 _get_config(key) 读取（用户已在设置面板填写）。'
              '登录验证成功后再逐个 build_selected_source。',
          schema: const {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': '仅登录用的完整 Python 代码（含 _get_config 凭证读取与登录自测输出）',
              },
            },
            'required': ['code'],
          },
          readOnly: false,
          execute: (args) async {
            final code = args['code'] as String? ?? '';
            if (code.isEmpty) return '[error: code 参数为空]';
            try {
              return await runLoginCheck(code);
            } catch (e) {
              debugPrint('[VerifyLoginFlow] 💥 $e');
              return '[error: 登录验证执行异常: $e]';
            }
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

// ═══════ execute_built_source（Phase 3 · 批量执行结果回传）═══════

/// 工具：执行某个已构建的数据源脚本（data-{name}/data/scraper.py）并回传 stdout/stderr。
///
/// build_selected_source 只写盘不运行；register_batch 的 orch.get 也只回「非 null/异常」。
/// 本工具让 AI 在注册前**逐个真实执行**已构建脚本，看到真实 stdout（JSON 样本）与
/// stderr，从而在注册前自证脚本能跑通、字段与声明一致，而不是靠猜。
class ExecuteBuiltSourceTool extends SimpleTool {
  /// 执行已构建脚本并返回 stdout/stderr 的回调（UI 层注入）。
  final Future<String> Function(String name) runBuiltSource;

  ExecuteBuiltSourceTool({required this.runBuiltSource})
      : super(
          name: 'execute_built_source',
          description: '执行某个已构建数据源的脚本（plugins/data-{name}/data/scraper.py），'
              '返回真实 stdout（数据 JSON 样本）与 stderr。'
              '用于 register_batch 之前对每个已构建脚本做真实执行验证：'
              '确认脚本能跑通、输出合法 JSON、字段与归类声明一致。'
              '若执行失败/输出非 JSON/缺字段，用 build_selected_source 修正后重试。',
          schema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': '数据源名称（已构建的 data-{name}）',
              },
            },
            'required': ['name'],
          },
          readOnly: false,
          execute: (args) async {
            final name = (args['name'] as String? ?? '').trim();
            if (name.isEmpty) return '[error: name 参数为空]';
            final err = sanitizeSourceName(name);
            if (err != null) return '[error: 数据源名称非法: $err]';
            try {
              return await runBuiltSource(name);
            } catch (e) {
              debugPrint('[ExecuteBuiltSource] 💥 $e');
              return '[error: 执行 data-$name 脚本异常: $e]';
            }
          },
        );
}

// ═══════ check_explore_ready（诊断工具：区分「AI 自身错误」vs「环境未就绪」）═══════

/// 工具：检查探索环境就绪状态（WebView/捕获/Python/阶段），返回诊断报告。
///
/// 背景（用户反馈 bug）：探索模式频繁「卡在某一步失败」，AI 分不清是
/// 自己代码/行为的问题还是浏览器通道坏了，于是反复抱怨工具设计。
/// 本工具给出环境事实，AI 据此自检：桥未就绪 → 等页面加载/ask 用户刷新；
/// 桥就绪但无日志 → 是导航/页面问题（自己的行为）；Python 不可用 → 环境问题。
class CheckExploreReadyTool extends SimpleTool {
  /// 生成就绪诊断报告的回调（UI 层注入，可访问 webBridge/exploreWorkflow）。
  final Future<String> Function() checkReady;

  CheckExploreReadyTool({required this.checkReady})
      : super(
          name: 'check_explore_ready',
          description: '诊断探索环境就绪状态并返回报告：WebView 是否已加载页面、'
              '浏览器 JS 通道是否可用、已捕获请求数、已访问页数、Python 是否可用、'
              '当前探索阶段。当 explore_page_links / navigate_get / '
              'list_captured_requests 持续报错时，先调用本工具定位是'
              '「浏览器/页面未就绪」还是「探索行为问题」，再对症处理，'
              '不要盲目重试同一工具。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            try {
              return await checkReady();
            } catch (e) {
              debugPrint('[CheckExploreReady] 💥 $e');
              return '[error: 环境诊断执行异常: $e]';
            }
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
/// - [jsClick] / [jsFill] / [jsSubmit] / [jsScroll] — P1-D 页面操作通道
///   （点击/填表/提交/滚动；全部经桥层 _evaluateJs 注入合成事件脚本）
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
  Future<String?> Function(String selector)? jsClick,
  Future<String?> Function(String selector, String value)? jsFill,
  Future<String?> Function(String formSelector)? jsSubmit,
  Future<String?> Function(String direction)? jsScroll,
  required Future<List<CandidateDataSource>> Function(
      List<CandidateDataSource> candidates) presentSources,
  required Future<String> Function(String name, String code) buildSource,
  required Future<String> Function(List<String> names) registerBatch,
  required Future<String> Function(String code) verifyLoginFlow,
  required Future<String> Function(String name) executeBuiltSource,
  List<String> Function()? listPythonCapabilities,
  ScraperEnvStore? envStore,
  String? workspaceDir,
  Future<bool> Function(String toolName, String reason)? requestOverride,
  Future<String> Function()? checkExploreReady,
}) {
  return [
    ExplorePageLinksTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
    ),
    ExploreNetworkResourcesTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
    ),
    // P1-C：导航后快照判型（解决"导航后失明"）
    ExplorePageSnapshotTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
    ),
    // P1-D：AI 页面操作工具（点击/填表/提交/滚动——触达"交互后才出现"的深层接口）
    PageClickTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
      jsClick: jsClick,
    ),
    PageFillTool(
      exploreWorkflow: exploreWorkflow,
      jsFill: jsFill,
    ),
    PageSubmitTool(
      exploreWorkflow: exploreWorkflow,
      evaluateJs: evaluateJs,
      jsSubmit: jsSubmit,
    ),
    PageScrollTool(
      exploreWorkflow: exploreWorkflow,
      jsScroll: jsScroll,
    ),
    NavigateGetTool(
      exploreWorkflow: exploreWorkflow,
      navigateTo: navigateTo,
    ),
    ListCapturedRequestsTool(
      captureWorkflow: captureWorkflow,
      exploreWorkflow: exploreWorkflow,
    ),
    ReadRequestByIdTool(
      captureWorkflow: captureWorkflow,
      exploreWorkflow: exploreWorkflow,
    ),
    ListPythonCapabilitiesTool(
      listCapabilities: listPythonCapabilities ?? () => const [],
    ),
    // 环境变量写入/列出（探索模式凭据路径：账号密码写入 .greenix/env.json
    // 并注入子进程环境变量——修复「探索模式无法写环境变量」）
    if (envStore != null) ...[
      SetEnvVarTool(envStore: envStore),
      ListEnvVarsTool(envStore: envStore),
    ],
    // 工作区文件读取（白名单已放行但此前未注册 → AI 调用报"工具不存在"）
    if (workspaceDir != null) ReadWorkspaceFileTool(workspaceDir: workspaceDir),
    // 环境诊断（区分「AI 自身错误」vs「浏览器未就绪」）
    if (checkExploreReady != null)
      CheckExploreReadyTool(checkReady: checkExploreReady),
    // 门控一次性豁免（白名单已放行但此前未注册；被 lint/证据拦截时可请求用户放行）
    if (requestOverride != null)
      GuardOverrideTool(requestOverride: requestOverride),
    PresentDataSourcesTool(
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
      presentSources: presentSources,
    ),
    VerifyLoginFlowTool(runLoginCheck: verifyLoginFlow),
    BuildSelectedSourceTool(
      buildSource: buildSource,
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
    ),
    ExecuteBuiltSourceTool(runBuiltSource: executeBuiltSource),
    RegisterBatchTool(
      registerBatch: registerBatch,
      exploreWorkflow: exploreWorkflow,
      captureWorkflow: captureWorkflow,
    ),
  ];
}

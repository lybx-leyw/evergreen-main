/// AI 答疑面板 — 自管 API 调用（论文上下文注入 + function calling），
///   渲染层用 v4 的 MarkdownRenderer / ThinkingBlock。
library;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/config/settings.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/markdown_renderer.dart';
import '../paper_reading_state.dart';

// ═══════════════ 工具调用数据 ═══════════════

class _ToolCall {
  final String id;
  String name;
  String arguments;
  String status;
  String? result;
  String? error;

  _ToolCall({required this.id, required this.name, required this.arguments,
    this.status = 'pending', this.result, this.error});

  Map<String, dynamic> get parsedArgs {
    try { return jsonDecode(arguments) as Map<String, dynamic>; }
    catch (_) { return {}; }
  }
}

// ═══════════════ 消息模型 ═══════════════

class _ChatMessage {
  final String role;
  final String rawContent;
  String? reasoning;
  String content;
  List<_ToolCall>? toolCalls;

  _ChatMessage({required this.role, required this.rawContent,
    this.reasoning, required this.content, this.toolCalls});
}

// ═══════════════ Function Calling 工具定义 ═══════════════

const _tools = [
  {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': '搜索网络获取最新信息。需要联网获取的内容时使用。',
      'parameters': {
        'type': 'object',
        'properties': {'query': {'type': 'string', 'description': '搜索关键词'}},
        'required': ['query'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'web_fetch',
      'description': '获取指定URL的文本内容。需要查看网页具体内容时使用。',
      'parameters': {
        'type': 'object',
        'properties': {'url': {'type': 'string', 'description': '网页地址'}},
        'required': ['url'],
      },
    },
  },
];

// ═══════════════ 主组件 ═══════════════

class AiAssistantPanel extends ConsumerStatefulWidget {
  final String paperId;
  const AiAssistantPanel({super.key, required this.paperId});
  @override ConsumerState<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends ConsumerState<AiAssistantPanel>
    with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _history = [];
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 120)));
  bool _loading = false;
  bool _webSearch = false;
  final _responseBuf = StringBuffer();
  String? _streamingReasoning;

  late final AnimationController _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);
  late final Animation<double> _pulseAnim = Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override void dispose() { _ctrl.dispose(); _scrollCtrl.dispose(); _dio.close(); _pulseCtrl.dispose(); _elapsedTimer?.cancel(); super.dispose(); }

  String _apiKey() { try { return getSetting(ref.read(sharedPreferencesProvider), 'DEEPSEEK_API_KEY') ?? ''; } catch (_) { return ''; } }
  String _model() { try { return getSetting(ref.read(sharedPreferencesProvider), 'DEEPSEEK_MODEL') ?? 'deepseek-v4-flash'; } catch (_) { return 'deepseek-v4-flash'; } }

  // ═══════════════ 上下文构建 ═══════════════

  List<Map<String, dynamic>> _buildMessages(String userMsg, {List<Map<String, dynamic>>? extraMsgs}) {
    final paper = selectedPaper(ref);
    final chapter = currentChapter(ref);
    final paragraph = currentParagraph(ref);
    final fullText = paper != null ? (ref.read(fullTextProvider)[paper.id] ?? '') : '';

    final sys = StringBuffer();
    sys.writeln('你是论文阅读助手。中文回答，简洁专业。');
    sys.writeln(r'数学公式必须用 $$...$$（显示）或 $...$（行内），禁止 \(..\) \[..\]。');
    if (chapter != null && paragraph != null) {
      sys.writeln('用户正在阅读章节: ${chapter.title}，段落: "${paragraph.content.substring(0, paragraph.content.length.clamp(0, 500))}"');
    }
    if (fullText.isNotEmpty) {
      sys.writeln('论文全文(截取): ${fullText.substring(0, fullText.length.clamp(0, 6000))}');
    }

    final msgs = <Map<String, dynamic>>[{'role': 'system', 'content': sys.toString()}];
    for (final h in _history) {
      if (h.toolCalls != null && h.toolCalls!.isNotEmpty) {
        final tcList = h.toolCalls!.map((tc) => {
          'id': tc.id, 'type': 'function', 'function': {'name': tc.name, 'arguments': tc.arguments},
        }).toList();
        msgs.add(h.rawContent.isEmpty
            ? {'role': 'assistant', 'tool_calls': tcList}
            : {'role': 'assistant', 'tool_calls': tcList, 'content': h.rawContent});
      } else {
        msgs.add({'role': h.role, 'content': h.rawContent});
      }
    }
    if (extraMsgs != null) msgs.addAll(extraMsgs);
    msgs.add({'role': 'user', 'content': userMsg});
    return msgs;
  }

  // ═══════════════ 发送 ═══════════════

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    final apiKey = _apiKey();
    if (apiKey.isEmpty) {
      setState(() => _history.add(_ChatMessage(role: 'assistant', rawContent: '❌ 未配置 API Key', content: '❌ 未配置 API Key')));
      return;
    }
    _ctrl.clear();
    setState(() { _history.add(_ChatMessage(role: 'user', rawContent: text, content: text)); _loading = true; _responseBuf.clear(); _elapsedSeconds = 0; _startTimer(); });
    _scrollToBottom();

    try {
      final msgs = _buildMessages(text);
      final (toolCalls, content) = await _streamWithTools(msgs, apiKey);
      if (toolCalls.isNotEmpty && content.isEmpty) {
        await _handleToolCalls(toolCalls, msgs, text, apiKey);
      } else {
        final raw = content.isNotEmpty ? content : _responseBuf.toString();
        final (reasoningT, body) = _extractReasoning(raw);
        if (mounted) setState(() {
          _history.add(_ChatMessage(role: 'assistant', rawContent: raw, reasoning: _streamingReasoning ?? reasoningT, content: body));
          _responseBuf.clear(); _streamingReasoning = null; _loading = false; _stopTimer();
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _history.add(_ChatMessage(role: 'assistant', rawContent: '❌ $e', content: '❌ $e'));
        _responseBuf.clear(); _streamingReasoning = null; _loading = false; _stopTimer();
      });
    }
    _scrollToBottom();
  }

  // ═══════════════ 流式 API ═══════════════

  Future<(List<_ToolCall>, String)> _streamWithTools(List<Map<String, dynamic>> msgs, String apiKey) async {
    final data = <String, dynamic>{
      'model': _model(), 'messages': msgs, 'stream': true, 'temperature': 0.7, 'max_tokens': 8192,
      if (_webSearch) ...{'tools': _tools, 'tool_choice': 'auto'},
    };
    debugPrint('[AI] webSearch=$_webSearch hasTools=${_webSearch}');

    final stream = await _dio.post('https://api.deepseek.com/v1/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'}, responseType: ResponseType.stream),
      data: data,
    );

    final toolCalls = <int, _ToolCall>{};
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();

    await for (final chunk in stream.data.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      if (!chunk.startsWith('data: ')) continue;
      final d = chunk.substring(6).trim();
      if (d == '[DONE]') break;
      try {
        final j = jsonDecode(d);
        final delta = j['choices']?[0]?['delta'];
        final tc = delta?['content']; if (tc != null) { contentBuf.write(tc); _responseBuf.write(tc); if (mounted) setState(() {}); }
        final rc = delta?['reasoning_content']; if (rc != null) { reasoningBuf.write(rc); if (mounted) setState(() {}); }
        final tcs = delta?['tool_calls'] as List?;
        if (tcs != null) for (final t in tcs) {
          final idx = t['index'] as int;
          toolCalls.putIfAbsent(idx, () => _ToolCall(id: t['id']?.toString() ?? 'call_$idx', name: '', arguments: ''));
          if (t['function']?['name'] != null) toolCalls[idx]!.name = t['function']['name'] as String;
          if (t['function']?['arguments'] != null) toolCalls[idx]!.arguments += t['function']['arguments'] as String;
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
    _streamingReasoning = reasoningBuf.isNotEmpty ? reasoningBuf.toString() : null;
    return (toolCalls.values.toList(), contentBuf.toString());
  }

  // ═══════════════ 工具执行 ═══════════════

  Future<void> _handleToolCalls(List<_ToolCall> tcs, List<Map<String, dynamic>> msgs, String userText, String apiKey) async {
    final toolMsg = _ChatMessage(role: 'assistant', rawContent: '', content: '', toolCalls: tcs);
    setState(() => _history.add(toolMsg)); _scrollToBottom();

    final results = <Map<String, dynamic>>[];
    for (final tc in tcs) {
      setState(() => tc.status = 'running');
      try {
        if (tc.name == 'web_search') tc.result = await _execWebSearch(tc.parsedArgs['query']?.toString() ?? '');
        else if (tc.name == 'web_fetch') tc.result = await _execWebFetch(tc.parsedArgs['url']?.toString() ?? '');
        else tc.result = '[未知: ${tc.name}]';
        tc.status = 'done';
      } catch (e) { tc.status = 'error'; tc.error = e.toString(); tc.result = '[失败: $e]'; }
      results.add({'role': 'tool', 'tool_call_id': tc.id, 'content': tc.result ?? ''});
      if (mounted) setState(() {});
    }

    _responseBuf.clear();
    final fullMsgs = _buildMessages(userText, extraMsgs: results);
    fullMsgs.removeLast(); fullMsgs.add({'role': 'user', 'content': userText});

    try {
      final (_, content) = await _streamWithTools(fullMsgs, apiKey);
      final raw = content.isNotEmpty ? content : _responseBuf.toString();
      final (reasoningT, body) = _extractReasoning(raw);
      if (mounted) setState(() {
        _history.add(_ChatMessage(role: 'assistant', rawContent: raw, reasoning: _streamingReasoning ?? reasoningT, content: body));
        _responseBuf.clear(); _streamingReasoning = null; _loading = false; _stopTimer();
      });
    } catch (e) {
      if (mounted) setState(() {
        _history.add(_ChatMessage(role: 'assistant', rawContent: '❌ $e', content: '❌ $e'));
        _streamingReasoning = null; _loading = false; _stopTimer();
      });
    }
  }

  /// 抓取 Bing 搜索结果。
  /// ⚠️ 依赖 cn.bing.com 的 HTML 结构（`<li class="b_algo">` 等），Bing 改版则失效。
  ///    如需更可靠方案，可接入 SearXNG 或 SerpAPI。
  Future<String> _execWebSearch(String query) async {
    for (final host in ['https://cn.bing.com', 'https://www.bing.com']) {
      try {
        final r = await _dio.get('$host/search', queryParameters: {'q': query, 'cc': 'cn'},
          options: Options(receiveTimeout: const Duration(seconds: 10),
            headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', 'Accept-Language': 'zh-CN,zh;q=0.9'}));
        final html = r.data?.toString() ?? '';
        if (html.isEmpty) continue;
        final results = <String>[];
        for (final m in RegExp(r'<li class="b_algo"[^>]*>(.*?)</li>', dotAll: true).allMatches(html)) {
          if (results.length >= 5) break;
          final b = m.group(1)!;
          final tm = RegExp(r'<h2[^>]*>.*?<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true).firstMatch(b);
          final sm = RegExp(r'<p class="b_lineclamp[^"]*"[^>]*>(.*?)</p>', dotAll: true).firstMatch(b);
          final tag = RegExp(r'<[^>]+>');
          if (tm != null) results.add('${results.length + 1}. ${tm.group(2)!.replaceAll(tag, '').trim()}\n   ${sm?.group(1)?.replaceAll(tag, '').trim() ?? ''}\n   ${tm.group(1)!}');
        }
        return results.isNotEmpty ? '搜索 "$query":\n${results.join('\n\n')}' : '未找到结果';
      } catch (_) {}
    }
    return '搜索失败';
  }

  Future<String> _execWebFetch(String url) async {
    final r = await _dio.get(url, options: Options(receiveTimeout: const Duration(seconds: 30), followRedirects: true,
      headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}));
    var t = r.data?.toString() ?? '';
    t = t.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
    t = t.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return '网页 ($url):\n${t.length > 4000 ? '${t.substring(0, 4000)}...' : t}';
  }

  // ═══════════════ 计时/滚动/reasoning ═══════════════

  void _startTimer() { _elapsedTimer?.cancel(); _elapsedSeconds = 0; _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _elapsedSeconds++); }); }
  void _stopTimer() { _elapsedTimer?.cancel(); _elapsedTimer = null; }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollCtrl.hasClients && mounted) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut); });

  (String?, String) _extractReasoning(String raw) {
    final m = RegExp(r':::reasoning\s*\n(.*?)\n\s*:::', dotAll: true).firstMatch(raw);
    if (m == null) return (null, raw);
    return (m.group(1)?.trim(), raw.replaceFirst(m.group(0)!, '').trim());
  }

  // ═══════════════ 重新生成 ═══════════════

  void _regenerate(int index, String lastUser) {
    if (_loading) return;
    setState(() => _history.removeRange(index - 1, _history.length));
    _ctrl.text = lastUser;
    _send();
  }

  // ═══════════════ Build ═══════════════

  @override
  Widget build(BuildContext context) {
    final chapter = currentChapter(ref);
    return Column(children: [
      if (_loading) AnimatedBuilder(animation: _pulseAnim, builder: (_, __) =>
        Container(width: double.infinity, height: 3, color: const Color(0xFF8B6914).withAlpha((60 + (_pulseAnim.value * 100)).toInt()))),

      Container(width: double.infinity, padding: const EdgeInsets.all(6), color: const Color(0xFF8B6914).withAlpha(15),
        child: Row(children: [
          const Text('📎 全文+段落', style: TextStyle(fontSize: 10, color: Color(0xFF8B6914))), const Spacer(),
          GestureDetector(onTap: () => setState(() => _webSearch = !_webSearch),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _webSearch ? const Color(0xFF4A90D9).withAlpha(40) : null, borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search, size: 12, color: _webSearch ? const Color(0xFF4A90D9) : Colors.grey),
                const Text('web', style: TextStyle(fontSize: 10, color: Color(0xFF8B6914))),
              ]))),
          if (chapter != null) ...[const SizedBox(width: 8), Expanded(child: Text(chapter.title, style: const TextStyle(fontSize: 10, color: Color(0xFF8B6914)), overflow: TextOverflow.ellipsis))],
        ])),

      Expanded(child: _history.isEmpty && !_loading
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.psychology_outlined, size: 40, color: Colors.grey[300]), Text('基于全文+当前段落提问', style: TextStyle(color: Colors.grey[400], fontSize: 13))]))
        : ListView.builder(controller: _scrollCtrl, padding: const EdgeInsets.all(10),
            itemCount: _history.length + (_loading ? 1 : 0), itemBuilder: (_, i) => i < _history.length ? _buildMsg(i) : _buildStreaming())),

      Container(padding: const EdgeInsets.all(8), color: const Color(0xFFEDE5D5),
        child: Row(children: [
          Expanded(child: TextField(controller: _ctrl,
            decoration: InputDecoration(hintText: '基于全文+当前段落提问...', hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true, filled: true, fillColor: const Color(0xFFFFF8E7)),
            style: const TextStyle(fontSize: 13), maxLines: 3, minLines: 1, onSubmitted: (_) => _send())),
          const SizedBox(width: 8),
          IconButton(onPressed: _loading ? null : _send, icon: Icon(_loading ? Icons.stop : Icons.send, size: 20), style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B6914))),
        ])),
    ]);
  }

  // ═══════════════ 消息渲染 ═══════════════

  Widget _buildMsg(int i) {
    final m = _history[i]; final isUser = m.role == 'user';
    return Align(alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isUser ? const Color(0xFF8B6914).withAlpha(20) : Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.reasoning != null && m.reasoning!.isNotEmpty) _ThinkingBlock(content: m.reasoning!),
          if (m.toolCalls != null) for (final tc in m.toolCalls!) _ToolCard(call: tc),
          if (isUser) SelectableText(m.content, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF4A2C00)))
          else if (m.content.isNotEmpty) _renderAssistant(m.content),
          if (!isUser && m.content.isNotEmpty && m.toolCalls == null) _ActionBar(content: m.content, isLast: i == _history.length - 1, onRegen: () { for (int j = i - 1; j >= 0; j--) if (_history[j].role == 'user') { _regenerate(i, _history[j].rawContent); return; } }),
        ]),
      ),
    );
  }

  /// v4 MarkdownRenderer 渲染：
  ///   1. `$$...$$` → ```math 代码块（显示公式）
  ///   2. `$...$` → `math:...` 行内语法（MarkdownRenderer 内联渲染）
  Widget _renderAssistant(String text) {
    var t = text;
    // 先处理 $$，再处理 $（避免 $ 误匹配 $$ 残片）
    t = t.replaceAllMapped(RegExp(r'\$\$\s*(.+?)\s*\$\$', dotAll: true),
        (m) => '\n\n```math\n${(m.group(1) ?? '').trim()}\n```\n\n');
    t = t.replaceAllMapped(RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)'),
        (m) => 'math:${(m.group(1) ?? '').trim()}');
    return MarkdownRenderer(text: t, useCard: false, padding: EdgeInsets.zero, fontScale: 0.85);
  }

  Widget _buildStreaming() {
    final t = _responseBuf.toString();
    return Align(alignment: Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: t.isNotEmpty ? _renderAssistant(t) : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
  }
}

// ═══════════════ 思考过程（自实现，与 v4 风格一致） ═══════════════

class _ThinkingBlock extends StatefulWidget {
  final String content;
  const _ThinkingBlock({required this.content});
  @override State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: const Color(0xFF8B6914).withAlpha(10), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF8B6914).withAlpha(30))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(onTap: () => setState(() => _expanded = !_expanded), borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
          child: Row(children: [
            const Icon(Icons.psychology, size: 14, color: Color(0xFF8B6914)), const SizedBox(width: 6),
            const Text('思考过程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF8B6914))), const Spacer(),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: const Color(0xFF8B6914).withAlpha(150)),
          ]))),
      if (_expanded) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: SelectableText(widget.content, style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF6B4C00)))),
    ]),
  );
}

// ═══════════════ 工具调用卡片 ═══════════════

class _ToolCard extends StatelessWidget {
  final _ToolCall call;
  const _ToolCard({required this.call});
  @override
  Widget build(BuildContext context) {
    final icons = {'web_search': Icons.search, 'web_fetch': Icons.open_in_browser};
    final labels = {'web_search': '联网搜索', 'web_fetch': '获取网页'};
    final icon = icons[call.name] ?? Icons.build;
    final label = labels[call.name] ?? call.name;

    Color bg, fg;
    switch (call.status) {
      case 'running': bg = const Color(0xFF4A90D9).withAlpha(20); fg = const Color(0xFF4A90D9);
      case 'done': bg = const Color(0xFF50B86C).withAlpha(15); fg = const Color(0xFF50B86C);
      case 'error': bg = const Color(0xFFE06060).withAlpha(15); fg = const Color(0xFFE06060);
      default: bg = Colors.grey.shade100; fg = Colors.grey.shade600;
    }
    return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: fg.withAlpha(50))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 14, color: fg), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)), const Spacer(),
          if (call.status == 'running') const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
          else if (call.status == 'done') const Icon(Icons.check, size: 14, color: Color(0xFF50B86C))
          else if (call.status == 'error') const Icon(Icons.error, size: 14, color: Color(0xFFE06060))]),
        if (call.name == 'web_search') ...[const SizedBox(height: 4), SelectableText(call.parsedArgs['query']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))],
        if (call.name == 'web_fetch') ...[const SizedBox(height: 4), SelectableText(call.parsedArgs['url']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'))],
        if (call.status == 'error' && call.error != null) ...[const SizedBox(height: 4), Text(call.error!, style: const TextStyle(fontSize: 11, color: Color(0xFFE06060)))],
      ]));
  }
}

// ═══════════════ 操作栏 ═══════════════

class _ActionBar extends StatelessWidget {
  final String content; final bool isLast; final VoidCallback onRegen;
  const _ActionBar({required this.content, required this.isLast, required this.onRegen});
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
    _Chip(icon: Icons.content_copy, label: '复制', onTap: () { Clipboard.setData(ClipboardData(text: content)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1))); }),
    if (isLast) ...[const SizedBox(width: 4), _Chip(icon: Icons.refresh, label: '重新生成', onTap: onRegen)],
  ]);
}

class _Chip extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _Chip({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(4),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ])));
}

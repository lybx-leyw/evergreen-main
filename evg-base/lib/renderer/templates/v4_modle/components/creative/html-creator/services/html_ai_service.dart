/// HTML 创作 AI Agent —— 复用 AgentAssembly/Controller 模式。
///
/// 与 scraper 同款架构：
/// - 注册专用工具（write_html_file / read_html_file / export_html_plugin）
/// - Agent 循环：用户指令 → 工具调用 → 结果反馈 → 迭代修改
/// - 工具操作真实磁盘文件，非仅文本回复
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/agent/agent_factory.dart';
import 'package:evergreen_base/core/agent/agent_runtime.dart';
import 'package:evergreen_base/core/agent/agent/session.dart';
import 'package:evergreen_base/core/agent/event.dart' as agent;
import 'package:evergreen_base/core/agent/controller/controller.dart';
import 'package:evergreen_base/core/agent/provider.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/log.dart';
import 'package:evergreen_base/renderer/app/service/theme/render_tokens.dart';
import 'html_creator_tools.dart';

/// 数据源格式快照中每个字段值的最大字符截断长度。
const _kValueMaxLen = 80;

/// 数据源格式快照中每个源输出的最大总字符数。
const _kSourceMaxChars = 3000;

enum HtmlAiStatus { idle, thinking, executing, done, error }

class HtmlAiEvent {
  final String? text;
  final String? reasoning;
  final HtmlAiStatus status;
  final String? error;
  final String? toolName;
  final String? toolResult;
  const HtmlAiEvent({this.text, this.reasoning, this.status = HtmlAiStatus.idle, this.error, this.toolName, this.toolResult});
}

class HtmlAiContext {
  final String htmlContent;
  final String cssContent;
  final String jsContent;
  final String? selectedDataSource;
  final String? dataPreview;
  final String userInstruction;
  const HtmlAiContext({
    required this.htmlContent,
    this.cssContent = '',
    this.jsContent = '',
    this.selectedDataSource,
    this.dataPreview,
    required this.userInstruction,
  });

  String toPrompt() {
    final buf = StringBuffer();
    buf.writeln(userInstruction);
    if (selectedDataSource != null) {
      buf.writeln('\n## 当前绑定的数据源');
      buf.writeln('名称: $selectedDataSource');
      if (dataPreview != null) {
        buf.writeln('数据格式示例:\n```json\n$dataPreview\n```');
      }
      buf.writeln('HTML 中通过 `platform.data.get("$selectedDataSource")` 获取数据。');
    }
    if (cssContent.isNotEmpty) {
      buf.writeln('\n## 当前 CSS\n```css\n$cssContent\n```');
    }
    if (jsContent.isNotEmpty) {
      buf.writeln('\n## 当前 JavaScript\n```javascript\n$jsContent\n```');
    }
    return buf.toString();
  }
}

class HtmlAiService extends ChangeNotifier {
  final WidgetRef ref;
  final String moduleId;
  final DataOrchestrator _orch;
  final String _workspaceDir;
  final String _pluginsDir;

  AgentAssembly? _assembly;
  StreamSubscription<agent.AgentEvent>? _sub;
  String _accumulatedText = '';
  String _accumulatedReasoning = '';
  HtmlAiStatus _status = HtmlAiStatus.idle;
  HtmlAiStatus get status => _status;
  String get accumulatedText => _accumulatedText;
  String get accumulatedReasoning => _accumulatedReasoning;
  final StreamController<HtmlAiEvent> _eventController = StreamController<HtmlAiEvent>.broadcast();
  Stream<HtmlAiEvent> get events => _eventController.stream;

  /// 文件同步回调：工具写入文件后通知 UI 刷新编辑器和预览。
  void Function()? onFileChanged;

  /// 导出回调：export_html_plugin 成功后通知 UI。
  void Function(String pluginId)? onPluginExported;

  /// 当前画布已绑定的插件 ID（null = 未导出过）。由 UI 层注入。
  String? Function()? resolveCanvasPluginId;

  /// 首次导出后绑定画布 ↔ 插件 ID。由 UI 层注入。
  void Function(String pluginId)? bindCanvasPluginId;

  /// 当前画布所属侧边栏分组（如「自定义」）。由 UI 层注入。
  String Function()? resolveNavSection;

  /// view_html_result 等待评判的回调（由 UI 层注入，通过 Completer 阻塞等待人类输入）。
  Future<String> Function()? awaitReview;

  /// 当前画布 ID（用于会话持久化）。
  String? _canvasId;
  String? get canvasId => _canvasId;

  /// UI 消息列表快照（用于恢复 UI 显示，AiPanel 通过此字段读写）。
  List<Map<String, dynamic>>? uiMessages;

  /// 当前全局主题色板（8 语义色 + accent 派生色），供工具与提示词使用。
  Map<String, String> _themeColors() {
    final t = ref.read(themeStoreProvider).activeTheme;
    final c = RenderTokensColors.fromTheme(t);
    return {
      'background': c.bgPrimaryHex,
      'surface': c.bgSecondaryHex,
      'border': c.borderDefaultHex,
      'text': c.textPrimaryHex,
      'textSecondary': c.textSecondaryHex,
      'accent': c.accentBlueHex,
      'accentBg': c.accentBlueBgHex,
      'accentBorder': c.accentBlueBorderHex,
      'error': c.stateErrorHex,
      'others': c.othersHex,
    };
  }

  HtmlAiService(this.ref, this.moduleId, this._orch, {
    required String workspaceDir,
    required String pluginsDir,
  }) : _workspaceDir = workspaceDir, _pluginsDir = pluginsDir;

  // ═══════ 数据快照 ═══════

  String _buildDataSourcesSnapshot() {
    final buf = StringBuffer();
    final statuses = _orch.allStatuses;
    int sourceCount = 0, withData = 0;

    for (final s in statuses) {
      sourceCount++;
      buf.writeln('### ${s.displayName ?? s.name} (name="${s.name}")');
      buf.writeln('分类: ${s.category} | ${s.connected ? "已连通" : "未拉取"} | ${s.freshnessLabel}');

      final format = _orch.dumpDataFormat(s.name);
      if (format != null) {
        withData++;
        buf.writeln('格式:\n```\n${_truncate(format, _kSourceMaxChars)}\n```');
      } else {
        final dt = _orch.typeByName(s.name);
        if (dt != null) {
          try {
            final raw = _orch.fastReadByName(s.name);
            if (raw != null) {
              withData++;
              buf.writeln('数据（内存缓存）:\n```json\n${_truncate(_formatDataValue(raw), _kSourceMaxChars)}\n```');
            } else {
              buf.writeln('(暂无缓存，通过 `platform.data.get("${s.name}")` 获取)');
            }
          } catch (_) {
            buf.writeln('(读取失败)');
          }
        } else {
          buf.writeln('(类型未注册)');
        }
      }
      buf.writeln();
    }

    if (sourceCount == 0) {
      buf.writeln('(数据中枢暂无已注册的数据源。)');
    }

    debugPrint('[HtmlAiService] 📊 数据快照: $sourceCount 源, $withData 有缓存, ${buf.length} 字符');
    return buf.toString();
  }

  /// 当前全局主题快照（注入 Agent 提示词）。
  String _buildThemeSnapshot() {
    final c = _themeColors();
    final buf = StringBuffer('页面已自动注入以下 CSS 变量（主题切换实时更新，无需重载）：\n');
    buf.writeln('  --evg-background=${c['background']}  (页面背景)');
    buf.writeln('  --evg-surface=${c['surface']}  (卡片/面板底色)');
    buf.writeln('  --evg-border=${c['border']}  (边框/分隔线)');
    buf.writeln('  --evg-text=${c['text']}  (主文字)');
    buf.writeln('  --evg-text-secondary=${c['textSecondary']}  (次级文字)');
    buf.writeln('  --evg-accent=${c['accent']}  (强调/品牌色)');
    buf.writeln('  --evg-accent-bg=${c['accentBg']}  (强调色半透明底)');
    buf.writeln('  --evg-accent-border=${c['accentBorder']}  (强调色半透明边框)');
    buf.writeln('  --evg-error=${c['error']}  (错误态)');
    buf.writeln('  --evg-others=${c['others']}  (其余杂色)');
    return buf.toString();
  }

  String _formatDataValue(dynamic val, {int depth = 0}) {
    if (depth > 2) return '"…"';
    if (val == null) return 'null';
    if (val is String) return val.length > _kValueMaxLen ? '"${val.substring(0, _kValueMaxLen)}…"' : '"$val"';
    if (val is num || val is bool) return val.toString();
    if (val is List) {
      if (val.isEmpty) return '[]';
      final items = val.take(5).map((e) => _formatDataValue(e, depth: depth + 1)).join(', ');
      return val.length > 5 ? '[$items, …${val.length - 5} 项]' : '[$items]';
    }
    if (val is Map) {
      if (val.isEmpty) return '{}';
      final entries = val.entries.take(10).map((e) => '"${e.key}": ${_formatDataValue(e.value, depth: depth + 1)}').join(', ');
      return val.length > 10 ? '{$entries, …${val.length - 10} 键}' : '{$entries}';
    }
    return val.toString();
  }

  String _truncate(String s, int maxChars) =>
      s.length <= maxChars ? s : '${s.substring(0, maxChars)}\n…(截断, 原 ${s.length} 字符)';

  // ═══════ Agent 初始化 ═══════

  Future<void> _ensureAgent() async {
    if (_assembly != null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final apiKey = prefs.getString('DEEPSEEK_API_KEY') ?? '';
    final model = prefs.getString('DEEPSEEK_MODEL') ?? 'deepseek-chat';
    if (apiKey.isEmpty) { _setError('请先配置 DEEPSEEK_API_KEY'); return; }

    // 确保工作区存在
    final wsDir = Directory(_workspaceDir);
    if (!wsDir.existsSync()) wsDir.createSync(recursive: true);

    // 初始化工作区文件（如果不存在）
    _initWorkspaceFiles();

    try {
      final provider = DeepSeekProvider(dio: Dio(), apiKey: apiKey, model: model);
      final skillIdx = SkillIndex();
      final memStore = FileMemoryStore('${moduleId}_html_creator');

      // 创建专用工具（与 scraper 同款模式）
      final seedTools = createHtmlCreatorTools(
        workspaceDir: _workspaceDir,
        pluginsDir: _pluginsDir,
        onExported: (pluginId) => onPluginExported?.call(pluginId),
        awaitReview: () => awaitReview?.call() ?? Future.value('PASS (评判系统不可用)'),
        resolveBoundPluginId: resolveCanvasPluginId,
        onBound: bindCanvasPluginId,
        resolveNavSection: resolveNavSection,
        themeColors: _themeColors,
      );

      _assembly = AgentAssembly.fromConfig(
        moduleId: moduleId,
        config: {
          'api_key': apiKey, 'model': model,
          'max_steps': 40,        // 足够的迭代步数
          'temperature': 0.3,     // 稳定输出
          'tools': {'mode': 'all'},
          'skills': {'mode': 'none'},
        },
        sharedProvider: provider,
        globalSkillIndex: skillIdx,
        globalMemoryStore: memStore,
        seedTools: seedTools,     // ← 关键：注入专用工具
      );

      _assembly!.controller.setSystemPrompt(_systemPrompt);

      _sub = _assembly!.eventSink.stream.listen(_onAgentEvent);
      debugPrint('[HtmlAiService] ✅ Agent 初始化完毕 (workspace=$_workspaceDir, tools=${seedTools.length})');

      // 恢复该画布的历史会话
      _restoreCanvasSession();
    } catch (e, st) {
      debugPrint('[HtmlAiService] ❌ 初始化失败: $e\n$st');
      _setError('Agent 初始化失败: $e');
    }
  }

  // ═══════ 画布级别会话持久化 ═══════

  String get _sessionsPath => p.join(_workspaceDir, '${_canvasId ?? 'default'}_sessions.json');

  /// 保存当前会话到画布文件。
  void _saveCanvasSession() {
    if (_canvasId == null || _assembly == null) return;
    try {
      final sessionJson = _assembly!.session.toJson();
      final file = File(_sessionsPath);
      file.writeAsStringSync(jsonEncode({
        'canvasId': _canvasId,
        'updatedAt': DateTime.now().toIso8601String(),
        'agentSession': sessionJson,
        'uiMessages': uiMessages,
      }));
    } catch (e) {
      debugPrint('[HtmlAiService] ⚠ 保存会话失败: $e');
    }
  }

  /// 从画布文件恢复历史会话。
  void _restoreCanvasSession() {
    if (_canvasId == null || _assembly == null) return;
    try {
      final file = File(_sessionsPath);
      if (!file.existsSync()) return;

      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final sessionJson = data['agentSession'] as Map<String, dynamic>?;
      if (sessionJson == null) return;

      final restored = Session.fromJson(sessionJson);
      _assembly!.controller.setSession(restored);
      _assembly!.controller.setSystemPrompt(_systemPrompt); // 重新设置 system prompt

      uiMessages = (data['uiMessages'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList();

      debugPrint('[HtmlAiService] 📂 恢复画布会话: $_canvasId (${restored.messages.length} 条消息)');
    } catch (e) {
      debugPrint('[HtmlAiService] ⚠ 恢复会话失败: $e');
    }
  }

  /// 切换到新画布：保存旧画布会话，重置 Agent。
  Future<void> switchCanvas(String newCanvasId) async {
    _saveCanvasSession(); // 保存当前
    _canvasId = newCanvasId;
    uiMessages = null;
    _accumulatedText = '';
    _accumulatedReasoning = '';

    // 重建 Agent（新画布 = 新会话）
    _sub?.cancel(); _sub = null;
    _assembly?.dispose(); _assembly = null;

    await _ensureAgent();
    _restoreCanvasSession();
  }

  /// 初始化工作区默认文件。
  void _initWorkspaceFiles() {
    final htmlFile = File(p.join(_workspaceDir, 'index.html'));
    final cssFile = File(p.join(_workspaceDir, 'style.css'));
    final jsFile = File(p.join(_workspaceDir, 'script.js'));

    if (!htmlFile.existsSync()) {
      htmlFile.writeAsStringSync(_defaultHtml());
    }
    if (!cssFile.existsSync()) {
      cssFile.writeAsStringSync(_defaultCss());
    }
    if (!jsFile.existsSync()) {
      jsFile.writeAsStringSync(_defaultJs());
    }
    debugPrint('[HtmlAiService] 📁 工作区文件已初始化: $_workspaceDir');
  }

  // ═══════ 发送指令 ═══════

  Future<void> send(HtmlAiContext ctx) async {
    await _ensureAgent();
    if (_assembly == null) return;
    _accumulatedText = '';
    _accumulatedReasoning = '';
    _setStatus(HtmlAiStatus.thinking);

    // 同步当前编辑器内容到工作区文件（让 Agent 看到最新状态）
    _syncEditorToWorkspace(ctx);

    // 构建 Agent 输入
    final prompt = StringBuffer();
    prompt.writeln('## 数据中枢可用数据源\n');
    prompt.write(_buildDataSourcesSnapshot());
    prompt.writeln('\n---\n');
    prompt.writeln('## 当前全局主题\n');
    prompt.write(_buildThemeSnapshot());
    prompt.writeln('\n---\n');
    prompt.writeln('## 用户指令\n');
    prompt.writeln(ctx.userInstruction);
    prompt.writeln('\n---\n');
    prompt.writeln('## 工作流要求\n');
    prompt.writeln('1. 先用 `read_html_file` 读取当前文件内容\n');
    prompt.writeln('2. 用 `write_html_file` 将修改写入 index.html / style.css / script.js\n');
    prompt.writeln('3. 写入后系统会自动刷新预览面板\n');
    prompt.writeln('4. 完成后调用 `export_html_plugin` 导出为完整插件\n');

    debugPrint('[HtmlAiService] 📤 发送 Agent prompt (${prompt.length} 字符)');
    _assembly!.controller.send(prompt.toString());
  }

  /// 将编辑器内容同步到工作区文件。
  void _syncEditorToWorkspace(HtmlAiContext ctx) {
    File(p.join(_workspaceDir, 'index.html')).writeAsStringSync(ctx.htmlContent);
    if (ctx.cssContent.isNotEmpty) {
      File(p.join(_workspaceDir, 'style.css')).writeAsStringSync(ctx.cssContent);
    }
    if (ctx.jsContent.isNotEmpty) {
      File(p.join(_workspaceDir, 'script.js')).writeAsStringSync(ctx.jsContent);
    }
  }

  void cancel() { _assembly?.controller.cancel(); _setStatus(HtmlAiStatus.idle); }

  void reset() {
    cancel();
    _sub?.cancel(); _sub = null;
    _assembly?.dispose(); _assembly = null;
    _accumulatedText = ''; _accumulatedReasoning = '';
    _setStatus(HtmlAiStatus.idle);
  }

  // ═══════ 事件处理 ═══════

  void _onAgentEvent(agent.AgentEvent e) {
    switch (e.kind) {
      case agent.EventKind.reasoning:
        _accumulatedReasoning += e.reasoning ?? '';
        _emit(HtmlAiEvent(reasoning: _accumulatedReasoning, status: _status));
        break;
      case agent.EventKind.text:
        _accumulatedText += e.text ?? '';
        _emit(HtmlAiEvent(text: _accumulatedText, status: _status));
        break;
      case agent.EventKind.toolDispatch:
        _setStatus(HtmlAiStatus.executing);
        final td = e.tool;
        _emit(HtmlAiEvent(toolName: td?.name, status: _status, text: _accumulatedText));
        break;
      case agent.EventKind.toolResult:
        final tr = e.tool;
        if (tr != null && tr.isError) {
          _emit(HtmlAiEvent(error: tr.error ?? '工具错误', toolName: tr.name, status: _status, text: _accumulatedText));
        } else {
          _emit(HtmlAiEvent(toolResult: tr?.output ?? '', toolName: tr?.name, status: _status, text: _accumulatedText));
          // 工具执行成功后通知 UI 刷新
          if (tr?.name == 'write_html_file') {
            onFileChanged?.call();
          }
        }
        _setStatus(HtmlAiStatus.thinking);
        break;
      case agent.EventKind.turnDone:
        _setStatus(HtmlAiStatus.done);
        _emit(HtmlAiEvent(text: _accumulatedText, status: _status));
        onFileChanged?.call();
        _saveCanvasSession(); // 自动持久化
        break;
      default: break;
    }
  }

  void _setStatus(HtmlAiStatus s) { _status = s; _emit(HtmlAiEvent(status: s, text: _accumulatedText)); }
  void _setError(String msg) { _status = HtmlAiStatus.error; _emit(HtmlAiEvent(error: msg, status: _status)); }
  void _emit(HtmlAiEvent e) { if (!_eventController.isClosed) _eventController.add(e); }

  // ═══════ System Prompt ═══════

  String get _systemPrompt => '''
你是 Evergreen 平台的 HTML 插件创作 Agent。你拥有文件系统操作能力和视觉评判能力。

## 可用工具
- **read_html_file(file)** — 读取 index.html / style.css / script.js
- **write_html_file(file, content)** — 写入文件（自动刷新预览）
- **get_theme_colors()** — 获取当前全局主题色板（hex 值与 --evg-* CSS 变量对照）
- **view_html_result(aspect)** — 提交当前渲染结果进行视觉评判
- **export_html_plugin(plugin_id, plugin_name)** — 导出为 Evergreen 插件

## 工作流程（必须严格遵守）
1. 先用 read_html_file 读取当前文件内容
2. 根据用户需求和数据源格式，用 write_html_file 写入/修改文件
3. **立即调用 view_html_result 进行视觉评判**
   - 若返回 PASS → 进入步骤 4
   - 若返回 FAIL（附带原因）→ 根据原因修改代码，回到步骤 2
   - 最多重试 5 轮，5 轮仍未 PASS 则告知用户当前状态
4. 全部 PASS 后，调用 export_html_plugin 导出插件

## 文件约定
- index.html — HTML 结构（不含 <style>/<script>，由系统自动注入 CSS/JS）
- style.css — 样式表
- script.js — 交互逻辑（使用 platform.data.get("数据源名") 获取数据）

## 设计原则
- 排版：bold + tight tracking 建立层级，正文 neutral gray, ~65 字符/行
- **主题适配（重要）**：颜色一律优先使用 CSS 变量 `var(--evg-*)`（--evg-background / --evg-surface / --evg-border / --evg-text / --evg-text-secondary / --evg-accent / --evg-accent-bg / --evg-accent-border / --evg-error / --evg-others），**禁止硬编码色值**——这样插件会随用户切换全局主题自动换肤；需要具体 hex 时调用 get_theme_colors 工具
- 色彩：最多 1 强调色(sat<80%)，禁止 AI 紫/蓝霓虹，禁止纯黑 #000，禁止过饱和
- 布局：CSS Grid 可靠列布局，max-width ~1100-1400px，窄屏降级单列，禁止永远居中
- 卡片：只在需要层级时使用，阴影染背景色，毛玻璃加 1px 白色半透明内边框
- 禁止：3列等宽卡、假数据(99.99%)、空洞词(Elevate/Seamless)、紫色按钮发光
- 交互：骨架屏 Loading、美观空状态、内联错误提示
- 数据：用真实字段名，列表→card网格，单对象→详情面板
''';

  // ═══════ 默认模板 ═══════

  String _defaultHtml() => '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>我的插件</title>
</head>
<body>
<header class="header">
  <div class="header-inner">
    <h1>📊 数据面板</h1>
    <p>选择数据源后自动加载</p>
  </div>
</header>
<main class="container">
  <div class="stats-row" id="stats"></div>
  <div id="content"><p class="loading">加载数据中...</p></div>
</main>
<footer class="footer"><span>Powered by Evergreen</span></footer>
</body>
</html>''';

  String _defaultCss() => '''* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: linear-gradient(135deg, var(--evg-accent-bg, #eef2ff) 0%, var(--evg-surface, #ffffff) 100%);
  min-height: 100vh; color: var(--evg-text, #333);
}
.header { background: var(--evg-surface, rgba(255,255,255,0.95)); backdrop-filter: blur(10px); box-shadow: 0 2px 20px rgba(0,0,0,0.08); }
.header-inner { max-width: 1100px; margin: 0 auto; padding: 28px 32px; }
.header h1 { font-size: 26px; font-weight: 700; color: var(--evg-text, #1a1a2e); margin-bottom: 6px; }
.header p { font-size: 14px; color: var(--evg-text-secondary, #666); }
.container { max-width: 1100px; margin: 0 auto; padding: 24px 32px 60px; }
.stats-row { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 24px; }
.stat-card { background: var(--evg-surface, rgba(255,255,255,0.95)); border-radius: 12px; padding: 20px; box-shadow: 0 2px 12px rgba(0,0,0,0.06); border: 1px solid var(--evg-border, #e5e7eb); transition: transform 0.2s, box-shadow 0.2s; }
.stat-card:hover { transform: translateY(-2px); box-shadow: 0 6px 24px rgba(0,0,0,0.1); }
.stat-label { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--evg-text-secondary, #999); margin-bottom: 6px; }
.stat-value { font-size: 28px; font-weight: 700; color: var(--evg-accent, #4f46e5); }
.data-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 16px; }
.data-card { background: var(--evg-surface, rgba(255,255,255,0.95)); border-radius: 12px; padding: 20px; box-shadow: 0 2px 12px rgba(0,0,0,0.06); border-left: 4px solid var(--evg-accent, #4f46e5); transition: transform 0.2s; }
.data-card:hover { transform: translateY(-2px); box-shadow: 0 8px 30px rgba(0,0,0,0.1); }
.data-card h3 { font-size: 16px; font-weight: 600; color: var(--evg-text, #1a1a2e); margin-bottom: 10px; }
.data-field { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid var(--evg-border, #f0f0f0); font-size: 13px; }
.data-field:last-child { border-bottom: none; }
.data-field .label { color: var(--evg-text-secondary, #888); font-weight: 500; }
.data-field .value { color: var(--evg-text, #333); font-weight: 500; text-align: right; max-width: 60%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.loading { text-align: center; color: var(--evg-text-secondary, #888); font-size: 15px; padding: 40px 0; }
.empty-state { text-align: center; padding: 60px 20px; color: var(--evg-text-secondary, #888); }
.empty-state .icon { font-size: 48px; margin-bottom: 12px; }
.footer { text-align: center; padding: 20px; color: var(--evg-text-secondary, #aaa); font-size: 12px; }''';

  String _defaultJs() => '''async function init() {
  try {
    var data = await platform.data.get('REPLACE_WITH_SOURCE_NAME');
    var container = document.getElementById('content');
    if (!data) {
      container.innerHTML = '<div class="empty-state"><div class="icon">📭</div><p>暂无数据</p></div>';
      return;
    }
    if (Array.isArray(data) && data.length > 0) {
      document.getElementById('stats').innerHTML = '<div class="stat-card"><div class="stat-label">总记录</div><div class="stat-value">' + data.length + '</div></div>';
      var html = '<div class="data-grid">';
      data.forEach(function(item, i) {
        html += '<div class="data-card"><h3>#' + (i + 1) + '</h3>';
        if (typeof item === 'object') {
          Object.keys(item).slice(0, 6).forEach(function(k) {
            var v = item[k];
            html += '<div class="data-field"><span class="label">' + k + '</span><span class="value">' + (v === null ? '—' : String(v).slice(0, 60)) + '</span></div>';
          });
        }
        html += '</div>';
      });
      container.innerHTML = html + '</div>';
    } else if (data && typeof data === 'object') {
      var keys = Object.keys(data);
      document.getElementById('stats').innerHTML = '<div class="stat-card"><div class="stat-label">字段数</div><div class="stat-value">' + keys.length + '</div></div>';
      var html = '<div class="data-card"><h3>数据详情</h3>';
      keys.slice(0, 12).forEach(function(k) {
        html += '<div class="data-field"><span class="label">' + k + '</span><span class="value">' + (data[k] === null ? '—' : String(data[k]).slice(0, 80)) + '</span></div>';
      });
      container.innerHTML = html + '</div>';
    }
  } catch (e) {
    document.getElementById('content').innerHTML = '<div class="empty-state"><div class="icon">⚠️</div><p>加载失败: ' + e.message + '</p></div>';
  }
}
init();''';

  @override
  void dispose() {
    _sub?.cancel(); _assembly?.dispose(); _eventController.close(); super.dispose();
  }
}

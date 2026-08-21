/// 主题 AI 生成服务——自然语言描述 → DeepSeek 返回 8 色 JSON。
///
/// 直连 DeepSeek Provider（与 scraper_ai_panel 的字段推断同模式），
/// 不依赖 AgentAssembly。失败返回 null，由 UI 提示。
///
/// ⚠️ 会话模型（对齐 html-creator HtmlAiService / scraper）：
/// 从「workspace 单会话」改造为「面板 ↔ 实例 ↔ 会话」双向绑定：
/// - 一面板一实例，实例 ID 固定不可变（== 主题 ID）；
/// - 一会话一固定历史，按实例隔离（`panels/{panelId}/instances/{instanceId}/session.json`）；
/// - 会话文件内 `panelId + instanceId` 双向校验，孤儿会话不恢复并清理；
/// - 支持断点续做：重启/切板后自动恢复历史，并在 System Prompt 中追加续作说明；
/// - 记忆存储（FileMemoryStore）命名空间按实例隔离。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/agent/memory/file_memory_store.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';

import '../models/theme_draft.dart';

/// AI 服务状态（AI 面板头部徽标用）。
enum ThemeAiStatus { idle, thinking, done, error }

/// 主题 AI 生成服务。
class ThemeAiService extends ChangeNotifier {
  /// DeepSeek Provider 配置（apiKey 可被 [ensureApiKey] 动态补全）。
  String apiKey;
  final String baseUrl;
  final String model;

  ThemeAiService({
    required this.apiKey,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.model = 'deepseek-v4-flash',
  });

  // ═══════ 面板 ↔ 实例绑定 ═══════

  /// 当前面板 ID（面板级；会话持久化按实例隔离）。
  String? _panelId;
  String? get panelId => _panelId;

  /// 当前实例 ID（面板 ↔ 实例 1:1；会话文件按实例隔离）。
  String? _instanceId;
  String? get instanceId => _instanceId;

  /// 会话文件路径解析回调（由 UI 层注入）。
  ///
  /// 返回给定**面板 + 实例**的会话文件路径（按实例隔离）：
  /// 新版由视图层指向实例目录 `panels/{panelId}/instances/{instanceId}/session.json`
  /// —— 会话随面板生命周期，删面板即删实例与会话，不再产生孤儿文件。
  /// 缺省时回退到 `{workspace}/{panelId}_{instanceId}_session.json`（测试用）。
  String Function(String panelId, String instanceId)? resolveSessionsPath;

  /// 当前实例会话文件路径。
  String get _sessionsPath {
    final pid = _panelId;
    final iid = _instanceId;
    if (pid != null && iid != null && resolveSessionsPath != null) {
      return resolveSessionsPath!(pid, iid);
    }
    return p.join(greenixWorkspaceDir('theme-creator'),
        '${pid ?? 'default'}_${iid ?? 'default'}_session.json');
  }

  /// API Key 补全回调（由 UI 层注入；返回非空则写回 [apiKey]）。
  Future<String?> Function()? ensureApiKey;

  /// 当前草稿提供者（由 UI 层注入；保存会话时写入 draftSnapshot）。
  ThemeDraft? Function()? currentDraftProvider;

  /// 生成成功回调（由 UI 层注入；携带新草稿供视图应用）。
  void Function(ThemeDraft draft)? onDraftGenerated;

  // ═══════ 会话状态 ═══════

  /// 对话历史（不含 system；system 由服务层注入最新版）。
  List<agent.Message> _history = [];

  /// UI 消息列表快照（AI 面板展示 + 会话持久化）。
  List<Map<String, dynamic>> uiMessages = [];

  ThemeAiStatus _status = ThemeAiStatus.idle;
  ThemeAiStatus get status => _status;

  /// 是否忙碌（思考中）。
  bool get busy => _status == ThemeAiStatus.thinking;

  /// 最近一次生成的草稿（成功后供视图应用）。
  ThemeDraft? _lastDraft;
  ThemeDraft? get lastDraft => _lastDraft;

  /// 上次恢复的会话消息数（绑定态 UI 用；0 = 无历史/新会话）。
  int _sessionMessageCount = 0;
  int get sessionMessageCount => _sessionMessageCount;

  /// 当前面板会话是否从历史恢复（断点续作标记，绑定态 UI 用）。
  bool _restoredFromSession = false;
  bool get restoredFromSession => _restoredFromSession;

  /// 记忆存储命名空间（按实例隔离：一会话一份历史记忆）。
  String get memoryNamespace => 'theme_creator_${_instanceId ?? 'default'}';

  /// 长期记忆存储（命名空间按实例隔离，切换实例不串记忆）。
  ///
  /// 主题创作是「直连 DeepSeek 单轮生成」模式（无 AgentAssembly 工具循环），
  /// 记忆目前不参与生成上下文；保留该存储以对齐 html-creator 的
  /// 「记忆按实例隔离」约定，后续接入 Agent 循环时直接可用。
  FileMemoryStore get memoryStore => _memory;
  late FileMemoryStore _memory = FileMemoryStore(memoryNamespace);

  /// 取消标志（流式生成循环中检查）。
  bool _cancelRequested = false;

  void _notify() => notifyListeners();

  // ═══════ 面板 ↔ 实例切换 ═══════

  /// 切换到新面板：保存当前会话，重置 Agent 会话，恢复新实例历史。
  ///
  /// [instanceId] 由视图层在 [ThemePanelManager.ensureInstance] 后传入
  /// （面板 ↔ 实例 1:1，实例 id == 主题 id）。
  Future<void> switchPanel(String panelId, {required String instanceId}) async {
    _savePanelSession(); // 保存当前面板会话
    _panelId = panelId;
    _instanceId = instanceId;
    _history = [];
    uiMessages = [];
    _lastDraft = null;
    _status = ThemeAiStatus.idle;
    _sessionMessageCount = 0;
    _restoredFromSession = false;
    _cancelRequested = false;
    // 记忆存储按实例隔离
    _memory = FileMemoryStore(memoryNamespace);
    _restorePanelSession();
    _notify();
  }

  /// 主题 ID 与实例 ID 对齐时调用。
  ///
  /// 不重建会话、不清空当前历史，只把当前实例 id 更新为新值，
  /// 并立即把内存中的会话落盘到新实例路径（ThemePanelManager 已负责
  /// 迁移旧目录/会话文件）。这样手动或 AI 导出后修改主题 ID，
  /// 会话仍与主题保持同一 id，且不会丢失当前未保存的对话。
  void rebindInstanceId(String newInstanceId) {
    if (_panelId == null || _instanceId == null) return;
    if (newInstanceId.isEmpty || newInstanceId == _instanceId) return;
    _instanceId = newInstanceId;
    _memory = FileMemoryStore(memoryNamespace);
    _savePanelSession();
    debugPrint('[ThemeAiService] 🔀 实例 ID 对齐主题 ID: $_panelId/$_instanceId');
    _notify();
  }

  // ═══════ 会话持久化（按实例） ═══════

  /// 保存当前会话到实例文件（一会话一份历史记忆）。
  ///
  /// 每次 AI 回合结束自动保存：Agent Session + UI 消息 + 当前主题草稿快照
  /// （断点续做数据）。
  void _savePanelSession() {
    final pid = _panelId;
    final iid = _instanceId;
    if (pid == null || iid == null) return;
    try {
      final file = File(_sessionsPath);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      final draft = currentDraftProvider?.call();
      file.writeAsStringSync(jsonEncode({
        'panelId': pid,
        'instanceId': iid,
        'updatedAt': DateTime.now().toIso8601String(),
        'agentSession': _history
            .map((m) => {'role': m.role.value, 'content': m.content})
            .toList(),
        'uiMessages': uiMessages,
        if (draft != null) 'draftSnapshot': draft.toJson(),
      }));
    } catch (e) {
      debugPrint('[ThemeAiService] ⚠ 保存会话失败: $e');
    }
  }

  /// 从实例文件恢复历史会话。
  ///
  /// 双向绑定校验（对齐 scraper 孤儿过滤）：会话文件内 panelId/instanceId
  /// 必须与当前面板/实例一致，不一致 = 孤儿会话 → 不恢复 + 清理文件，
  /// 保证绝不串台。
  void _restorePanelSession() {
    final pid = _panelId;
    final iid = _instanceId;
    if (pid == null || iid == null) return;
    try {
      final file = File(_sessionsPath);
      if (!file.existsSync()) return;

      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      // 双向绑定校验：panelId/instanceId 必须匹配当前面板/实例
      final fPanel = data['panelId'] as String?;
      final fInstance = data['instanceId'] as String?;
      if (fPanel != pid || fInstance != iid) {
        debugPrint('[ThemeAiService] ⚠ 孤儿会话（panelId=$fPanel instanceId=$fInstance '
            '≠ $pid/$iid），不恢复并清理');
        try {
          file.deleteSync();
        } catch (_) {}
        return;
      }

      final rounds = (data['agentSession'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      _history = rounds
          .map((m) => agent.Message(
                role: m['role'] == 'assistant'
                    ? agent.Role.assistant
                    : agent.Role.user,
                content: (m['content'] as String? ?? '').trim(),
              ))
          .where((m) => m.content.isNotEmpty)
          .toList();

      uiMessages = (data['uiMessages'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];

      // 老数据可能只有 agentSession：由历史推导 UI 消息（不丢展示）。
      if (uiMessages.isEmpty && _history.isNotEmpty) {
        uiMessages = _history
            .where((m) => m.role != agent.Role.system)
            .map((m) => {
                  'role': m.role == agent.Role.user ? 'user' : 'ai',
                  'text': m.content,
                })
            .toList();
      }

      _sessionMessageCount = _history.length;
      _restoredFromSession = _history.isNotEmpty;

      debugPrint(
          '[ThemeAiService] 📂 恢复实例会话: $pid/$iid (${_history.length} 条消息)');
    } catch (e) {
      debugPrint('[ThemeAiService] ⚠ 恢复会话失败: $e');
    }
  }

  /// 手动追加一轮对话（迁移/测试/未来人工备注用），并落盘。
  void addRound({required String user, required String assistant}) {
    _history.add(agent.Message(role: agent.Role.user, content: user));
    _history.add(agent.Message(role: agent.Role.assistant, content: assistant));
    uiMessages.add({'role': 'user', 'text': user});
    uiMessages.add({'role': 'ai', 'text': assistant});
    _sessionMessageCount = _history.length;
    _savePanelSession();
    _notify();
  }

  /// 清空当前会话（历史 + UI 消息），并落盘空会话。
  void reset() {
    _cancelRequested = true;
    _history = [];
    uiMessages = [];
    _lastDraft = null;
    _status = ThemeAiStatus.idle;
    _sessionMessageCount = 0;
    _restoredFromSession = false;
    _savePanelSession();
    _notify();
  }

  /// 取消当前生成（流式循环中检查标志；不丢已有历史）。
  void cancel() {
    _cancelRequested = true;
    if (_status == ThemeAiStatus.thinking) {
      _status = ThemeAiStatus.idle;
      _notify();
    }
  }

  // ═══════ AI 生成 ═══════

  /// 根据 [description] 生成 8 色主题草稿；失败返回 null。
  ///
  /// 断点续作：自动携带本实例持久化历史（重启/切板后返工不丢上下文）；
  /// 历史非空时 System Prompt 追加续作说明，AI 直接继续执行而非从头重做。
  Future<ThemeDraft?> generate(String description) async {
    if (busy) return null;
    if (apiKey.isEmpty) {
      if (ensureApiKey != null) {
        final k = await ensureApiKey!();
        if (k == null || k.isEmpty) {
          _appendError('请先配置 DEEPSEEK_API_KEY 后重试');
          return null;
        }
        apiKey = k;
      } else {
        _appendError('请先配置 DEEPSEEK_API_KEY');
        return null;
      }
    }
    final desc = description.trim();
    if (desc.isEmpty) return null;

    _cancelRequested = false;
    _status = ThemeAiStatus.thinking;
    _history.add(agent.Message(role: agent.Role.user, content: desc));
    uiMessages.add({'role': 'user', 'text': desc});
    _notify();

    final buf = StringBuffer();
    try {
      final provider = agent.DeepSeekProvider(
        dio: Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        )),
        apiKey: apiKey,
        model: model,
      );

      // 断点续作：历史非空时追加续作说明，避免 AI 从头解释/重做已完成修改。
      final systemPrompt = _history.length > 1
          ? '$_systemPrompt\n\n## 断点续作\n'
              '上次会话已恢复（${_history.length - 1} 条消息）。'
              '若上一次任务未完成，请直接继续执行，'
              '不要从头解释或重做已完成的工作。'
          : _systemPrompt;

      final messages = [
        agent.Message(role: agent.Role.system, content: systemPrompt),
        // 历史（不含刚追加的当前指令；当前指令用模板包装）
        ..._history.take(_history.length - 1),
        agent.Message(role: agent.Role.user, content: _buildUserPrompt(desc)),
      ];

      await for (final event in provider.chat(messages: messages)) {
        if (_cancelRequested) {
          _status = ThemeAiStatus.idle;
          _notify();
          return null;
        }
        if (event.kind == agent.ProviderEventKind.content &&
            event.text != null) {
          buf.write(event.text);
        }
      }

      final draft = _parseDraft(buf.toString());
      if (draft == null) {
        _appendError('AI 生成失败，请重试或检查 API Key');
        return null;
      }

      _lastDraft = draft;
      // 记录本轮对话（用户指令 + 结果摘要），供下次迭代返工
      final summary = '已生成主题「${draft.name}」：' + jsonEncode(draft.toJson());
      _history.add(agent.Message(role: agent.Role.assistant, content: summary));
      uiMessages.add({'role': 'ai', 'text': summary});
      _status = ThemeAiStatus.done;
      _savePanelSession(); // 自动持久化（含草稿快照）
      _notify();
      onDraftGenerated?.call(draft);
      return draft;
    } catch (e) {
      debugPrint('[ThemeAiService] 生成失败: $e');
      _appendError('AI 生成失败: $e');
      return null;
    }
  }

  void _appendError(String msg) {
    uiMessages.add({'role': 'error', 'text': msg});
    _status = ThemeAiStatus.error;
    _savePanelSession();
    _notify();
  }

  /// 从 AI 回复文本解析并校验草稿；失败返回 null。
  ThemeDraft? _parseDraft(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 提取 JSON（可能被 markdown 代码块包裹）
    var jsonText = trimmed;
    final m = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(trimmed);
    if (m != null) jsonText = m.group(1)!.trim();

    final json = jsonDecode(jsonText) as Map<String, dynamic>;
    final colors = (json['colors'] as Map?)?.cast<String, dynamic>();
    if (colors == null) return null;

    final draft = ThemeDraft(
      id: (json['id'] as String? ?? 'ai_theme').replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
      name: json['name'] as String? ?? 'AI 主题',
      colors: colors.map((k, v) => MapEntry(k, v.toString())),
    );

    // 校验：缺键/非法 hex 时丢弃返回 null
    if (!draft.hasAllColors || !draft.allColorsValid) return null;
    if (!isValidHexColor(draft.colors['background'])) return null;
    return draft;
  }

  /// 构建用户指令（JSON 结构模板）。
  String _buildUserPrompt(String description) => '''
用户的主题描述：$description

请返回如下结构的 JSON（8 个键全必填，值为 #RRGGBB 格式 hex）：
{
  "id": "英文 snake_case 主题 id",
  "name": "中文主题名",
  "colors": {
    "background": "#...",
    "surface": "#...",
    "border": "#...",
    "text": "#...",
    "textSecondary": "#...",
    "accent": "#...",
    "error": "#...",
    "others": "#..."
  }
}

配色要求：
- background 是页面主背景；surface 是卡片/面板底色（与 background 协调）
- text 与 background 对比度 ≥ 4.5:1；textSecondary 略弱于 text
- accent 是品牌强调色，与背景对比鲜明
- error 是错误态红色系
- 整体风格贴合用户描述，色调统一和谐
''';

  /// 基础 Agent 提示词（职责 + 输出约束）。
  String get _systemPrompt => '你是资深 UI 配色设计师。根据用户的主题描述，'
      '设计一套协调的配色方案。你必须只返回合法的 JSON 对象，'
      '不要包含任何解释、markdown 标记或代码块。';
}

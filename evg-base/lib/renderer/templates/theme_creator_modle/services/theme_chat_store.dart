/// ⚠️ 已废弃（降级为旧数据迁移工具）。
///
/// 主题创作中心已从「workspace 单会话」改造为「面板 ↔ 实例 ↔ 会话」双向绑定
/// 模型（一面板一实例、一会话一固定历史、按实例隔离、断点续做）。
/// 本类不再作为唯一历史来源——只由 [ThemePanelManager.migrateLegacyIfNeeded]
/// 读取老版 `chats/chat.json` 并把历史迁入实例 `session.json`。
/// 不要再在业务代码中新建实例读写历史。
library;

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 主题创作 AI 聊天历史存储（workspace 单会话，旧模型，仅迁移用）。
class ThemeChatStore {
  final String rootDir;

  ThemeChatStore({String? rootDir})
      : rootDir = rootDir ?? greenixWorkspaceDir('theme-creator/chats');

  File get _file => File('$rootDir/chat.json');

  /// 加载历史（缺失/损坏 → 空列表，绝不抛）。
  List<Map<String, dynamic>> load() {
    try {
      if (!_file.existsSync()) return [];
      final json = jsonDecode(_file.readAsStringSync()) as List<dynamic>;
      return json.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// 追加一轮对话（用户指令 + AI 结果摘要）。最多保留最近 24 条（12 轮），
  /// 防止上下文无限膨胀。
  void appendRound({
    required String userPrompt,
    required String assistantSummary,
  }) {
    try {
      final rounds = load();
      rounds.add({
        'role': 'user',
        'content': userPrompt,
        'at': DateTime.now().toIso8601String(),
      });
      rounds.add({
        'role': 'assistant',
        'content': assistantSummary,
        'at': DateTime.now().toIso8601String(),
      });
      final kept = rounds.length > 24 ? rounds.sublist(rounds.length - 24) : rounds;
      Directory(rootDir).createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(kept));
    } catch (_) {
      // 历史持久化失败静默——不阻断生成
    }
  }

  /// 转成 agent.Message 列表（不含 system——system 由服务层注入最新版）。
  List<agent.Message> toAgentMessages() => load()
      .map((m) => agent.Message(
            role: (m['role'] == 'assistant')
                ? agent.Role.assistant
                : agent.Role.user,
            content: (m['content'] as String? ?? '').trim(),
          ))
      .where((m) => m.content.isNotEmpty)
      .toList();
}

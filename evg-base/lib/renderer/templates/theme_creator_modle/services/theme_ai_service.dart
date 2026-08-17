/// 主题 AI 生成服务——自然语言描述 → DeepSeek 返回 8 色 JSON。
///
/// 直连 DeepSeek Provider（与 scraper_ai_panel 的字段推断同模式），
/// 不依赖 AgentAssembly。失败返回 null，由 UI 提示。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'package:evergreen_base/core/theme/theme_descriptor.dart';

import '../models/theme_draft.dart';

/// 主题 AI 生成服务。
class ThemeAiService {
  /// DeepSeek Provider 配置。
  final String apiKey;
  final String baseUrl;
  final String model;

  ThemeAiService({
    required this.apiKey,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.model = 'deepseek-v4-flash',
  });

  /// 根据 [description] 生成 8 色主题草稿；失败返回 null。
  ///
  /// [history] 为历史对话（不含 system，由 [ThemeChatStore] 持久化提供）：
  /// 迭代/返工时 AI 能看到之前的指令与结果，不会从零重走流程。
  Future<ThemeDraft?> generate(String description,
      {List<agent.Message> history = const []}) async {
    if (apiKey.isEmpty) return null;
    final provider = agent.DeepSeekProvider(
      dio: Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
      )),
      apiKey: apiKey,
    );

    const systemPrompt = '你是资深 UI 配色设计师。根据用户的主题描述，'
        '设计一套协调的配色方案。你必须只返回合法的 JSON 对象，'
        '不要包含任何解释、markdown 标记或代码块。';

    final userPrompt = '''
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

    try {
      final messages = [
        agent.Message(role: agent.Role.system, content: systemPrompt),
        ...history,
        agent.Message(role: agent.Role.user, content: userPrompt),
      ];
      final buf = StringBuffer();
      await for (final event in provider.chat(messages: messages)) {
        if (event.kind == agent.ProviderEventKind.content &&
            event.text != null) {
          buf.write(event.text);
        }
      }
      final text = buf.toString().trim();
      if (text.isEmpty) return null;

      // 提取 JSON（可能被 markdown 代码块包裹）
      var jsonText = text;
      final m = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)```').firstMatch(text);
      if (m != null) jsonText = m.group(1)!.trim();

      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      final colors = (json['colors'] as Map?)?.cast<String, dynamic>();
      if (colors == null) return null;

      final draft = ThemeDraft(
        id: (json['id'] as String? ?? 'ai_theme')
            .replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
        name: json['name'] as String? ?? 'AI 主题',
        colors: colors.map((k, v) => MapEntry(k, v.toString())),
      );

      // 校验：缺键/非法 hex 时丢弃返回 null
      if (!draft.hasAllColors || !draft.allColorsValid) return null;
      if (!isValidHexColor(draft.colors['background'])) return null;
      return draft;
    } catch (e) {
      debugPrint('[ThemeAiService] 生成失败: $e');
      return null;
    }
  }
}

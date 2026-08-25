/// HtmlCreatorHooks — HTML 创作 Agent 的工具钩子（T3-P3D 守卫）。
///
/// L2 preToolUse 白名单守卫（仿 scraper 的 ScraperHooks 模式）：
/// - `write_html_file` → file 白名单（index.html/style.css/script.js）+ 体积上限
/// - `export_html_plugin` → plugin_id 格式校验（防路径穿越）
/// - `save_credential` → key 命名规范校验
/// - `platform_api_call` → service/path 合法性（服务白名单 + 路径以 / 开头）
///
/// 硬安全（不因用户放行而绕过）：凭证 key 非法、插件 ID 含路径分隔符。
library html_creator_hooks;

import 'package:evergreen_base/core/agent/agent.dart' as agent;
import 'html_creator_tools.dart' show validateCredentialKey;
import 'html_export_service.dart' show htmlPluginIdError;

/// HTML 创作 Agent 工具钩子。
class HtmlCreatorHooks implements agent.ToolHooks {
  /// 单文件体积上限（与 WriteHtmlFileTool 一致）。
  static const int maxFileBytes = 200 * 1024;

  /// 允许写入的工作区文件白名单。
  static const Set<String> allowedFiles = {'index.html', 'style.css', 'script.js'};

  /// 允许转发的 core 服务白名单。
  static const Set<String> allowedServices = {
    'agent', 'config', 'data', 'module', 'theme', 'core',
  };

  const HtmlCreatorHooks();

  @override
  String get match => '';

  @override
  Future<(bool block, String message)> preToolUse(
      String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'write_html_file':
        final file = args['file'] as String? ?? '';
        if (!allowedFiles.contains(file)) {
          return (true, '[error: 目标文件 $file 不在白名单'
              '（仅允许 index.html / style.css / script.js）]');
        }
        final content = args['content'] as String? ?? '';
        if (content.length > maxFileBytes) {
          return (true, '[error: 文件过大（${content.length} 字符，'
              '上限 $maxFileBytes）——请精简或拆分]');
        }
        return (false, '');

      case 'export_html_plugin':
        // 共享 htmlPluginIdError（与手动导出/AI 工具同一规则）：
        // 小写字母开头 + 小写字母/数字/连字符，防纯数字/路径穿越。
        final pluginId = args['plugin_id'] as String? ?? '';
        final idErr = htmlPluginIdError(pluginId);
        if (idErr != null) {
          return (true, '[error: $idErr]');
        }
        return (false, '');

      case 'save_credential':
        final key = args['key'] as String? ?? '';
        final err = validateCredentialKey(key);
        if (err != null) {
          return (true, '[error: 凭证 key 校验失败: $err]');
        }
        return (false, '');

      case 'platform_api_call':
        final service = args['service'] as String? ?? '';
        if (!allowedServices.contains(service)) {
          return (true, '[error: 服务 $service 不在白名单'
              '（仅允许 agent/config/data/module/theme/core）]');
        }
        final path = args['path'] as String? ?? '';
        if (!path.startsWith('/')) {
          return (true, '[error: path 必须以 / 开头: "$path"]');
        }
        if (path.contains('..')) {
          return (true, '[error: path 禁止包含 "..": "$path"]');
        }
        return (false, '');

      default:
        return (false, '');
    }
  }

  @override
  Future<void> postToolUse(
      String name, Map<String, dynamic> args, String result) async {
    // 预留：结果摘要/审计（当前无 TraceBuffer 接入）。
  }

  @override
  Future<void> postToolUseFailure(
      String name, Map<String, dynamic> args, String errorResult) async {
    // 预留。
  }
}

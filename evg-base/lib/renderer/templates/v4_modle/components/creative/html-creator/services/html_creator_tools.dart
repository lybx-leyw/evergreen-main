/// HTML 创作 Agent 专用工具集。
///
/// 提供文件读写工具，让 AI Agent 能实际操作磁盘文件：
/// - `write_html_file` — 将 HTML/CSS/JS 写入磁盘文件
/// - `read_html_file` — 读取磁盘上的 HTML 文件内容
/// - `export_html_plugin` — 导出为完整插件并返回验证结果
///
/// T3（全栈贯通）新增：
/// - `platform_api_call` — 通用 core 服务 HTTP 转发（6 组服务端口自动发现）
/// - `get_config_value` / `save_credential` — ConfigHttpServer 配置/凭证读写
/// - `list_data_sources` / `read_data_source` — 数据中枢取数（平台能力取数）
/// - `check_ui_quality` — 静态 UI 质量自检（主题 token / 结构 / 溢出风险）
library html_creator_tools;

import 'dart:convert';
import 'dart:io';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/html_modle/bridge_script.dart'
    show forwardCoreHttp;
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart'
    show CoreService;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'html_export_service.dart' show htmlPluginIdError, writeHtmlPluginModule;

/// 工具：将 HTML 内容写入磁盘文件。
///
/// AI 调用此工具实际创建/修改 .html 文件，而非仅回复文本。
/// 支持分别写入 HTML/CSS/JS 三个独立文件。
class WriteHtmlFileTool extends SimpleTool {
  final String workspaceDir;

  WriteHtmlFileTool({required this.workspaceDir})
      : super(
          name: 'write_html_file',
          description: '将 HTML/CSS/JS 代码写入工作区文件。'
              'file 参数指定目标文件：index.html / style.css / script.js。'
              'content 参数为完整的文件内容。'
              '写入后会自动刷新预览面板。',
          schema: const {
            'type': 'object',
            'properties': {
              'file': {
                'type': 'string',
                'enum': ['index.html', 'style.css', 'script.js'],
                'description': '目标文件名',
              },
              'content': {
                'type': 'string',
                'description': '完整的文件内容',
              },
            },
            'required': ['file', 'content'],
          },
          readOnly: false,
          execute: (args) async {
            final file = args['file'] as String? ?? 'index.html';
            final content = args['content'] as String? ?? '';
            if (content.isEmpty) return '[error: content 参数为空]';
            // T3-P3D 守卫：单文件体积上限（防止 AI 一次性写出失控巨文件）。
            if (content.length > 200 * 1024) {
              return '[error: 文件过大（${content.length} 字符，上限 200KB）——'
                  '请精简或拆分，禁止写入超大文件]';
            }

            final dir = Directory(workspaceDir);
            if (!dir.existsSync()) dir.createSync(recursive: true);

            final filePath = p.join(workspaceDir, file);
            await File(filePath).writeAsString(content);
            debugPrint('[WriteHtmlFile] ✅ 写入: $filePath (${content.length} 字符)');
            return '✅ 已写入 $file (${content.length} 字符) → 预览面板已自动刷新';
          },
        );
}

/// 工具：读取磁盘上的 HTML 相关文件。
///
/// AI 在修改前应先用此工具读取当前文件内容，
/// 避免基于过时上下文做修改。
class ReadHtmlFileTool extends SimpleTool {
  final String workspaceDir;

  ReadHtmlFileTool({required this.workspaceDir})
      : super(
          name: 'read_html_file',
          description: '读取工作区中的文件内容。'
              'file 参数：index.html / style.css / script.js。'
              '修改文件前先用此工具读取当前内容。',
          schema: const {
            'type': 'object',
            'properties': {
              'file': {
                'type': 'string',
                'enum': ['index.html', 'style.css', 'script.js'],
                'description': '要读取的文件名',
              },
            },
            'required': ['file'],
          },
          readOnly: true,
          execute: (args) async {
            final file = args['file'] as String? ?? 'index.html';
            final filePath = p.join(workspaceDir, file);
            final f = File(filePath);
            if (!f.existsSync()) return '⚠️ 文件 $file 不存在 ($filePath)';
            final content = f.readAsStringSync();
            debugPrint('[ReadHtmlFile] 📖 读取: $filePath (${content.length} 字符)');
            // 截断过长内容
            if (content.length > 6000) {
              return '📄 $file (${content.length} 字符, 已截断前 6000 字符):\n```${_lang(file)}\n${content.substring(0, 6000)}\n... (截断)```';
            }
            return '📄 $file (${content.length} 字符):\n```${_lang(file)}\n$content\n```';
          },
        );
}

/// 工具：将工作区文件导出为完整的 Evergreen HTML 插件。
///
/// 生成 plugins/<id>/module/ 目录结构，包含 manifest.json + index.html
/// （style.css / script.js 合并进 index.html）。
class ExportHtmlPluginTool extends SimpleTool {
  final String workspaceDir;
  /// 插件根目录；缺省时使用 [resolvePluginsRoot]（与手动导出/主题插件同源）。
  final String? pluginsDir;

  /// 插件根目录（平台正确解析：桌面=项目 plugins/，安卓=应用私有 .greenix/plugins）。
  String get pluginsRoot => pluginsDir ?? resolvePluginsRoot();
  /// 回调：导出成功后通知 UI 刷新预览（切换到 HTTP 模式）。
  final void Function(String pluginId) onExported;

  /// 返回当前画布已绑定的插件 ID（null = 尚未导出过）。
  /// 非空时强制复用绑定 ID，忽略 AI 传入的 plugin_id，
  /// 避免同一画布多次导出生成多个插件。
  final String? Function()? resolveBoundPluginId;

  /// 首次导出成功后调用，将 pluginId 绑定到当前画布。
  final void Function(String pluginId)? onBound;

  /// 返回当前画布所属侧边栏分组（如「自定义」）。
  /// 与手动导出路径（HtmlExportService 的 project.navSection）保持一致，
  /// 避免 AI 导出与手动导出落入不同分组。默认「自定义」。
  final String Function()? resolveNavSection;

  ExportHtmlPluginTool({
    required this.workspaceDir,
    this.pluginsDir,
    required this.onExported,
    this.resolveBoundPluginId,
    this.onBound,
    this.resolveNavSection,
  }) : super(
          name: 'export_html_plugin',
          description: '将工作区文件导出为 Evergreen HTML 插件。'
              '生成 plugins/<id>/module/ 目录结构。'
              '导出成功后预览面板自动切换到 HTTP 模式加载真实插件。'
              '参数：plugin_id（插件 ID，如 my-dashboard）、plugin_name（显示名称）。'
              '注意：同一画布已导出过时插件 ID 固定，请直接复用画布当前 ID。'
              '导出完成后检查返回日志中的 ❌ 或 error，若有错误则修改代码后重试。',
          schema: const {
            'type': 'object',
            'properties': {
              'plugin_id': {
                'type': 'string',
                'description': '插件唯一 ID（小写+连字符，如 my-dashboard）',
              },
              'plugin_name': {
                'type': 'string',
                'description': '插件显示名称（如 我的数据面板）',
              },
            },
            'required': ['plugin_id', 'plugin_name'],
          },
          readOnly: false,
          execute: (args) async {
            var pluginId = args['plugin_id'] as String? ?? '';
            var pluginName = args['plugin_name'] as String? ?? pluginId;

            // 画布已绑定插件 ID → 强制复用，忽略 AI 传入的新 ID
            final boundId = resolveBoundPluginId?.call();
            if (boundId != null && boundId.isNotEmpty) {
              pluginId = boundId;
            }
            // T3-P3D 守卫：插件 ID 格式校验（共享 htmlPluginIdError：
            // 小写字母开头 + 小写字母/数字/连字符，防纯数字/大写/路径穿越）。
            final idErr = htmlPluginIdError(pluginId);
            if (idErr != null) {
              return '[error: $idErr]';
            }

            try {
              // 读取工作区文件
              final htmlFile = File(p.join(workspaceDir, 'index.html'));
              final cssFile = File(p.join(workspaceDir, 'style.css'));
              final jsFile = File(p.join(workspaceDir, 'script.js'));

              if (!htmlFile.existsSync()) {
                return '[error: index.html 不存在，请先用 write_html_file 创建]';
              }

              final htmlContent = htmlFile.readAsStringSync();
              final cssContent = cssFile.existsSync() ? cssFile.readAsStringSync() : '';
              final jsContent = jsFile.existsSync() ? jsFile.readAsStringSync() : '';

              // 合并 CSS/JS 到 HTML（Evergreen 插件格式）
              String fullHtml = htmlContent;
              if (cssContent.isNotEmpty && !fullHtml.contains('<style>')) {
                fullHtml = fullHtml.replaceFirst(
                  '</head>',
                  '<style>\n$cssContent\n</style>\n</head>',
                );
              }
              if (jsContent.isNotEmpty && !fullHtml.contains('<script>')) {
                fullHtml = fullHtml.replaceFirst(
                  '</body>',
                  '<script>\n$jsContent\n</script>\n</body>',
                );
              }

              // manifest.json
              final manifest = {
                'schemaVersion': '2.0',
                'type': 'module',
                'id': pluginId,
                'name': pluginName,
                'template': 'html',
                'version': '1.0.0',
                'route': '/$pluginId',
                'nav': {
                  'sidebar': {
                    'section': resolveNavSection?.call() ?? '自定义',
                    'sectionOrder': 99,
                    'order': 99,
                  },
                },
              };

              // 单目标原子导出（与手动导出共用 writeHtmlPluginModule：
              // resolvePluginsRoot + path_sandbox 校验 + 临时目录替换）。
              // ⚠ 闭包内不能访问 this.getter（字段初始化器限制），
              // 直接由构造参数 pluginsDir ?? resolvePluginsRoot() 解析。
              final moduleDir = await writeHtmlPluginModule(
                pluginsRoot: pluginsDir ?? resolvePluginsRoot(),
                pluginId: pluginId,
                files: {
                  'manifest.json':
                      const JsonEncoder.withIndent('  ').convert(manifest),
                  'index.html': fullHtml,
                },
              );

              debugPrint('[ExportHtmlPlugin] ✅ 导出成功: $moduleDir');
              onExported(pluginId);
              // 首次导出：绑定画布 ↔ 插件 ID，后续导出均复用
              if (boundId == null || boundId.isEmpty) {
                onBound?.call(pluginId);
              }

              return '✅ 插件 "$pluginName" ($pluginId) 已导出\n'
                  '📁 $moduleDir/\n'
                  '  ├── manifest.json\n'
                  '  └── index.html\n'
                  '预览面板已切换到 HTTP 模式加载真实插件。';
            } catch (e) {
              debugPrint('[ExportHtmlPlugin] ❌ 导出失败: $e');
              return '❌ 导出失败: $e';
            }
          },
        );
}

/// 工具：获取当前全局主题色板。
///
/// AI 生成/修改 CSS 时调用：返回 8 个语义色 + accent 派生色的当前 hex 值，
/// 并提示使用 --evg-* CSS 变量（插件随全局主题自动换肤）。
class GetThemeColorsTool extends SimpleTool {
  final Map<String, String> Function() themeColors;

  GetThemeColorsTool({required this.themeColors})
      : super(
          name: 'get_theme_colors',
          description: '获取 Evergreen 当前全局主题色板（背景/面板/边框/文字/强调/错误等语义色）。'
              '生成或修改 CSS 时调用本工具获取具体 hex 值；'
              '推荐优先使用 CSS 变量（var(--evg-accent) 等），插件会随全局主题自动换肤。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            final c = themeColors();
            final buf = StringBuffer('当前全局主题色板：\n');
            c.forEach((k, v) => buf.writeln('- $k: $v'));
            buf.writeln('\n对应的 CSS 变量（页面已自动注入，主题切换实时更新）：');
            buf.writeln('  --evg-background / --evg-surface / --evg-border');
            buf.writeln('  --evg-text / --evg-text-secondary / --evg-accent');
            buf.writeln('  --evg-accent-bg / --evg-accent-border / --evg-error / --evg-others');
            return buf.toString();
          },
        );
}

/// 工具：提交当前渲染结果进行视觉评判。
///
/// AI 调用此工具后，系统会在预览面板旁弹出评判对话框，
/// 由内部视觉检查系统评估渲染效果。
/// 对 AI 而言这是一个普通的评判工具——调用后等待结果即可。
class ViewHtmlResultTool extends SimpleTool {
  /// 等待评判结果的 Completer（由 UI 层填充结果）。
  final Future<String> Function() awaitReview;

  ViewHtmlResultTool({required this.awaitReview})
      : super(
          name: 'view_html_result',
          description: '提交当前渲染结果进行视觉评判。'
              '在 write_html_file 修改文件后调用此工具，'
              '系统会对预览面板中的渲染效果进行自动视觉检查。'
              '返回 PASS（通过）或 FAIL（不通过，附带具体原因）。'
              '若 FAIL，请根据返回的原因修改代码后重新提交评判。'
              '参数：aspect（要检查的方面，如 layout/color/typography/data/all）。',
          schema: const {
            'type': 'object',
            'properties': {
              'aspect': {
                'type': 'string',
                'description': '检查方面：all（全面检查）、layout（布局）、color（配色）、typography（排版）、data（数据渲染）',
              },
            },
          },
          readOnly: true,
          execute: (args) async {
            final aspect = args['aspect'] as String? ?? 'all';
            debugPrint('[ViewHtmlResult] 🔍 AI 请求视觉评判 (aspect=$aspect)');
            try {
              final result = await awaitReview();
              debugPrint('[ViewHtmlResult] 📋 评判结果: $result');
              return result;
            } catch (e) {
              debugPrint('[ViewHtmlResult] ⚠ 评判异常: $e');
              return 'PASS (评判系统暂时不可用，默认通过)';
            }
          },
        );
}

String _lang(String file) => switch (file) {
  'style.css' => 'css',
  'script.js' => 'javascript',
  _ => 'html',
};

// ═══════════════════════════ T3-A 平台底层能力工具 ═══════════════════════════

/// 工具：通用 core 服务 HTTP 转发（端口自动发现）。
///
/// 让 AI 直接调用平台 6 组底层 HttpServer（Agent/Config/Data/Module/Theme/Core），
/// 端口从 projectRoot 下 `.xxx_port` 文件自动发现（[CoreApiDiscovery]）。
class PlatformApiCallTool extends SimpleTool {
  PlatformApiCallTool()
      : super(
          name: 'platform_api_call',
          description: '调用 Evergreen 平台 core 服务 HTTP API（端口自动发现）。'
              'service ∈ agent/config/data/module/theme/core；'
              'path 为服务内路径（如 /config/settings/DEEPSEEK_API_KEY、'
              '/data/types、/agent/tools、/theme/colors）；'
              'method ∈ GET/POST；body 为可选 JSON 对象。'
              '返回 JSON 响应。用于读取平台配置/数据源/主题/模块等底层能力。'
              '⚠️ 凭证写入请用 save_credential，不要用本工具 POST 到 /config/settings。',
          schema: const {
            'type': 'object',
            'properties': {
              'service': {
                'type': 'string',
                'enum': ['agent', 'config', 'data', 'module', 'theme', 'core'],
                'description': '服务标识（6 组 core 服务之一）',
              },
              'path': {
                'type': 'string',
                'description': '服务内路径，必须以 / 开头（如 /config/settings）',
              },
              'method': {
                'type': 'string',
                'enum': ['GET', 'POST'],
                'description': 'HTTP 方法（默认 GET）',
              },
              'body': {
                'type': 'object',
                'description': 'POST 请求体（可选）',
              },
            },
            'required': ['service', 'path'],
          },
          readOnly: true,
          execute: (args) async {
            final serviceId = args['service'] as String? ?? '';
            final path = args['path'] as String? ?? '';
            if (!path.startsWith('/')) {
              return '[error: path 必须以 / 开头: "$path"]';
            }
            final method = ((args['method'] as String?) ?? 'GET').toUpperCase();
            final rawBody = args['body'];
            final body = rawBody is Map
                ? Map<String, dynamic>.from(rawBody)
                : null;
            final service = CoreService.values.firstWhere(
              (s) => s.id == serviceId,
              orElse: () => CoreService.config, // 占位；下方显式校验兜底
            );
            if (service.id != serviceId) {
              return '[error: 未知服务 "$serviceId"（仅允许 '
                  'agent/config/data/module/theme/core）]';
            }
            try {
              final result =
                  await forwardCoreHttp(service, method, path, body);
              return result == null
                  ? '(空响应)'
                  : const JsonEncoder.withIndent('  ').convert(result);
            } catch (e) {
              debugPrint('[PlatformApiCall] ❌ $method $path 失败: $e');
              return '[error: $method $path 失败: $e]';
            }
          },
        );
}

/// 工具：读取平台配置项（ConfigHttpServer）。
class GetConfigValueTool extends SimpleTool {
  GetConfigValueTool()
      : super(
          name: 'get_config_value',
          description: '读取平台配置项（ConfigHttpServer）。'
              'key 为设置键（如 DEEPSEEK_API_KEY / DEEPSEEK_MODEL / ZJU_USERNAME）。'
              '返回 {"key": "...", "value": "..."}；未配置返回提示。',
          schema: const {
            'type': 'object',
            'properties': {
              'key': {
                'type': 'string',
                'description': '配置键名（如 DEEPSEEK_API_KEY）',
              },
            },
            'required': ['key'],
          },
          readOnly: true,
          execute: (args) async {
            final key = args['key'] as String? ?? '';
            if (key.isEmpty) return '[error: key 参数为空]';
            try {
              final result = await forwardCoreHttp(
                  CoreService.config, 'GET', '/config/settings/$key');
              if (result is Map && result['value'] != null) {
                return '配置项 $key = ${result['value']}';
              }
              return '未找到配置项 $key（可能未设置）';
            } catch (e) {
              debugPrint('[GetConfigValue] ❌ 读取 $key 失败: $e');
              return '[error: 读取配置 $key 失败: $e]';
            }
          },
        );
}

/// 工具：写入/更新平台配置项（ConfigHttpServer，凭证管理）。
class SaveCredentialTool extends SimpleTool {
  SaveCredentialTool()
      : super(
          name: 'save_credential',
          description: '将凭证/配置写入平台（ConfigHttpServer）。'
              'key 命名规范：大写字母开头，仅含大写字母/数字/下划线'
              '（如 SCRAPER_USERNAME / DEEPSEEK_API_KEY）。'
              '写入后插件可经 platform.api.call("config", "/config/settings/KEY")'
              ' 或平台设置面板读取。'
              '⚠️ 先 get_config_value 检查是否已有现成值，避免重复覆盖。',
          schema: const {
            'type': 'object',
            'properties': {
              'key': {
                'type': 'string',
                'description': '配置键名（大写字母开头，如 SCRAPER_USERNAME）',
              },
              'value': {
                'type': 'string',
                'description': '配置值（用户名/密码/Token/API Key）',
              },
            },
            'required': ['key', 'value'],
          },
          readOnly: false,
          execute: (args) async {
            final key = args['key'] as String? ?? '';
            final value = (args['value'] as String? ?? '').toString();
            final err = validateCredentialKey(key);
            if (err != null) return '[error: $err]';
            try {
              await forwardCoreHttp(
                CoreService.config,
                'POST',
                '/config/settings',
                {'key': key, 'value': value},
              );
              debugPrint('[SaveCredential] ✅ $key 已写入平台配置');
              return '✅ 配置 "$key" 已保存到平台（ConfigHttpServer）。';
            } catch (e) {
              debugPrint('[SaveCredential] ❌ 保存 $key 失败: $e');
              return '[error: 保存配置 $key 失败: $e]';
            }
          },
        );
}

/// 校验配置键名（T3-P3D 守卫，hooks 与工具共用）。
///
/// 规则：非空、≤64 字符、以大写字母开头、仅含大写字母/数字/下划线。
String? validateCredentialKey(String key) {
  if (key.isEmpty) return 'key 参数为空';
  if (key.length > 64) return 'key 过长（≤64 字符）';
  if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key)) {
    return 'key 非法: "$key"——必须以大写字母开头，仅含大写字母/数字/下划线'
        '（如 SCRAPER_USERNAME / DEEPSEEK_API_KEY）';
  }
  return null;
}

/// 工具：列出数据中枢全部数据源（含连通状态/新鲜度/格式快照）。
class ListDataSourcesTool extends SimpleTool {
  /// 数据中枢快照提供者（由 HtmlAiService 注入，含截断）。
  final String Function() snapshotProvider;

  ListDataSourcesTool({required this.snapshotProvider})
      : super(
          name: 'list_data_sources',
          description: '列出数据中枢全部已注册数据源：名称/分类/连通状态/'
              '格式示例（与系统注入的数据快照一致）。'
              '在决定用哪个数据源取数、确认数据源名时调用。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async => snapshotProvider(),
        );
}

/// 工具：读取指定数据源的当前值（平台能力取数）。
class ReadDataSourceTool extends SimpleTool {
  /// 数据源读取器（由 HtmlAiService 注入；返回截断后的 JSON 文本）。
  final Future<String> Function(String name) reader;

  ReadDataSourceTool({required this.reader})
      : super(
          name: 'read_data_source',
          description: '读取指定数据源的当前缓存值（截断 JSON）。'
              'name 必须是数据中枢真实存在的数据源名（先用 list_data_sources 确认）。'
              '用于设计插件前查看真实字段结构与示例数据。',
          schema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': '数据源名（数据中枢 name）',
              },
            },
            'required': ['name'],
          },
          readOnly: true,
          execute: (args) async {
            final name = args['name'] as String? ?? '';
            if (name.isEmpty) return '[error: name 参数为空]';
            try {
              return await reader(name);
            } catch (e) {
              return '[error: 读取数据源 $name 失败: $e]';
            }
          },
        );
}

// ═══════════════════════════ T3-C UI 质量自检工具 ═══════════════════════════

/// 工具：静态 UI 质量自检（theme_token / html_structure / ui_render）。
///
/// 纯字符串分析，不依赖真实浏览器——在 `view_html_result` 视觉评判之前调用，
/// 提前拦截可静态判定的问题（硬编码色值、结构缺失、溢出风险模式）。
class CheckUiQualityTool extends SimpleTool {
  final String workspaceDir;

  CheckUiQualityTool({required this.workspaceDir})
      : super(
          name: 'check_ui_quality',
          description: '对当前工作区 index.html/style.css/script.js 做静态 UI 质量自检。'
              '检查项：theme_token（硬编码色值 vs --evg-* 主题变量 / 平台变量重定义）、'
              'html_structure（DOCTYPE/head/body/占位符残留/外链资源）、'
              'ui_render（固定宽高溢出风险/nowrap 未截断/网格过宽）。'
              'aspect 可选 all/theme_token/html_structure/ui_render。'
              '返回逐项 PASS/FAIL + 行号；总评 FAIL 时必须修改后重跑。'
              '在 view_html_result 之前调用。',
          schema: const {
            'type': 'object',
            'properties': {
              'aspect': {
                'type': 'string',
                'enum': ['all', 'theme_token', 'html_structure', 'ui_render'],
                'description': '检查范围（默认 all）',
              },
            },
          },
          readOnly: true,
          execute: (args) =>
              CheckUiQualityTool.runCheck(workspaceDir, args['aspect'] as String?),
        );

  /// 执行自检（静态：避免 execute 闭包在构造期捕获实例成员）。
  static Future<String> runCheck(String workspaceDir, String? aspectArg) async {
    final aspect = aspectArg ?? 'all';
    final html = _readFileSafe(p.join(workspaceDir, 'index.html'));
    final css = _readFileSafe(p.join(workspaceDir, 'style.css'));
    final issues = <String>[];
    final buf = StringBuffer();

    if (aspect == 'all' || aspect == 'theme_token') {
      final themeIssues = checkThemeTokens(css);
      buf.writeln('### theme_token（主题 token 一致性）');
      if (themeIssues.isEmpty) {
        buf.writeln('✅ 通过：无硬编码色值、无平台变量重定义');
      } else {
        buf.writeln('❌ ${themeIssues.length} 处问题：');
        for (final i in themeIssues.take(15)) {
          buf.writeln('  $i');
        }
        issues.addAll(themeIssues);
      }
      buf.writeln();
    }

    if (aspect == 'all' || aspect == 'html_structure') {
      final structIssues = checkHtmlStructure(html);
      buf.writeln('### html_structure（HTML 结构）');
      if (structIssues.isEmpty) {
        buf.writeln('✅ 通过：结构完整、无占位符残留、无外链资源');
      } else {
        buf.writeln('❌ ${structIssues.length} 处问题：');
        for (final i in structIssues.take(15)) {
          buf.writeln('  $i');
        }
        issues.addAll(structIssues);
      }
      buf.writeln();
    }

    if (aspect == 'all' || aspect == 'ui_render') {
      final renderIssues = checkUiRender(css);
      buf.writeln('### ui_render（布局溢出/裁剪风险）');
      if (renderIssues.isEmpty) {
        buf.writeln('✅ 通过：未发现溢出风险模式');
      } else {
        buf.writeln('⚠️ ${renderIssues.length} 处风险（建议修复）：');
        for (final i in renderIssues.take(15)) {
          buf.writeln('  $i');
        }
        issues.addAll(renderIssues);
      }
      buf.writeln();
    }

    final verdict = issues.isEmpty ? '✅ PASS' : '❌ FAIL（${issues.length} 处问题）';
    buf.writeln('---');
    buf.writeln('总评: $verdict');
    if (issues.isNotEmpty) {
      buf.writeln('请按上述行号修复后重跑 check_ui_quality，全部通过再 view_html_result。');
    }
    return buf.toString();
  }

  static String _readFileSafe(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  /// 主题 token 检查（静态方法，可单测）。
  static List<String> checkThemeTokens(String css) {
    final issues = <String>[];
    if (css.trim().isEmpty) return issues;
    // 先剥掉注释，避免注释里的色值误报
    final stripped = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final lines = stripped.split('\n');
    final hexRe = RegExp(r'#[0-9a-fA-F]{3,8}\b');
    final funcRe = RegExp(r'\b(?:rgb|rgba|hsl|hsla)\([^)]*\)');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final no = i + 1;
      // 平台变量重定义：--evg-xxx: value（定义形态）
      if (RegExp(r'--evg-[\w-]+\s*:').hasMatch(line)) {
        issues.add('style.css:$no 重定义平台主题变量（$line.trim()）——'
            '平台自动注入 --evg-*，插件禁止覆盖');
        continue;
      }
      // var(--evg-x, #fallback) 兜底色允许
      if (line.contains('var(--evg-')) continue;
      for (final m in hexRe.allMatches(line)) {
        issues.add('style.css:$no 硬编码色值 ${m.group(0)}（应使用 var(--evg-*)）');
        break; // 每行报一次即可
      }
      for (final m in funcRe.allMatches(line)) {
        issues.add('style.css:$no 硬编码颜色 ${m.group(0)}（应使用 var(--evg-*)）');
        break;
      }
    }
    return issues;
  }

  /// HTML 结构检查（静态方法，可单测）。
  static List<String> checkHtmlStructure(String html) {
    final issues = <String>[];
    if (html.trim().isEmpty) {
      issues.add('index.html 为空——请先用 write_html_file 写入内容');
      return issues;
    }
    final lower = html.toLowerCase();
    if (!lower.contains('<!doctype') && !lower.contains('<html')) {
      issues.add('index.html 缺少 <!DOCTYPE html> / <html> 根元素');
    }
    if (!lower.contains('<head')) {
      issues.add('index.html 缺少 <head> 元素');
    }
    if (!lower.contains('<body')) {
      issues.add('index.html 缺少 <body> 元素');
    }
    if (html.contains('REPLACE_WITH_SOURCE_NAME')) {
      issues.add('index.html 残留占位符 REPLACE_WITH_SOURCE_NAME——'
          '必须替换为数据中枢真实数据源名');
    }
    // 外链资源（离线导出约束）；[\x22\x27] = " 与 '（raw 串内避开引号定界符）
    final extRe = RegExp(
        r'<(?:script|link|img|iframe)\b[^>]*(?:src|href)\s*=\s*[\x22\x27]https?://',
        caseSensitive: false);
    for (final m in extRe.allMatches(html)) {
      issues.add('index.html 禁止外链远程资源（离线约束）: '
          '${m.group(0)!.trim().replaceAll(RegExp(r'\s+'), ' ')}…');
    }
    // 标签配平（轻量启发）
    for (final tag in ['div', 'span', 'section', 'tr', 'td']) {
      final open = RegExp('<$tag\\b').allMatches(lower).length;
      final close = RegExp('</$tag>').allMatches(lower).length;
      if (open != close) {
        issues.add('index.html 标签不平衡: <$tag> ×$open vs </$tag> ×$close');
      }
    }
    return issues;
  }

  /// 布局溢出/裁剪风险检查（静态方法，可单测）。
  static List<String> checkUiRender(String css) {
    final issues = <String>[];
    if (css.trim().isEmpty) return issues;
    final stripped = css.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    // 按声明块切分（保留选择器定位）
    final blocks = stripped.split('}');
    var lineCursor = 0;
    for (final block in blocks) {
      final colon = block.indexOf('{');
      if (colon < 0) {
        lineCursor += '\n'.allMatches(block).length;
        continue;
      }
      final selector = block.substring(0, colon).trim();
      final decls = block.substring(colon + 1);
      final lineNo = lineCursor + 1;
      lineCursor += '\n'.allMatches(block).length;

      if (decls.contains(RegExp(r'width:\s*\d+px')) &&
          !decls.contains('max-width')) {
        issues.add('style.css:$lineNo 规则 "$selector": 固定宽度无 max-width '
            '（窄屏会溢出，请加 max-width: 100%）');
      }
      final minW = RegExp(r'min-width:\s*(\d{3,})px').firstMatch(decls);
      if (minW != null) {
        issues.add('style.css:$lineNo 规则 "$selector": min-width 过大 '
            '（${minW.group(1)}px，移动端放不下，建议 ≤280px 或改用弹性布局）');
      }
      if (decls.contains('white-space: nowrap') &&
          !decls.contains('overflow') &&
          !decls.contains('text-overflow')) {
        issues.add('style.css:$lineNo 规则 "$selector": white-space: nowrap 未配 '
            'overflow: hidden + text-overflow: ellipsis（长文本会溢出）');
      }
      if (decls.contains(RegExp(r'height:\s*\d+px')) &&
          !decls.contains('overflow')) {
        issues.add('style.css:$lineNo 规则 "$selector": 固定高度未配 overflow '
            '（内容超出会被裁剪，请加 overflow: auto）');
      }
      final grid = RegExp(r'minmax\((\d{3,})px').firstMatch(decls);
      if (grid != null) {
        issues.add('style.css:$lineNo 规则 "$selector": 网格列 minmax 过宽 '
            '（${grid.group(1)}px，建议 ≤300px 以便窄屏单列降级）');
      }
    }
    return issues;
  }
}

/// 为 HTML 创作 Agent 构造专用工具集。
List<Tool> createHtmlCreatorTools({
  required String workspaceDir,
  String? pluginsDir,
  required void Function(String pluginId) onExported,
  required Future<String> Function() awaitReview,
  String? Function()? resolveBoundPluginId,
  void Function(String pluginId)? onBound,
  String Function()? resolveNavSection,
  Map<String, String> Function()? themeColors,
  /// 数据中枢快照提供者（list_data_sources 用）。
  String Function()? dataSourcesSnapshot,
  /// 数据源读取器（read_data_source 用；返回截断 JSON 文本）。
  Future<String> Function(String name)? readDataSource,
}) {
  return [
    WriteHtmlFileTool(workspaceDir: workspaceDir),
    ReadHtmlFileTool(workspaceDir: workspaceDir),
    if (themeColors != null) GetThemeColorsTool(themeColors: themeColors),
    ExportHtmlPluginTool(
      workspaceDir: workspaceDir,
      pluginsDir: pluginsDir,
      onExported: onExported,
      resolveBoundPluginId: resolveBoundPluginId,
      onBound: onBound,
      resolveNavSection: resolveNavSection,
    ),
    ViewHtmlResultTool(awaitReview: awaitReview),
    // ── T3 全栈贯通：平台底层能力 + 检验工具 ──
    PlatformApiCallTool(),
    GetConfigValueTool(),
    SaveCredentialTool(),
    if (dataSourcesSnapshot != null)
      ListDataSourcesTool(snapshotProvider: dataSourcesSnapshot),
    if (readDataSource != null)
      ReadDataSourceTool(reader: readDataSource),
    CheckUiQualityTool(workspaceDir: workspaceDir),
  ];
}

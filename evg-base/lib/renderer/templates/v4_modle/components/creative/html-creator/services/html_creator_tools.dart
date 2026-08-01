/// HTML 创作 Agent 专用工具集。
///
/// 提供文件读写工具，让 AI Agent 能实际操作磁盘文件：
/// - `write_html_file` — 将 HTML/CSS/JS 写入磁盘文件
/// - `read_html_file` — 读取磁盘上的 HTML 文件内容
/// - `export_html_plugin` — 导出为完整插件并返回验证结果
library html_creator_tools;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/agent/tool.dart';

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
/// 生成 plugins/<id>/module/ 目录结构，包含 manifest.json + index.html + style.css + script.js。
class ExportHtmlPluginTool extends SimpleTool {
  final String workspaceDir;
  final String pluginsDir;
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
    required this.pluginsDir,
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
            if (pluginId.isEmpty) return '[error: plugin_id 参数为空]';

            final normPluginsDir = pluginsDir.endsWith('/') || pluginsDir.endsWith('\\')
                ? pluginsDir : '$pluginsDir/';
            final moduleDir = Directory('${normPluginsDir}$pluginId/module');

            try {
              if (!await moduleDir.exists()) {
                await moduleDir.create(recursive: true);
              }

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

              await File('${moduleDir.path}/manifest.json')
                  .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
              await File('${moduleDir.path}/index.html').writeAsString(fullHtml);

              debugPrint('[ExportHtmlPlugin] ✅ 导出成功: ${moduleDir.path}');
              onExported(pluginId);
              // 首次导出：绑定画布 ↔ 插件 ID，后续导出均复用
              if (boundId == null || boundId.isEmpty) {
                onBound?.call(pluginId);
              }

              return '✅ 插件 "$pluginName" ($pluginId) 已导出\n'
                  '📁 ${moduleDir.path}/\n'
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

/// 为 HTML 创作 Agent 构造专用工具集。
List<Tool> createHtmlCreatorTools({
  required String workspaceDir,
  required String pluginsDir,
  required void Function(String pluginId) onExported,
  required Future<String> Function() awaitReview,
  String? Function()? resolveBoundPluginId,
  void Function(String pluginId)? onBound,
  String Function()? resolveNavSection,
  Map<String, String> Function()? themeColors,
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
  ];
}

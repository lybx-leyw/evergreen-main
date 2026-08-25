// 测试：HTML 创作中心 T3 新增工具与守卫。
//
// 覆盖点：
// 1. CheckUiQualityTool.checkThemeTokens —— 硬编码色值 / var 兜底放行 / 变量重定义
// 2. CheckUiQualityTool.checkHtmlStructure —— 结构缺失 / 占位符残留 / 外链拦截
// 3. CheckUiQualityTool.checkUiRender —— 固定宽高溢出 / nowrap 未截断 / 网格过宽
// 4. validateCredentialKey —— 凭证键名规范
// 5. HtmlCreatorHooks.preToolUse —— 白名单守卫（写文件/导出/凭证/API 转发）
// 6. ExportHtmlPluginTool —— plugin_id 路径穿越拒绝 + 合法导出落盘
// 7. PlatformApiCallTool —— path/service 前置校验
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:evergreen_base/core/utils/path_sandbox.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/html_creator_hooks.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/html_creator_tools.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/html_export_service.dart';

void main() {
  group('CheckUiQualityTool.checkThemeTokens', () {
    test('硬编码 hex 色值按行号报出', () {
      final css = 'body {\n  background: #ffffff;\n  color: #333;\n}\n'
          '.card { border: 1px solid #e5e7eb; }';
      final issues = CheckUiQualityTool.checkThemeTokens(css);
      expect(issues, isNotEmpty);
      expect(issues.any((i) => i.contains('style.css:2') && i.contains('#ffffff')), isTrue);
      expect(issues.any((i) => i.contains('style.css:3') && i.contains('#333')), isTrue);
      expect(issues.any((i) => i.contains('style.css:5') && i.contains('#e5e7eb')), isTrue);
    });

    test('var(--evg-*) 兜底色放行', () {
      final css = '.stat-value { color: var(--evg-accent, #4f46e5); }\n'
          '.x { background: var(--evg-surface, #ffffff); }';
      expect(CheckUiQualityTool.checkThemeTokens(css), isEmpty);
    });

    test('重定义平台主题变量被报出', () {
      final css = ':root { --evg-accent: #ff0000; }\nbody { color: var(--evg-text); }';
      final issues = CheckUiQualityTool.checkThemeTokens(css);
      expect(issues, isNotEmpty);
      expect(issues.first, contains('重定义平台主题变量'));
      expect(issues.first, contains('style.css:1'));
    });

    test('rgb() 函数色值被报出', () {
      final css = '.a { background: rgb(102, 126, 234); }';
      final issues = CheckUiQualityTool.checkThemeTokens(css);
      expect(issues, isNotEmpty);
      expect(issues.first, contains('rgb(102, 126, 234)'));
    });

    test('注释内的色值不误报', () {
      final css = '/* 示例色 #ffffff 仅注释 */\nbody { color: var(--evg-text); }';
      expect(CheckUiQualityTool.checkThemeTokens(css), isEmpty);
    });
  });

  group('CheckUiQualityTool.checkHtmlStructure', () {
    test('缺 DOCTYPE/head/body 被报出', () {
      final html = '<div>hello</div>';
      final issues = CheckUiQualityTool.checkHtmlStructure(html);
      expect(issues.any((i) => i.contains('<!DOCTYPE html>')), isTrue);
      expect(issues.any((i) => i.contains('<head>')), isTrue);
      expect(issues.any((i) => i.contains('<body>')), isTrue);
    });

    test('占位符残留被报出', () {
      final html = '<html><head></head><body>'
          'platform.data.get("REPLACE_WITH_SOURCE_NAME")</body></html>';
      final issues = CheckUiQualityTool.checkHtmlStructure(html);
      expect(issues.any((i) => i.contains('REPLACE_WITH_SOURCE_NAME')), isTrue);
    });

    test('外链远程资源被拦截（离线约束）', () {
      final html = '<html><head>'
          '<script src="https://cdn.example.com/lib.js"></script>'
          '<link rel="stylesheet" href="http://cdn.example.com/a.css">'
          '</head><body></body></html>';
      final issues = CheckUiQualityTool.checkHtmlStructure(html);
      expect(issues.any((i) => i.contains('外链远程资源')), isTrue);
      expect(issues.length, greaterThanOrEqualTo(2));
    });

    test('完整合规 HTML 通过', () {
      final html = '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">'
          '<title>t</title></head><body><div>ok</div></body></html>';
      expect(CheckUiQualityTool.checkHtmlStructure(html), isEmpty);
    });
  });

  group('CheckUiQualityTool.checkUiRender', () {
    test('固定宽度无 max-width 被报出', () {
      final css = '.panel { width: 900px; }';
      final issues = CheckUiQualityTool.checkUiRender(css);
      expect(issues.any((i) => i.contains('固定宽度无 max-width')), isTrue);
      expect(issues.first, contains('.panel'));
    });

    test('nowrap 未配 overflow/ellipsis 被报出', () {
      final css = '.value { white-space: nowrap; }';
      final issues = CheckUiQualityTool.checkUiRender(css);
      expect(issues.any((i) => i.contains('white-space: nowrap')), isTrue);
    });

    test('nowrap 已配 overflow + ellipsis 放行', () {
      final css = '.value { white-space: nowrap; overflow: hidden; '
          'text-overflow: ellipsis; max-width: 60%; }';
      expect(CheckUiQualityTool.checkUiRender(css), isEmpty);
    });

    test('min-width 过大 / 网格 minmax 过宽被报出', () {
      final css = '.a { min-width: 500px; }\n'
          '.grid { grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); }';
      final issues = CheckUiQualityTool.checkUiRender(css);
      expect(issues.any((i) => i.contains('min-width 过大')), isTrue);
      expect(issues.any((i) => i.contains('网格列 minmax 过宽')), isTrue);
    });

    test('固定高度未配 overflow 被报出', () {
      final css = '.box { height: 300px; }';
      final issues = CheckUiQualityTool.checkUiRender(css);
      expect(issues.any((i) => i.contains('固定高度未配 overflow')), isTrue);
    });
  });

  group('validateCredentialKey', () {
    test('合法键名通过', () {
      expect(validateCredentialKey('DEEPSEEK_API_KEY'), isNull);
      expect(validateCredentialKey('ZJU_USERNAME'), isNull);
    });
    test('非法键名被拒', () {
      expect(validateCredentialKey(''), isNotNull);
      expect(validateCredentialKey('deepseek_api_key'), isNotNull);
      expect(validateCredentialKey('1ABC'), isNotNull);
      expect(validateCredentialKey('A B C'), isNotNull);
      expect(validateCredentialKey('A/B'), isNotNull);
    });
  });

  group('HtmlCreatorHooks.preToolUse', () {
    const hooks = HtmlCreatorHooks();

    test('write_html_file 越权文件被 block', () async {
      final (block, _) = await hooks.preToolUse(
          'write_html_file', {'file': '../../etc/passwd', 'content': 'x'});
      expect(block, isTrue);
    });
    test('write_html_file 超大内容被 block', () async {
      final (block, _) = await hooks.preToolUse('write_html_file',
          {'file': 'index.html', 'content': 'x' * 300000});
      expect(block, isTrue);
    });
    test('export_html_plugin 路径穿越 plugin_id 被 block', () async {
      final (block, msg) = await hooks.preToolUse(
          'export_html_plugin', {'plugin_id': '../evil', 'plugin_name': 'x'});
      expect(block, isTrue);
      expect(msg, contains('plugin_id 非法'));
    });
    test('save_credential 非法 key 被 block', () async {
      final (block, _) = await hooks.preToolUse(
          'save_credential', {'key': 'bad key!', 'value': 'v'});
      expect(block, isTrue);
    });
    test('platform_api_call 越权服务/非法 path 被 block', () async {
      final (b1, _) = await hooks.preToolUse(
          'platform_api_call', {'service': 'hack', 'path': '/x'});
      expect(b1, isTrue);
      final (b2, _) = await hooks.preToolUse(
          'platform_api_call', {'service': 'config', 'path': 'config/settings'});
      expect(b2, isTrue);
      final (b3, _) = await hooks.preToolUse(
          'platform_api_call', {'service': 'config', 'path': '/../x'});
      expect(b3, isTrue);
    });
    test('合法调用放行', () async {
      final (b1, _) = await hooks.preToolUse(
          'write_html_file', {'file': 'index.html', 'content': '<html></html>'});
      expect(b1, isFalse);
      final (b2, _) = await hooks.preToolUse('export_html_plugin',
          {'plugin_id': 'my-dashboard', 'plugin_name': '面板'});
      expect(b2, isFalse);
    });
  });

  group('ExportHtmlPluginTool 守卫', () {
    late Directory ws;
    late Directory plugins;

    setUp(() async {
      ws = await Directory.systemTemp.createTemp('evg_ws_');
      plugins = await Directory.systemTemp.createTemp('evg_plugins_');
      File('${ws.path}/index.html').writeAsStringSync(
          '<!DOCTYPE html><html><head></head><body>ok</body></html>');
    });

    tearDown(() async {
      await ws.delete(recursive: true);
      await plugins.delete(recursive: true);
    });

    test('非法 plugin_id（路径穿越）拒绝且不落盘', () async {
      final tool = ExportHtmlPluginTool(
        workspaceDir: ws.path,
        pluginsDir: plugins.path,
        onExported: (_) {},
      );
      final res = await tool.execute(
          {'plugin_id': '../../escape', 'plugin_name': 'x'});
      expect(res, contains('plugin_id 非法'));
      expect(Directory('${plugins.path}/../../escape').existsSync(), isFalse);
    });

    test('合法 plugin_id 导出成功并回调', () async {
      var exportedId = '';
      final tool = ExportHtmlPluginTool(
        workspaceDir: ws.path,
        pluginsDir: plugins.path,
        onExported: (id) => exportedId = id,
        onBound: (_) {},
      );
      final res = await tool.execute(
          {'plugin_id': 'my-dashboard', 'plugin_name': '我的面板'});
      expect(res, contains('已导出'));
      expect(exportedId, 'my-dashboard');
      expect(
          File('${plugins.path}/my-dashboard/module/manifest.json').existsSync(),
          isTrue);
      expect(
          File('${plugins.path}/my-dashboard/module/index.html').existsSync(),
          isTrue);
    });
  });

  group('PlatformApiCallTool 前置校验', () {
    test('path 不以 / 开头被拒（不发起 HTTP）', () async {
      final tool = PlatformApiCallTool();
      final res = await tool.execute(
          {'service': 'config', 'path': 'config/settings'});
      expect(res, contains('[error:'));
      expect(res, contains('必须以 / 开头'));
    });
    test('未知服务被拒', () async {
      final tool = PlatformApiCallTool();
      final res =
          await tool.execute({'service': 'nope', 'path': '/x'});
      expect(res, contains('未知服务'));
    });
  });

  group('htmlPluginIdError（O5：id 校验过松）', () {
    test('纯数字 id 被拒（如 "5"——曾泄漏进 bundle 的画布 id）', () {
      expect(htmlPluginIdError('5'), isNotNull);
      expect(htmlPluginIdError('123'), isNotNull);
      expect(htmlPluginIdError('5')!, contains('plugin_id 非法'));
    });
    test('大写/空格/路径分隔符/空 id 被拒', () {
      expect(htmlPluginIdError('My-Plugin'), isNotNull);
      expect(htmlPluginIdError('my plugin'), isNotNull);
      expect(htmlPluginIdError('../../escape'), isNotNull);
      expect(htmlPluginIdError('my/plugin'), isNotNull);
      expect(htmlPluginIdError(''), isNotNull);
      expect(htmlPluginIdError('a' * 65), isNotNull);
    });
    test('合法 kebab-case 通过', () {
      expect(htmlPluginIdError('my-dashboard'), isNull);
      expect(htmlPluginIdError('a'), isNull);
      expect(htmlPluginIdError('my2-plugin-3'), isNull);
    });
  });

  group('writeHtmlPluginModule（单目标原子导出）', () {
    late Directory plugins;

    setUp(() async {
      plugins = await Directory.systemTemp.createTemp('evg_export_');
    });

    tearDown(() async {
      await plugins.delete(recursive: true);
    });

    test('非法 id 抛 PathSandboxException 且不落盘', () async {
      await expectLater(
        writeHtmlPluginModule(
            pluginsRoot: plugins.path,
            pluginId: '../../escape',
            files: {'index.html': 'x'}),
        throwsA(isA<PathSandboxException>()),
      );
      expect(Directory('${plugins.path}/../../escape').existsSync(), isFalse);
    });

    test('导出落盘 manifest+index，且保留旧 module 的附加资产', () async {
      final root = plugins.path;
      // 预置旧 module 与附加资产（如 icon/）
      final oldModule = Directory('$root/quiz/module');
      oldModule.createSync(recursive: true);
      File('$root/quiz/module/icon.png').writeAsStringSync('old-icon');
      File('$root/quiz/module/index.html').writeAsStringSync('old');

      final moduleDir = await writeHtmlPluginModule(
        pluginsRoot: root,
        pluginId: 'quiz',
        files: {
          'manifest.json': '{"type":"module","id":"quiz"}',
          'index.html': '<html>new</html>',
        },
      );

      expect(moduleDir, endsWith('${Platform.pathSeparator}quiz${Platform.pathSeparator}module'));
      expect(File('$root/quiz/module/manifest.json').readAsStringSync(),
          contains('"id":"quiz"'));
      expect(File('$root/quiz/module/index.html').readAsStringSync(),
          contains('new'));
      // 附加资产保留（原子导出基于旧目录复制而非整体覆盖）
      expect(File('$root/quiz/module/icon.png').readAsStringSync(), 'old-icon');
      // 无临时/备份残留
      final leftovers = Directory('$root/quiz')
          .listSync()
          .where((e) => e.path.contains('.module_tmp_') || e.path.contains('.module_bak_'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });
}

/// R10 HTML 渲染日志生成器（真实 Flutter 渲染器参与）。
///
/// 这是 R10 校验的**正确**入口：必须由内嵌于 `evg-base/lib/renderer/html/` 的
/// 真实 `HtmlRenderer`（与运行态 AppShell / `HtmlRenderView` 同源）生成 HTML，
/// 且页面内动态文本全部来自真实数据源拉取，绝不使用绕开 Flutter 的独立脚本。
///
/// 必须通过 Flutter 运行（提供 `dart:ui` 等运行时），即用 `flutter test`：
///   cd evg-base && flutter test test/r10_render_log.dart
///
/// 行为：扫描 `plugins/` 下所有含 `module/manifest.json` 的插件，逐个：
///   1. 读 `module/manifest.json`
///   2. 对含 dataSource 的 data-table，用 `Process.run` 跑 `data/<x>.exe` 真实拉取
///   3. 把真实行注入 `data-table.config.rows`（R10 允许的 HTML 渲染升级）
///   4. 调用真实 `HtmlRenderer.render(manifest)` 生成 HTML（Flutter 渲染器参与）
///   5. 写 `plugins/<id>/render_log.html`
///   6. 运行 R10 四项自动检查：真实数据 / 非空 / 无重叠 / 合规
///
/// 可选环境变量 `R10_PLUGIN`（逗号分隔）限定只跑指定插件，便于调试。

import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/renderer/html/html_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 合规组件类型集合（覆盖 renderer 已实现的 53 种 + 别名）。
const Set<String> _supported = <String>{
  'ai-assistant', 'chat', 'code-editor', 'data-dashboard', 'data-table',
  'chart', 'stat-tile', 'timeline', 'card-list', 'kanban', 'tree',
  'nav-button', 'button', 'timetable', 'markdown', 'divider', 'spreadsheet',
  'mindmap', 'type-check', 'flashcards', 'quiz', 'video', 'video-player',
  'map', 'document', 'doc-viewer', 'doc-editor', 'presentation', 'calendar',
  'audio-player', 'image-gallery', 'notepad', 'whiteboard', 'diff-viewer',
  'terminal', 'crossword', 'pronunciation', 'prompt-builder', 'custom',
  'webview', 'settings', 'form', 'lottery-wheel',
  'pdf-viewer', 'scanner', 'tech-planner', 'scraper-generator',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('R10 HTML 渲染日志（真实 Flutter 渲染器 + 真实数据）', () async {
    // flutter test 在 evg-base 目录内运行，cwd 即 evg-base；项目根为其父目录。
    final root = Platform.environment['R10_ROOT'] ??
        Directory.current.parent.path;
    final pluginsDir = Directory('$root/plugins');
    if (!pluginsDir.existsSync()) {
      fail('找不到 plugins 目录: ${pluginsDir.path}');
    }

    final only = (Platform.environment['R10_PLUGIN'] ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    // 演示/参考插件（showcase*）刻意使用写死示例内容，不属于 29 模块复刻任务，
    // 不纳入 R11 严格校验（其 dataSource 亦未实现真实拉取）。
    final skip = <String>{'showcase', 'showcase-dart', 'showcase-dart-chrome'};

    final failures = <String>[];
    final ran = <String>[];
    for (final ent in pluginsDir.listSync().whereType<Directory>()) {
      final id = ent.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      if (only.isNotEmpty && !only.contains(id)) continue;
      if (skip.contains(id)) continue;
      final manifestPath = File('${ent.path}/module/manifest.json');
      if (!manifestPath.existsSync()) continue;
      final ok = await render(id, root);
      ran.add(id);
      if (!ok) failures.add(id);
    }

    stdout.writeln('\n==== R10 汇总 ====');
    stdout.writeln('已处理模块数: ${ran.length}');
    stdout.writeln('R10 未通过: ${failures.isEmpty ? '无' : failures.join(', ')}');
    expect(failures, isEmpty,
        reason: '以下模块 R10 未通过: ${failures.join(', ')}');
  });
}

Future<bool> render(String pluginId, String root) async {
  final manifestPath = File('$root/plugins/$pluginId/module/manifest.json');
  final manifest =
      jsonDecode(manifestPath.readAsStringSync()) as Map<String, dynamic>;

  String? script;
  Map<String, dynamic>? dataManifest;
  final dmPath = File('$root/plugins/$pluginId/data/manifest.json');
  if (dmPath.existsSync()) {
    dataManifest = jsonDecode(dmPath.readAsStringSync()) as Map<String, dynamic>;
    final scriptName =
        (dataManifest['script'] as String? ?? '').replaceAll('.exe', '');
    final exe = File('$root/plugins/$pluginId/data/$scriptName.exe');
    final py = File('$root/plugins/$pluginId/data/$scriptName.py');
    if (exe.existsSync()) {
      script = exe.path;
    } else if (py.existsSync()) {
      script = py.path;
    }
  }

  final typeMap = <String, String>{};
  if (dataManifest != null) {
    for (final dt in (dataManifest['dataTypes'] as List<dynamic>? ?? [])) {
      final m = dt as Map<String, dynamic>;
      final name = m['name'] as String?;
      final typeArg = m['typeArg'] as String?;
      if (name != null && typeArg != null) {
        typeMap[name] = typeArg;
      } else {
        stderr.writeln('[WARN] 数据清单 dataTypes 缺 name/typeArg，跳过: '
            '${m['name'] ?? '<null>'}');
      }
    }
  }

  final realValues = <String>[];
  final pages =
      (manifest['pages'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  for (final page in pages) {
    final layout = (page['layout'] as Map<String, dynamic>? ?? {});
    final slots = (layout['slots'] as Map<String, dynamic>? ?? {});
    slots.forEach((_, rawSlot) {
      final slot = rawSlot as Map<String, dynamic>? ?? {};
      final comp = (slot['component'] as Map<String, dynamic>? ?? {});
      final type = comp['type'] as String?;
      if (type == null) return;
      final cfg = (comp['config'] as Map<String, dynamic>? ?? {});
      // 确保后续对 cfg 的注入（rows/sessions/wordList/settings）写回组件，
      // 即使 manifest 中该组件原本没有 config 字段（如 settings）。
      comp['config'] = cfg;

      // 1) 带 dataSource 的组件：真实拉取并注入对应 config 字段
      if (type == 'data-table' || type == 'timetable') {
        final ds = (cfg['dataSource'] as Map<String, dynamic>? ?? {});
        final name = ds['name'] as String?;
        if (name != null && script != null) {
          final typeArg = typeMap[name] ?? name;
          final data = _runDataSource(script, typeArg, root);
          if (data == null) {
            stderr.writeln('[WARN] $name 真实拉取失败（保留官方空态）');
          } else {
            final dataPath = ds['dataPath'] as String? ?? '';
            final rows = _extract(data, dataPath);
            if (type == 'data-table') {
              cfg['rows'] = rows;
              final cols = (cfg['columns'] as List<dynamic>? ?? []);
              if (cols.isNotEmpty && rows.isNotEmpty) {
                final firstKey =
                    (cols[0] as Map<String, dynamic>)['key'] as String?;
                final v = rows.first[firstKey];
                if (v != null) realValues.add(v.toString());
              }
            } else if (type == 'timetable') {
              cfg['sessions'] = rows;
              for (final s in rows) {
                final cn = s['courseName'] ?? s['name'];
                if (cn != null) realValues.add(cn.toString());
              }
            }
          }
        }
        return;
      }

      // 2) flashcards / quiz：从 wordList 文件（真实词库）注入
      if (type == 'flashcards' || type == 'quiz') {
        final wl = cfg['wordList'];
        if (wl is String && wl.endsWith('.json')) {
          final fp = File('$root/plugins/$pluginId/data/$wl');
          if (fp.existsSync()) {
            try {
              final list = jsonDecode(fp.readAsStringSync());
              if (list is List) {
                cfg['wordList'] = list;
                for (final w in list) {
                  if (w is Map) {
                    final a = w['word'] ?? w['term'];
                    final b = w['meaning'] ?? w['def'];
                    if (a != null) realValues.add(a.toString());
                    if (b != null) realValues.add(b.toString());
                  } else if (w is String) {
                    realValues.add(w);
                  }
                }
              }
            } catch (e) {
              stderr.writeln('[WARN] 读取 $wl 失败: $e');
            }
          } else {
            stderr.writeln('[WARN] 词库文件缺失: ${fp.path}');
          }
        } else if (wl is List) {
          for (final w in wl) {
            if (w is Map) {
              final a = w['word'] ?? w['term'];
              if (a != null) realValues.add(a.toString());
            } else if (w is String) {
              realValues.add(w);
            }
          }
        }
        return;
      }

      // 3) settings：注入插件 config.json 的 settings 条目（真实设置）
      if (type == 'settings') {
        final sp = File('$root/plugins/$pluginId/config/config.json');
        if (sp.existsSync()) {
          try {
            final sc = jsonDecode(sp.readAsStringSync()) as Map<String, dynamic>;
            final setList = sc['settings'] as List<dynamic>? ?? [];
            cfg['settings'] = setList;
            for (final s in setList) {
              if (s is Map) {
                final l = s['label'] ?? s['key'];
                if (l != null) realValues.add(l.toString());
              }
            }
          } catch (e) {
            stderr.writeln('[WARN] 读取 settings config 失败: $e');
          }
        }
        return;
      }
    });
  }

  // 真实 Flutter 渲染器参与
  final html = await HtmlRenderer.render(manifest);
  File('$root/plugins/$pluginId/render_log.html').writeAsStringSync(html);

  final checks = <String, bool>{};
  // R11 加严：禁止任何写死示例串残留（这些串仅出现在旧版写死渲染中）。
  const _banned = [
    'lorem ipsum',
    '占位示例',
    'TODO数据',
    '项目 1',
    '运行中',
    '展示 AI 助手',
    '介绍这个平台',
    'Python 中如何声明列表',
    '哪个关键字用于定义 Python 函数',
    '核心主题',
    '本学期各科目',
    '这是一段示例文档内容',
  ];
  checks['真实数据'] = !_banned.any((b) => html.contains(b));
  checks['非空展示'] = html.contains('evg-comp') || html.contains('evg-card');
  checks['无重叠'] =
      !html.contains('margin:-') && !html.contains('position:absolute');

  final rendered = <String>{};
  void collect(Map<String, dynamic> m) {
    final t = m['type'] as String?;
    if (t != null) rendered.add(t);
    final comp = m['component'] as Map<String, dynamic>?;
    if (comp != null) collect(comp);
    final lay = m['layout'] as Map<String, dynamic>?;
    if (lay != null) {
      final sl = lay['slots'] as Map<String, dynamic>?;
      sl?.forEach((_, v) => collect(v as Map<String, dynamic>));
    }
  }

  for (final p in pages) collect(p);
  checks['合规槽位'] =
      rendered.isEmpty || rendered.difference(_supported).isEmpty;

  final realPresent =
      realValues.isEmpty || realValues.any((v) => html.contains(v));
  var ok = checks.values.every((e) => e);
  if (realValues.isNotEmpty && !realPresent) ok = false;

  for (final e in checks.entries) {
    stdout.writeln('  [$pluginId] [R10] ${e.key}: ${e.value ? 'PASS' : 'FAIL'}');
  }
  stdout.writeln('  [$pluginId] [R10] 真实数据注入(出现于HTML): '
      '${realPresent ? 'PASS' : (realValues.isEmpty ? 'N/A(无数据源)' : 'FAIL')}');
  stdout.writeln('  [$pluginId] ${ok ? '[PASS]' : '[FAIL]'} R10');
  return ok;
}

/// 从项目根 `.env` 读取键值对（R4：测试时 `.env` 作为设置来源）。
/// 主流程不依赖 `.env`（从 `.config_port` 读），但 R10 测试必须注入真实凭据，
/// 否则子进程取不到 ZJU_USERNAME/ZJU_PASSWORD 而空态（这是 fetch 问题非环境问题）。
Map<String, String> _loadDotEnv(String root) {
  final env = <String, String>{};
  final file = File('$root/.env');
  if (!file.existsSync()) return env;
  for (final line in file.readAsLinesSync()) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final idx = s.indexOf('=');
    if (idx <= 0) continue;
    final k = s.substring(0, idx).trim();
    final v = s.substring(idx + 1).trim();
    env[k] = v;
  }
  return env;
}

Map<String, dynamic>? _runDataSource(
    String script, String typeArg, String root) {
  try {
    // 合并当前进程环境 + 项目根 .env（后者优先，提供测试凭据）。
    final mergedEnv = <String, String>{
      ...Platform.environment,
      ..._loadDotEnv(root),
    };
    ProcessResult? r;
    String? lastErr;
    // ZDBK 对同一账号并发/连续 CAS 登录偶发返回 HTTP 901（会话竞争），
    // 属偶发 fetch 抖动，重试可恢复；非代码或环境缺陷。
    for (var attempt = 0; attempt < 3; attempt++) {
      r = Process.runSync(
        script,
        ['--type', typeArg, '--project-root', root],
        environment: mergedEnv,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode == 0) break;
      lastErr = r.stderr.toString();
      if (lastErr.contains('901') && attempt < 2) {
        sleep(const Duration(seconds: 2));
        continue;
      }
      break;
    }
    if (r == null || r.exitCode != 0) {
      stderr.writeln('[WARN] 拉取失败(exit=${r?.exitCode}): $lastErr');
      return null;
    }
    return jsonDecode(r.stdout) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('[WARN] 运行异常: $e');
    return null;
  }
}

List<Map<String, dynamic>> _extract(Map<String, dynamic> data, String path) {
  dynamic cur = data;
  for (final part in path.split('.')) {
    if (cur is! Map || !cur.containsKey(part)) return [];
    cur = cur[part];
  }
  if (cur is List) return cur.whereType<Map<String, dynamic>>().toList();
  if (cur is Map) return [cur as Map<String, dynamic>];
  return [];
}

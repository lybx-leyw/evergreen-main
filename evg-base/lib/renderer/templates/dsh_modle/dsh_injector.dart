/// DSH 注入器——平台往用户本地 DSH home 注入 evergreen 能力。
///
/// 职责（Phase 2 第一批，聚焦数据源创作最小闭环）：
/// 1. **路径契约**：写 `~/.dsh/evergreen-bridge.json`，让 DSH 的 tool 知道
///    Evergreen 的 pluginsDir / dataHttpPort / projectRoot（DSH workspace 自由，
///    不能靠相对路径）。
/// 2. **注入 preset**：写 `~/.dsh/.agent-presets/evergreen/{agent.cordis.yml, preset.yml}`
///    （裁剪版，挂载我们的 tool 插件）。
/// 3. **注入 skill**：写 `~/.dsh/skills/evg-scraper-create/SKILL.md`（数据源创作技能）。
/// 4. **注入 tool 插件**：写 `~/.dsh/.agent-presets/evergreen/plugins/evg-tools.mjs`
///    （ESM 单文件 tool 插件，相对路径被 preset 的 agent.cordis.yml 加载）。
///
/// 全部幂等写入：不覆盖用户已有同名文件（除非 force）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/data/orchestrator.dart';
import 'package:evergreen_base/core/data/register_data_source.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_skill_const.dart'
    show scraperSkillBody;

/// DSH home 目录（`~/.dsh`）。
///
/// Windows：`%USERPROFILE%\.dsh`；其它：`$HOME/.dsh`。可用 `DSH_HOME` 覆盖。
String dshHomeDir() {
  final env = Platform.environment['DSH_HOME'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return p.join(home, '.dsh');
}

/// 桥接文件路径（路径契约）。
String dshBridgePath() => p.join(dshHomeDir(), 'evergreen-bridge.json');

/// evergreen preset 目录。
String dshPresetDir() => p.join(dshHomeDir(), '.agent-presets', 'evergreen');

/// evergreen skill 目录。
String dshSkillDir() => p.join(dshHomeDir(), 'skills', 'evg-scraper-create');

/// 注入结果（供 UI 展示 / 调试）。
class DshInjectResult {
  final bool bridgeOk;
  final bool presetOk;
  final bool skillOk;
  final bool toolOk;
  final String bridgePath;

  const DshInjectResult({
    required this.bridgeOk,
    required this.presetOk,
    required this.skillOk,
    required this.toolOk,
    required this.bridgePath,
  });

  bool get allOk => bridgeOk && presetOk && skillOk && toolOk;
}

/// 执行完整注入：写 bridge + preset + skill + tool。
///
/// 参数为 Evergreen 侧已知信息（由 DSH-mode 视图在「连接」时传入）。
/// 幂等：已有同名文件且未 [force] 时跳过（保留用户自定义）。
DshInjectResult injectEvergreen({
  required String pluginsDir,
  required int dataHttpPort,
  required int scraperBridgePort,
  required String projectRoot,
  bool force = false,
}) {
  final bridgeOk = _writeBridge(
    pluginsDir: pluginsDir,
    dataHttpPort: dataHttpPort,
    scraperBridgePort: scraperBridgePort,
    projectRoot: projectRoot,
    force: force,
  );
  final presetOk = _writePreset(force: force);
  final skillOk = _writeSkill(force: force);
  final toolOk = _writeTool(force: force);
  return DshInjectResult(
    bridgeOk: bridgeOk,
    presetOk: presetOk,
    skillOk: skillOk,
    toolOk: toolOk,
    bridgePath: dshBridgePath(),
  );
}

// ── bridge 文件 ──

bool _writeBridge({
  required String pluginsDir,
  required int dataHttpPort,
  required int scraperBridgePort,
  required String projectRoot,
  required bool force,
}) {
  try {
    final file = File(dshBridgePath());
    if (!force && file.existsSync()) return true; // 幂等：已存在即视为成功
    file.parent.createSync(recursive: true);
    final json = jsonEncode({
      'pluginsDir': pluginsDir,
      'dataHttpPort': dataHttpPort,
      'scraperBridgePort': scraperBridgePort,
      'projectRoot': projectRoot,
      'generatedAt': DateTime.now().toIso8601String(),
    });
    file.writeAsStringSync(json);
    return true;
  } catch (e) {
    debugLog('⚠ 写 bridge 文件失败: $e');
    return false;
  }
}

// ── evergreen preset ──

bool _writePreset({required bool force}) {
  try {
    final dir = Directory(dshPresetDir());
    final cordisFile = File(p.join(dir.path, 'agent.cordis.yml'));
    final metaFile = File(p.join(dir.path, 'preset.yml'));

    // 幂等：两文件都已存在且未 force → 跳过（保留用户自定义）。
    if (!force && cordisFile.existsSync() && metaFile.existsSync()) return true;

    dir.createSync(recursive: true);

    // 裁剪版 preset：基于 minimal，去掉 str_replace_editor，保留 shell + fs + skill，
    // persona 改为 Evergreen 数据源创作身份，并挂载我们的 tool 插件（相对路径）。
    cordisFile.writeAsStringSync(_presetCordisYml);
    metaFile.writeAsStringSync(_presetMetaYml);
    return true;
  } catch (e) {
    debugLog('⚠ 写 evergreen preset 失败: $e');
    return false;
  }
}

/// 相对路径插件从 preset 目录解析（`./plugins/evg-tools.mjs`）。
/// `ctx.tools` 由 dsh-base host 提供，tool 插件经 `inject: ['tools']` 消费。
const String _presetCordisYml = '''
# Evergreen 平台数据源创作 Agent preset（裁剪版，Phase 2 第一批）。
# 基于 minimal 裁剪：去掉 str_replace_editor，保留 shell + fs + skill，
# persona 改为 Evergreen 身份，挂载平台交互 tool（evg-tools）。
- id: persona
  name: '@deepseek-ai/dsh-persona'
  config:
    text: You are the Evergreen micro-tool platform's data-source authoring agent. You help users create data sources (scrapers) for Evergreen. Read and follow the evg-scraper-create skill for authoring conventions. Use the evg_register_data_source tool to register a completed data source into the platform.
    complete: true
    includeRuntimeContext: false

- id: persistent-shell
  name: cordis:group
  group: true
  isolate:
    terminals: true
  config:
    - id: pty
      name: '@deepseek-ai/dsh-terminal'
    - id: terminal-bash
      name: '@deepseek-ai/dsh-terminal-bash'
      config:
        timeoutMs: 300000
    - id: persistent-bash
      name: '@deepseek-ai/dsh-tool-bash-persistent'
      config:
        timeoutMs: 300000

- id: filesystem
  name: cordis:group
  group: true
  isolate:
    fs: true
  config:
    - id: fs-local
      name: '@deepseek-ai/dsh-fs-local'
      config:
        cwd: !!js process.env.DSH_CWD ?? process.cwd()

- id: skills
  name: '@deepseek-ai/dsh-skill-filesystem'

- id: tool-skill
  name: '@deepseek-ai/dsh-tool-skill'

# 平台交互 tool 插件（相对路径 → 从 preset 目录解析）。
- id: evg-tools
  name: ./plugins/evg-tools.mjs
''';

const String _presetMetaYml = '''
name: Evergreen 数据源创作
description: 平台数据源创作 Agent，含 Shell、文件、Skills 与数据源注册能力。
''';

// ── evg-scraper-create skill ──

bool _writeSkill({required bool force}) {
  try {
    final file = File(p.join(dshSkillDir(), 'SKILL.md'));
    if (!force && file.existsSync()) return true;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_skillMd);
    return true;
  } catch (e) {
    debugLog('⚠ 写 evg-scraper-create skill 失败: $e');
    return false;
  }
}

/// skill 内容：**完整移植官方 scraperSkillBody（定向）+ scraperExploreSkillBody（探索）**。
///
/// DSH 侧工具名与官方工具名完全一致（经 `/scraper/tool` 转发到官方 Registry），
/// 因此 skill 正文几乎原样复用官方实战打磨的完整 SOP（铁律 / 锁定模板 /
/// 工作流程 / 守卫红线 / 成功案例），仅在开头加 DSH 环境说明。
String get _skillMd => '''
---
name: evg-scraper-create
description: 为 Evergreen 平台创作数据源（scraper）。完整工作流：浏览抓包 → 分析 API → 编写 scraper.py → 调试 → 打包热注册。当用户要求「抓取某网站数据」「创建一个数据源」「爬某个榜单」时使用。
whenToUse: 用户需要为 Evergreen 微工具平台创作一个新数据源（爬虫）时。
---

# 🔧 Evergreen 数据源创作（DSH 版）

> 你运行在 DeepSeek Harness 中，通过 RPC 驱动平台真实的 scraper 能力
> （WebView 抓包 / Python 执行 / 数据源热注册）。下面的工具虽由平台执行，
> 但你按官方 scraper 的完整 SOP 调用即可——工具名与官方完全一致。

## 浏览器直控工具（探索网页用）

- `evg_browse(url)` —— 导航真实 WebView 到 URL（用户可在 scraper 插件看到浏览器被操作）
- `evg_explore_links()` —— 枚举当前页所有 http(s) 链接
- `evg_get_requests()` —— 获取抓包的 HTTP 请求日志（method/url/responseBody）
- `evg_current_url()` —— 当前浏览器地址

---

${scraperSkillBody}
''';

// ── evg-tools 插件（ESM 单文件） ──

bool _writeTool({required bool force}) {
  try {
    final file = File(p.join(dshPresetDir(), 'plugins', 'evg-tools.mjs'));
    if (!force && file.existsSync()) return true;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_toolMjs);
    return true;
  } catch (e) {
    debugLog('⚠ 写 evg-tools 插件失败: $e');
    return false;
  }
}

/// ESM tool 插件：注册平台交互工具（薄壳 RPC 转发）。
///
/// B 方案：DSH 的 tool 是「薄壳」——execute 里 fetch 平台 ScraperBridgeServer，
/// 转发给「活跃 ScraperAIPanel 的官方工具 Registry」执行（100% 复用官方逻辑）。
///
/// 两类工具：
/// 1. **官方工具名薄壳**（与官方 scraper 工具名完全一致，转发 `/scraper/tool`）：
///    run_python_scraper / get_request_logs / read_request_snapshot /
///    read_workspace_file / save_credential / read_existing_credential /
///    run_terminal_command / export_and_register_scraper / set_data_name /
///    set_env_var / list_env_vars。
///    这样 scraperSkillBody 里的工具名可直接复用，agent 调这些工具即转发到
///    官方工具执行（含 lint / Guardian / 真实数据验收 / UI 气泡）。
/// 2. **浏览器直控**（转发 WebView bridge，探索用）：
///    evg_browse / evg_explore_links / evg_get_requests / evg_current_url。
const String _toolMjs = r'''
import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { defineTool } from '@deepseek-ai/dsh-tools'

export const name = 'evg-tools'
export const inject = ['tools']

function bridgePath() {
  const dshHome = process.env.DSH_HOME ?? join(homedir(), '.dsh')
  return join(dshHome, 'evergreen-bridge.json')
}

async function readBridge() {
  const raw = await readFile(bridgePath(), 'utf8')
  return JSON.parse(raw)
}

// 通用 RPC：POST/GET 到平台 ScraperBridgeServer。
async function rpc(bridge, path, { method = 'GET', body } = {}) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } }
  if (body !== undefined) opts.body = JSON.stringify(body)
  const resp = await fetch(`http://127.0.0.1:${bridge.scraperBridgePort}${path}`, opts)
  const data = await resp.json().catch(() => ({}))
  if (!resp.ok) {
    throw new Error(data.error || data.code || `HTTP ${resp.status}`)
  }
  return data
}

function stringOut() {
  return { schema: { type: 'string' }, render: (_a, v) => [{ type: 'text', text: v }] }
}

// 官方工具转发薄壳：把官方 scraper 工具名注册为 DSH 工具，
// execute 里 fetch /scraper/tool 转发给平台官方工具 Registry。
function forwardTool(name, description, paramSpecs) {
  return defineTool({
    name,
    description,
    parameters: paramSpecs,
    output: stringOut(),
    async execute(args) {
      try {
        const bridge = await readBridge()
        const r = await rpc(bridge, '/scraper/tool', { method: 'POST', body: { name, args } })
        return r.result ?? '[no result]'
      } catch (e) {
        return `[error: ${e.message}]`
      }
    },
  })
}

export function apply(ctx) {
  // ═══ 官方工具薄壳（转发到平台官方工具 Registry，工具名与官方一致）═══

  ctx.tools.register(forwardTool(
    'run_python_scraper',
    'Write the given Python scraper code to scraper.py and run it with the ' +
    'platform Python interpreter, then validate the stdout JSON. Use this to ' +
    'write and test your scraper (this is the ONLY way to write scraper.py).',
    { code: { type: 'string', required: true, description: 'Complete Python scraper code (with import/main())' } },
  ))

  ctx.tools.register(forwardTool(
    'get_request_logs',
    'Get the HTTP requests captured by the embedded browser during the current ' +
    'session (method/url/headers/body/responseBody). Use this to find the API ' +
    'endpoint that returns the data you need.',
    {},
  ))

  ctx.tools.register(forwardTool(
    'read_request_snapshot',
    'Read the frozen request-log snapshot after the user confirms capture is done.',
    {},
  ))

  ctx.tools.register(forwardTool(
    'read_workspace_file',
    'Read a file from the scraper workspace (<=50KB). Do not read scraper_sessions.json.',
    { path: { type: 'string', required: true, description: 'File path relative to workspace' } },
  ))

  ctx.tools.register(forwardTool(
    'save_credential',
    'Write a credential key/value to the platform config (for scraper.py _get_config).',
    { key: { type: 'string', required: true, description: 'Credential key, e.g. SCRAPER_USERNAME' }, value: { type: 'string', required: true, description: 'Credential value' } },
  ))

  ctx.tools.register(forwardTool(
    'read_existing_credential',
    'Check whether a plugin already has credential config (reuse before registering new).',
    { plugin_name: { type: 'string', required: true, description: 'Data source name (without data- prefix)' } },
  ))

  ctx.tools.register(forwardTool(
    'run_terminal_command',
    'Run a command in the scraper terminal (e.g. pip install). Subject to the command guard.',
    { command: { type: 'string', required: true, description: 'Command to run' } },
  ))

  ctx.tools.register(forwardTool(
    'export_and_register_scraper',
    'Package scraper.py as a data plugin, hot-register it, and verify data-center ' +
    'fetch. Call this AFTER run_python_scraper succeeds. The returned log tells you ' +
    'whether registration and fetch verification passed.',
    {},
  ))

  ctx.tools.register(forwardTool(
    'set_data_name',
    'Lock the data source root name (must match the user-specified name).',
    { name: { type: 'string', required: true, description: 'Data source name (snake_case)' } },
  ))

  ctx.tools.register(forwardTool(
    'set_env_var',
    'Write/update an environment variable (user account/password credential). ' +
    'Persisted to .greenix/env.json and injected into every Python subprocess, ' +
    'so scraper.py can read it via _get_config("KEY") or os.environ["KEY"]. ' +
    'Key must start with an uppercase letter and contain only A-Z/0-9/_ (e.g. SCRAPER_USERNAME).',
    { key: { type: 'string', required: true, description: 'Env var name, e.g. SCRAPER_USERNAME' }, value: { type: 'string', required: true, description: 'Env var value (username/password/cookie/token)' } },
  ))

  ctx.tools.register(forwardTool(
    'list_env_vars',
    'List the keys of environment variables already set (values are NOT echoed). ' +
    'Use to confirm whether credentials like SCRAPER_USERNAME/SCRAPER_PASSWORD are written.',
    {},
  ))

  // ═══ 浏览器直控（探索模式用，转发 WebView bridge）═══

  ctx.tools.register(defineTool({
    name: 'evg_browse',
    description: 'Navigate the embedded browser (real WebView2) to a URL for exploration.',
    parameters: { url: { type: 'string', required: true, description: 'Target URL (http/https)' } },
    output: stringOut(),
    async execute(args) {
      try {
        const bridge = await readBridge()
        await rpc(bridge, '/scraper/navigate', { method: 'POST', body: { url: args.url } })
        return `Navigated to ${args.url}`
      } catch (e) { return `[error: ${e.message}]` }
    },
  }))

  ctx.tools.register(defineTool({
    name: 'evg_explore_links',
    description: 'Enumerate http(s) links on the current page (for exploration mode).',
    parameters: {},
    output: stringOut(),
    async execute() {
      try {
        const bridge = await readBridge()
        const script = 'JSON.stringify(Array.from(document.querySelectorAll("a[href]")).map(a=>a.href).filter(h=>/^https?:/.test(h)))'
        const r = await rpc(bridge, '/scraper/evaluate', { method: 'POST', body: { script } })
        return r.result ?? '[no result]'
      } catch (e) { return `[error: ${e.message}]` }
    },
  }))

  ctx.tools.register(defineTool({
    name: 'evg_get_requests',
    description: 'Get captured HTTP requests (method/url/responseBody) from the browser.',
    parameters: {},
    output: stringOut(),
    async execute() {
      try {
        const bridge = await readBridge()
        const r = await rpc(bridge, '/scraper/requests', { method: 'GET' })
        return JSON.stringify(r.logs ?? [])
      } catch (e) { return `[error: ${e.message}]` }
    },
  }))

  ctx.tools.register(defineTool({
    name: 'evg_current_url',
    description: 'Get the current URL of the embedded browser.',
    parameters: {},
    output: stringOut(),
    async execute() {
      try {
        const bridge = await readBridge()
        const r = await rpc(bridge, '/scraper/current', { method: 'GET' })
        return r.url ?? '[no url]'
      } catch (e) { return `[error: ${e.message}]` }
    },
  }))
}
''';

void debugLog(String msg) {
  // 与平台日志一致：debugPrint 在 release 下不可见，这里保留 assert 内打印。
  assert(() {
    // ignore: avoid_print
    print('[DshInjector] $msg');
    return true;
  }());
}

// ── 文件 watcher（「两者结合」的主方案：轮询兜底）──

/// 扫描 [pluginsDir] 下所有 `data-*/` 插件，注册尚未注册的数据源。
///
/// 这是「两者结合」的主方案兜底：DSH tool 写数据源产物后若 HTTP 触发失败
/// （端口未发现/进程间瞬时不可达），本函数由 DSH-mode 视图周期轮询调用，
/// 发现新 manifest 即热注册。
///
/// 返回本次新注册的类型名列表（无新增则空）。
List<String> rescanDataSources({
  required String pluginsDir,
  required DataOrchestrator orch,
}) {
  final dir = Directory(pluginsDir);
  if (!dir.existsSync()) return [];
  final registered = orch.registeredTypes.toSet();
  final newly = <String>[];

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final base = p.basename(entity.path);
    if (!base.startsWith('data-')) continue;
    // 读 manifest 的 dataTypes，若全已注册则跳过（避免重复注册覆盖 fetcher）。
    final manifestFile = File(p.join(entity.path, 'data', 'manifest.json'));
    if (!manifestFile.existsSync()) continue;
    try {
      final json = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      if (json['type'] != 'data-source') continue;
      final dataTypes = (json['dataTypes'] as List<dynamic>?) ?? [];
      final names = dataTypes
          .whereType<Map<String, dynamic>>()
          .map((d) => d['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final hasNew = names.any((n) => !registered.contains(n));
      if (!hasNew) continue;
      final projectRoot = _projectRootFallback();
      final registeredNow = registerDataSourcesFromManifest(
        orch: orch,
        pluginDir: entity.path,
        projectRoot: projectRoot,
      );
      newly.addAll(registeredNow);
    } catch (e) {
      debugLog('⚠ rescan 解析 ${manifestFile.path} 失败: $e');
    }
  }
  return newly;
}

String _projectRootFallback() {
  // 与平台其它模块一致：桌面向上找 pubspec.yaml，找不到回退 cwd。
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

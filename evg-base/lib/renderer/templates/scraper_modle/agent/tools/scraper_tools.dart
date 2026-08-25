/// 爬虫生成器自定义 Agent 工具。
///
/// 提供两个核心工具：
/// - `run_python_scraper(code)` — 执行 Python 爬虫代码并返回 stdout/stderr
/// - `save_credential(key, value)` — 通过 ConfigHttpServer 写入凭证
///
/// 这些工具注册到隔离 Agent 的 Registry 中，由 AI 在生成爬虫时调用。
library scraper_tools;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/config/credential_store.dart';
import 'package:evergreen_base/core/plugin/plugin_runner.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/core/utils/python_env.dart';
import '../../scraper_env.dart';
import '../../scraper_json_validator.dart';

// ═══════ run_python_scraper ═══════

/// 工具：运行 Python 爬虫代码。
///
/// 将 AI 生成的代码写入临时 .py 文件，用 Platform 发现的 Python 解释器执行，
/// 捕获 stdout/stderr 返回给 AI 分析。
class RunPythonScraperTool extends SimpleTool {
  /// 工作目录——Python 文件写入和运行位置。
  final String workspaceDir;

  /// Python 可执行文件路径（调用方注入，避免每次都 resolve）。
  final Future<String?> Function() resolvePython;

  /// 环境变量存储（注入子进程环境；null = 不注入）。
  final ScraperEnvStore? envStore;

  RunPythonScraperTool({
    required this.workspaceDir,
    required this.resolvePython,
    this.envStore,
  }) : super(
          name: 'run_python_scraper',
          description: '运行生成的 Python 爬虫代码。'
              '将代码写入 scraper.py 并用 Python 解释器执行，返回 stdout/stderr。'
              '若执行失败，请分析错误原因并修改代码后重试（最多 5 轮）。',
          schema: const {
            'type': 'object',
            'properties': {
              'code': {
                'type': 'string',
                'description': '完整的 Python 爬虫代码（含 import/main()）',
              },
            },
            'required': ['code'],
          },
          readOnly: false,
          execute: (args) async {
            final code = args['code'] as String? ?? '';
            if (code.isEmpty) return '[error: code 参数为空]';

            final dir = Directory(workspaceDir);
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }

            // 写入 scraper.py
            final scriptPath = p.join(workspaceDir, 'scraper.py');
            await File(scriptPath).writeAsString(code);
            debugPrint('[RunPythonScraper] 写入脚本: $scriptPath');

            // 发现 Python
            final pyExe = await resolvePython();
            if (pyExe == null) {
              return '[error: 未找到 Python 解释器，请确认 Python 3.8+ 已安装]';
            }

            debugPrint('[RunPythonScraper] 执行: $pyExe $scriptPath');
            try {
              final String stdout;
              final String stderr;
              final int exitCode;

              if (Platform.isAndroid) {
                // 安卓：resolvePythonExe 返回哨兵 'chaquopy'（进程内解释器），
                // 不能直接当命令执行（/system/bin/sh: chaquopy: not found）
                // → 必须走 ChaquopyRunner 经 MethodChannel('evergreen/python')。
                // 原生侧从 args 提取 --project-root / --greenix-config 注入环境变量。
                final runner = await sharedPluginRunner;
                final r = await runner.runOnce(
                  scriptPath,
                  [
                    '--project-root', workspaceDir,
                    '--greenix-config', greenixConfigPath,
                  ],
                  workingDirectory: workspaceDir,
                ).timeout(const Duration(seconds: 60));
                stdout = r.stdout.trim();
                stderr = r.stderr.trim();
                exitCode = r.exitCode;
                debugPrint('[RunPythonScraper] chaquopy 执行完成 exitCode=$exitCode');
              } else {
                final result = await Process.run(
                  pyExe,
                  [scriptPath],
                  workingDirectory: workspaceDir,
                  runInShell: true,
                  environment: envStore != null
                      ? envStore!.envForSubprocess(workspaceDir)
                      : Map<String, String>.from(
                          Platform.environment,
                        )..['PROJECT_ROOT'] = workspaceDir,
                ).timeout(const Duration(seconds: 60));
                stdout = (result.stdout as String).trim();
                stderr = (result.stderr as String).trim();
                exitCode = result.exitCode;
              }

              if (exitCode == 0) {
                // 与平台一致的 JSON 校验：scraper stdout 必须是合法 JSON，
                // 否则平台 jsonDecode(stdout) 会在运行期「检验失败」。
                // 这里让 AI 循环提前看到校验日志并自我修正，而非误判为成功。
                final validation = validateScraperStdout(stdout);
                if (!validation.isValid) {
                  debugPrint('[RunPythonScraper] ❌ JSON 输出校验失败');
                  return buildJsonValidationFailureMessage(
                    stdout,
                    error: validation.error,
                  );
                }
                debugPrint('[RunPythonScraper] ✅ 执行成功且 JSON 校验通过');
                return buildJsonValidationSuccessMessage(
                  truncateToolOutput(stdout),
                  stderr,
                );
              } else {
                debugPrint(
                    '[RunPythonScraper] ❌ 执行失败 (exitCode=$exitCode)');
                return '❌ 爬虫执行失败 (exitCode=$exitCode)\n'
                    '--- STDOUT ---\n${truncateToolOutput(stdout)}\n'
                    '--- STDERR ---\n${truncateToolOutput(stderr)}\n'
                    '请根据错误信息修改代码后，再次调用 run_python_scraper 重试。';
              }
            } catch (e) {
              debugPrint('[RunPythonScraper] 💥 执行异常: $e');
              return '[error: Python 执行异常: $e]';
            }
          },
        );
}

// ═══════ read_existing_credential ═══════

/// 工具：读取指定插件的现有凭证配置。
///
/// 检查 `plugins/data-{name}/config/config.json` 是否存在，
/// 若存在则返回已声明的凭证字段列表，AI 可直接在 scraper.py 中
/// 通过 `_get_config(key)` 使用这些凭证，无需重复注册。
/// 仅当现有凭证登录失败后才需要调用 save_credential 更新。
class ReadExistingCredentialTool extends SimpleTool {
  final String projectRoot;

  ReadExistingCredentialTool({required this.projectRoot})
      : super(
          name: 'read_existing_credential',
          description: '检查指定数据名称的插件是否已有凭证配置。'
              '若 plugins/data-{名称}/config/config.json 存在，返回已声明的凭证字段（key/label/type）。'
              '已存在的凭证可直接在 scraper.py 中通过 _get_config(key) 使用，无需重新调用 save_credential。'
              '**仅在旧凭证反复登录失败后才需要 save_credential 更新值。**',
          schema: const {
            'type': 'object',
            'properties': {
              'plugin_name': {
                'type': 'string',
                'description': '数据名称（如 courses），对应 plugins/data-{名称}/ 目录',
              },
            },
            'required': ['plugin_name'],
          },
          readOnly: true,
          execute: (args) async {
            final pluginName = args['plugin_name'] as String? ?? '';
            if (pluginName.isEmpty) return '[error: 缺少 plugin_name 参数]';

            final pluginsDir = resolvePluginsRoot();
            final configPath = p.join(pluginsDir, 'data-$pluginName', 'config', 'config.json');
            final configFile = File(configPath);
            if (!configFile.existsSync()) {
              return '⚠️ 未找到 $configPath\n'
                  '→ 这是全新插件，尚未配置凭证。请进入「保存凭证」步骤（save_credential）注册新凭证。';
            }

            try {
              final configJson =
                  jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
              final settings = (configJson['settings'] as List<dynamic>?) ?? [];
              if (settings.isEmpty) {
                return '📄 $configPath 存在但无凭证字段声明。';
              }

              final buf = StringBuffer();
              buf.writeln('✅ **找到现有凭证配置**: `$configPath`\n');
              for (final item in settings) {
                if (item is! Map<String, dynamic>) continue;
                final key = item['key'] as String? ?? '';
                final label = item['label'] as String? ?? key;
                final type = item['type'] as String? ?? 'string';
                buf.writeln('- `${key}` — $label (type: $type)');
              }
              buf.writeln();
              buf.writeln('➡ **直接使用**：在 `scraper.py` 中通过 `_get_config("KEY")` 读取上述凭证。');
              buf.writeln('⚠️ **不要调用 save_credential** 重复注册——先用现有凭证跑一遍，'
                  '失败后再考虑更新。');
              return buf.toString();
            } catch (e) {
              return '[error: 读取 $configPath 失败: $e]';
            }
          },
        );
}

// ═══════ save_credential ═══════

/// 工具：直写平台凭证（[CredentialStore.writeCredentialDirect]）。
///
/// 凭证写入 SharedPreferences + 镜像 `.greenix/config.json`。T9 起去掉
/// `.config_port` 端口文件的硬依赖——不再要求 ConfigHttpServer 在线，未启动时
/// 直写同样生效；后续生成的 Python 脚本经 `_get_config(key)` 从 greenix
/// config.json 读取（SP 侧同时让 getSetting 一致）。
class SaveCredentialTool extends SimpleTool {
  /// 可选注入 SharedPreferences；缺省时延迟 [SharedPreferences.getInstance]。
  final SharedPreferences? prefs;

  SaveCredentialTool({this.prefs})
      : super(
          name: 'save_credential',
          description: '将爬虫所需凭证写入/更新到平台配置。'
              '⚠️ 优先使用 read_existing_credential 检查现成凭证——仅旧凭证失败或全新插件时才调用本工具。'
              '写入后，生成的 Python 脚本通过 _get_config(key) 函数即可读取。'
              'key 命名规范：SCRAPER_USERNAME / SCRAPER_PASSWORD / SCRAPER_COOKIE / SCRAPER_TOKEN。',
          schema: const {
            'type': 'object',
            'properties': {
              'key': {
                'type': 'string',
                'description': '凭证键名（如 SCRAPER_USERNAME）',
              },
              'value': {
                'type': 'string',
                'description': '凭证值（用户名/密码/Cookie/Token）',
              },
            },
            'required': ['key', 'value'],
          },
          readOnly: false,
          execute: (args) async {
            final key = args['key'] as String? ?? '';
            final value = args['value'] as String? ?? '';
            if (key.isEmpty) return '[error: key 参数为空]';

            try {
              final p = prefs ?? await SharedPreferences.getInstance();
              await writeCredentialDirect(
                prefs: p,
                key: key,
                value: value,
                configPath: greenixConfigPath,
              );
              debugPrint('[SaveCredential] ✅ $key 已直写 SP + config.json');
              return '✅ 凭证 "$key" 已保存到平台配置。';
            } catch (e) {
              debugPrint('[SaveCredential] 💥 直写异常: $e');
              return '[error: 保存凭证失败: $e]';
            }
          },
        );
}

// ═══════ set_env_var / list_env_vars ═══════

/// 工具：写入/更新爬虫环境变量（用户账号密码等凭据）。
///
/// 背景（用户反馈 bug）：探索模式禁用 `run_terminal_command`/`save_credential`，
/// AI 无法把用户账号密码写入环境变量，登录验证/构建脚本读不到凭据。
/// 本工具把 key/value 持久化到 `.greenix/env.json`（并镜像到
/// `.greenix/config.json`），运行 Python 子进程时自动合并进环境变量——
/// scraper.py 中 `_get_config(key)`（Tier 3 os.environ）或 `os.environ[key]`
/// 即可读取。
class SetEnvVarTool extends SimpleTool {
  final ScraperEnvStore envStore;

  SetEnvVarTool({required this.envStore})
      : super(
          name: 'set_env_var',
          description: '写入/更新一个环境变量（账号密码等凭据）。'
              '持久化到 .greenix/env.json，运行 Python 时自动注入子进程环境变量。'
              '写入后 scraper.py 中可用 _get_config("KEY") 或 os.environ["KEY"] 读取。'
              'key 必须大写字母开头，仅含大写字母/数字/下划线（如 SCRAPER_USERNAME / '
              'SCRAPER_PASSWORD / SCRAPER_COOKIE / SCRAPER_TOKEN）。'
              '⚠️ 优先用 read_existing_credential 复用现成配置；仅需要新凭据时再写入。',
          schema: const {
            'type': 'object',
            'properties': {
              'key': {
                'type': 'string',
                'description': '环境变量名（如 SCRAPER_USERNAME）',
              },
              'value': {
                'type': 'string',
                'description': '环境变量值（用户名/密码/Cookie/Token）',
              },
            },
            'required': ['key', 'value'],
          },
          readOnly: false,
          execute: (args) async {
            try {
              final key = args['key'] as String? ?? '';
              final value = args['value'] as String? ?? '';
              if (key.isEmpty) return '[error: key 参数为空]';
              return envStore.setVar(key, value);
            } catch (e) {
              debugPrint('[SetEnvVar] 💥 $e');
              return '[error: 写入环境变量失败: $e]';
            }
          },
        );
}

/// 工具：列出已设置的环境变量（值不回显，只列 key）。
class ListEnvVarsTool extends SimpleTool {
  final ScraperEnvStore envStore;

  ListEnvVarsTool({required this.envStore})
      : super(
          name: 'list_env_vars',
          description: '列出当前已设置的环境变量 key（值不回显）。'
              '用于确认账号密码等凭据是否已写入；未设置时返回写入指引。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async => envStore.listSummary(),
        );
}

// ═══════ get_request_logs ═══════

/// 工具：获取当前捕获到的 HTTP 请求日志。
///
/// 返回 AI 友好的日志摘要，供分析和生成爬虫代码。
class GetRequestLogsTool extends SimpleTool {
  /// 获取日志的回调——由 UI 层注入，实时返回当前的日志列表。
  final String Function() getLogsSummary;

  GetRequestLogsTool({required this.getLogsSummary})
      : super(
          name: 'get_request_logs',
          description: '获取用户在 WebView 中操作时捕获的 HTTP 请求日志。'
              '日志按时间排序，包含 method、URL、headers、body。'
              '用于分析登录流程和目标数据接口。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            final summary = getLogsSummary();
            if (summary.isEmpty || summary == '(暂无请求日志)') {
              return '(暂无请求日志) 请用户在 WebView 中操作目标网站后重试。';
            }
            debugPrint('[GetRequestLogs] 返回 ${summary.length} chars 的日志摘要');
            return summary;
          },
        );
}

// ═══════ run_terminal_command ═══════

/// 工具：在终端中执行命令并将输出回传给 AI。
///
/// AI 通过此工具发送命令（如 `python scraper.py`），命令在终端可视化执行，
/// 执行完成后输出回传给 AI 供下一步决策。
class RunTerminalCommandTool extends SimpleTool {
  /// 将命令入队到终端的回调。
  final void Function(String command) enqueueCommand;

  /// 获取终端执行结果的回调（阻塞直到命令执行完成）。
  final Future<String> Function() getResult;

  RunTerminalCommandTool({
    required this.enqueueCommand,
    required this.getResult,
  }) : super(
          name: 'run_terminal_command',
          description: '在左下角 bash 终端中执行命令并获取输出。'
              '将命令发送到终端可视化执行，等待执行完成后返回 stdout/stderr。'
              '用户可在终端中实时看到命令执行过程和结果。'
              '⚠️ 命令受守卫约束：仅白名单命令（python scraper.py / pip install <包名> / cd <目录>）'
              '自动放行；其余需用户确认；破坏性/走私命令（rm、拼接、python -c 等）将被拒绝。'
              '用法：先用 run_python_scraper 写并执行 scraper.py（没有 write_file），'
              '再用 run_terminal_command 执行 `python scraper.py` 或安装依赖。'
              '若执行失败，分析错误输出后修改代码并重新执行（连续 3 轮失败后换策略）。',
          schema: const {
            'type': 'object',
            'properties': {
              'command': {
                'type': 'string',
                'description': '要在终端中执行的 shell 命令（如 "python scraper.py" 或 "pip install requests"）',
              },
            },
            'required': ['command'],
          },
          readOnly: false,
          execute: (args) async {
            final command = args['command'] as String? ?? '';
            if (command.isEmpty) return '[error: command 参数为空]';

            debugPrint('[RunTerminalCommand] 📟 入队命令: $command');

            // 1. 将命令入队到终端（ScraperTerminal 监听 workflow 变化后执行）
            enqueueCommand(command);

            // 2. 等待终端执行完成并返回结果
            final result = await getResult();
            debugPrint('[RunTerminalCommand] 📟 执行结果 (${result.length} chars)');
            return result;
          },
        );
}

// ═══════ export_and_register_scraper ═══════

/// 工具：导出插件（打包 .py + 三件套）并热注册到数据中心，返回完整验证日志。
///
/// **root cause B 修复**：过去「导出/注册/数据中心 orch.get 验证」的结果
/// （含 scraper.py 打包失败、lastError、拉取异常、返回 null 等平台期「检验失败」）
/// 只弹在 UI（`_messages.add`），AI 永远看不到、无法自修。
///
/// 本工具让 AI 主动触发导出+注册，并把**完整结果日志**作为工具结果回传，
/// 使 AI 的调试循环能看到检验失败并修改代码/凭证后重试。
class ExportAndRegisterScraperTool extends SimpleTool {
  /// 执行导出+注册并返回完整日志的回调（由 UI 层 ScraperAIPanel 注入）。
  final Future<String> Function() runExportAndRegister;

  /// 用户指定的数据名称（来自命名对话框），用于校验 AI 传参、强制纠正。
  final String? Function() dataNameProvider;

  ExportAndRegisterScraperTool({
    required this.runExportAndRegister,
    required this.dataNameProvider,
  }) : super(
          name: 'export_and_register_scraper',
          description: '爬虫脚本跑通（run_python_scraper / run_terminal_command 返回 '
              '✅ JSON 校验通过）后调用本工具，把 scraper.py 直接打包为 data 插件'
              '（.py + manifest + config，不再编译 .exe——统一 .py 契约，安卓 Chaquopy 亦可执行）、'
              '热注册到数据中心并验证 orch.get 拉取，返回完整结果日志。'
              '日志包含 scraper.py 打包失败、lastError、拉取异常、返回 null 等平台期「检验失败」详情。'
              '若日志含 ❌ 或 lastError，请分析原因、修改 scraper 代码或凭证后，'
              '再次调用本工具重试（最多 5 轮）。',
          schema: const {
            'type': 'object',
            'properties': {
              'data_name': {
                'type': 'string',
                'description':
                    '用户指定的数据名称（如 courses）。必须与用户确认的名称完全一致，'
                    '不可自行编造或修改。',
              },
            },
            'required': ['data_name'],
          },
          readOnly: false,
          execute: (args) async {
            // ═══ 三层名称防护 ═══
            final aiName = args['data_name'] as String? ?? '';
            final userDataName = dataNameProvider() ?? '';

            // 第 2 层：AI 传参 vs 用户命名 校验
            if (aiName.isNotEmpty &&
                userDataName.isNotEmpty &&
                aiName != userDataName) {
              debugPrint(
                '[ExportAndRegister] ⚠ AI name "$aiName" ≠ user name '
                '"$userDataName" → 代码强制使用用户名称',
              );
            } else {
              debugPrint(
                '[ExportAndRegister] 🏷 data_name="$aiName" '
                '(user="$userDataName")',
              );
            }

            // 代码层始终用 _dataName（_generatePlugin 内部已强制），此处仅校验日志
            final log = await runExportAndRegister();
            final base = log.trim().isEmpty
                ? '[error: 导出/注册未产生任何日志]'
                : log;

            // 第 3 层：结果前缀明确最终使用的名称，AI 回复用户时不会自行编造
            return '📁 **数据名称: $userDataName**\n\n$base';
          },
        );
}

// ═══════ set_data_name ═══════

/// 工具：AI 在工作流中向用户索取产物根名后，回写到面板状态。
///
/// 取代原「页面打开即强制弹出的命名对话框」：产物根名（如 `courses`）
/// 现在由 AI 在 Step 0 用 `ask` 工具询问用户、拿到名称后调用本工具锁定，
/// 后续插件目录 `data-{name}`、manifest name、orch:// 类型名均以它为准。
class SetDataNameTool extends SimpleTool {
  /// 回写产物根名的回调（由 UI 层 ScraperAIPanel 注入；只记录 dataName 并原地
  /// 重命名当前会话，不切换/重建 Agent 会话——避免中断正在运行的 AI 循环）。
  final void Function(String name) setDataName;

  SetDataNameTool({required this.setDataName})
      : super(
          name: 'set_data_name',
          description: '在生成代码/导出前，锁定本次爬虫的「产物根名」（数据名称）。'
              '插件目录自动推导为 plugins/data-{name}/，manifest name 与 orch:// 类型名均为 {name}。'
              '名称必须是用户通过 ask 工具确认给出的（不可自行编造）。'
              '合法名称：小写字母/数字/下划线，2-32 字符，例如 courses、zju_grades。',
          schema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description':
                    '用户确认的产物根名（如 courses）。必须是用户 ask 后给出的真实名称。',
              },
            },
            'required': ['name'],
          },
          readOnly: false,
          execute: (args) async {
            final raw = (args['name'] as String? ?? '').trim();
            if (raw.isEmpty) {
              return '[error: name 参数为空]';
            }
            // 名称合法性校验（与插件目录命名约束一致）
            final ok = RegExp(r'^[a-z0-9_]{2,32}$').hasMatch(raw);
            if (!ok) {
              return '[error: 非法产物根名 "$raw"——仅允许小写字母/数字/下划线，'
                  '长度 2-32，例如 courses / zju_grades]';
            }
            setDataName(raw);
            return '✅ 产物根名已锁定为 "$raw"。'
                '后续插件目录 plugins/data-$raw/、manifest name=$raw、'
                'orch:// 类型名=$raw 均以此为准。';
          },
        );
}

// ═══════ guard_override ═══════

/// 工具：AI 被工作流门控拦截（lint violation / 假数据 / 证据终闸）时，
/// 请求用户对**本次拦截**做一次性放行，避免门控过严堵死工作流。
///
/// 仅当前一次拦截豁免：用户放行后，AI 重新调用被拦工具即可通过（hook 消费
/// 该豁免标记并清除）；下次同类拦截仍需重新请求放行。
/// 硬安全（命令黑名单 / 凭证非法 / 危险 import）不可豁免。
class GuardOverrideTool extends SimpleTool {
  /// 请求用户放行的回调（UI 层注入：弹窗 → 用户同意则调 workflow.requestOverride）。
  /// 返回 true=用户放行，false=拒绝。
  final Future<bool> Function(String toolName, String reason) requestOverride;

  GuardOverrideTool({required this.requestOverride})
      : super(
          name: 'guard_override',
          description: '当你被工作流门控拦截（如代码 lint violation、疑似假数据、'
              '数据源无日志证据、页面写操作 page_fill/page_submit 未授权等），'
              '且你确信当前操作是真实/合理的，可调用本工具'
              '请求用户对**本次拦截**做一次性放行。用户同意后，重新调用被拦工具'
              '即可通过；用户拒绝则需继续修正。'
              '⚠️ 仅适用于工作流门控（lint/假数据/证据/页面写操作授权）；'
              '命令黑名单、凭证非法等硬安全不可豁免。'
              '仅在确实被拦截且用户应知情决策时使用，不要滥用。',
          schema: const {
            'type': 'object',
            'properties': {
              'tool_name': {
                'type': 'string',
                'description': '被拦截的工具名（如 run_python_scraper / '
                    'export_and_register_scraper / build_selected_source / '
                    'register_batch / page_fill / page_submit）',
              },
              'reason': {
                'type': 'string',
                'description': '为何需要放行（向用户说明，如"该站是静态 JSON 页，'
                    '无 API 日志，数据为真实抓取"）',
              },
            },
            'required': ['tool_name', 'reason'],
          },
          readOnly: false,
          execute: (args) async {
            final toolName = (args['tool_name'] as String? ?? '').trim();
            final reason = (args['reason'] as String? ?? '').trim();
            if (toolName.isEmpty) return '[error: tool_name 参数为空]';
            if (reason.isEmpty) return '[error: reason 参数为空]';
            // 仅可豁免工具允许请求放行（硬安全工具拒绝，防 AI 尝试豁免命令黑名单）
            // P1-D：page_fill/page_submit（页面写操作）纳入可豁免（用户授权后放行）
            const overridable = {
              'run_python_scraper',
              'export_and_register_scraper',
              'build_selected_source',
              'register_batch',
              'page_fill',
              'page_submit',
            };
            if (!overridable.contains(toolName)) {
              return '[error: 工具 "$toolName" 不属于可豁免的门控，'
                  '（命令黑名单/凭证非法/危险 import 等硬安全不可豁免）]';
            }
            final approved = await requestOverride(toolName, reason);
            if (approved) {
              return '✅ 用户已放行 "$toolName" 的本次门控拦截。'
                  '请重新调用 "$toolName" 继续。';
            }
            return '用户拒绝放行 "$toolName"。请修正问题后重试，'
                '或询问用户期望如何处理。';
          },
        );
}

// ═══════ read_workspace_file ═══════

/// 工具：读取爬虫工作区文件内容。
///
/// 背景（2026-08-02）：scraper 工具集没有文件读取工具，AI 只能用 Python
/// 代码读文件——曾误读 8MB 的 scraper_sessions.json 导致 2.1MB 输出撑爆
/// LLM 上下文（DeepSeek 400）。本工具提供受控读取：仅限工作区内文件、
/// 单文件 ≤50KB、超出截断提示。
class ReadWorkspaceFileTool extends SimpleTool {
  /// 爬虫工作目录（scraper.py 所在目录）。
  final String workspaceDir;

  ReadWorkspaceFileTool({required this.workspaceDir})
      : super(
          name: 'read_workspace_file',
          description: '读取爬虫工作区文件内容（如 scraper.py、config_reader.py）。'
              '仅能读取工作区内文件，单文件不超过 50KB。'
              '⚠️ 禁止用 Python 代码读取文件——请优先使用本工具；'
              '禁止读取 scraper_sessions.json（会话文件可能数 MB，输出会撑爆上下文）。',
          schema: const {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '工作区内文件名或相对路径（如 scraper.py、config/config.json）',
              },
            },
            'required': ['path'],
          },
          readOnly: true,
          execute: (args) async {
            final name = args['path'] as String? ?? '';
            if (name.isEmpty) return '[error: path 参数为空]';
            // 防路径逃逸：解析后必须仍在工作区内
            final resolved = p.normalize(p.join(workspaceDir, name));
            if (!resolved.startsWith(p.normalize(workspaceDir)) ||
                resolved.contains('scraper_sessions.json')) {
              return '[error: 仅允许读取工作区内文件，且禁止读取 scraper_sessions.json]';
            }
            final file = File(resolved);
            if (!file.existsSync()) {
              return '[error: 文件不存在: $name]';
            }
            try {
              var content = file.readAsStringSync();
              if (content.length > 50000) {
                content = '${content.substring(0, 50000)}\n…[文件过大，已截断 ${content.length - 50000} 字符]';
              }
              return '文件 $name (${file.lengthSync()} 字节):\n\n$content';
            } catch (e) {
              return '[error: 读取 $name 失败: $e]';
            }
          },
        );
}

// ═══════ read_request_snapshot ═══════

/// 工具：读取已冻结的日志快照（A26/A18）。
///
/// 用户点击「确认操作完毕」后日志快照冻结；AI 通过本工具随时阅读快照
/// （快照冻结后不再更新，即便用户仍在 WebView 操作）。未冻结时读取活动日志。
class ReadRequestSnapshotTool extends SimpleTool {
  /// 获取快照摘要的回调（由 UI 层注入，返回 workflow.requestLogsSummary()）。
  final String Function() getSnapshotSummary;

  ReadRequestSnapshotTool({required this.getSnapshotSummary})
      : super(
          name: 'read_request_snapshot',
          description: '读取用户确认操作完毕后冻结的 HTTP 请求日志快照'
              '（包含 method/URL/headers/body/response）。'
              'AI 分析目标 API、登录流程、认证方式时必须使用本工具。'
              '快照在用户点击「确认操作完毕」后冻结，不再更新；'
              '若需重新抓取，请先询问用户是否重新走一遍流程。',
          schema: const {
            'type': 'object',
            'properties': {},
          },
          readOnly: true,
          execute: (args) async {
            final summary = getSnapshotSummary();
            if (summary.isEmpty || summary == '(暂无请求日志)') {
              return '(暂无请求日志快照) 请用户先在 WebView 中完成操作并点击「确认操作完毕」。';
            }
            return summary;
          },
        );
}

// ═══════ 工具集工厂 ═══════

/// 为爬虫生成器 Agent 构造所有自定义工具。
///
/// 返回的工具有以下需要 UI 层注入的回调：
/// - [resolvePython] — Python 解释器发现函数
/// - [getLogsSummary] — 日志摘要获取函数
/// - [enqueueCommand] — 终端命令入队回调
/// - [getTerminalResult] — 获取终端执行结果的 Future
/// - [exportAndRegister] — 导出插件+热注册并返回完整日志（含检验失败）的回调
List<Tool> createScraperTools({
  required String workspaceDir,
  required String projectRoot,
  required Future<String?> Function() resolvePython,
  required String Function() getLogsSummary,
  required void Function(String command) enqueueCommand,
  required Future<String> Function() getTerminalResult,
  required Future<String> Function() exportAndRegister,
  required String? Function() dataNameProvider,
  required void Function(String name) setDataName,
  required Future<bool> Function(String toolName, String reason)
      requestOverride,
  ScraperEnvStore? envStore,
}) {
  return [
    RunPythonScraperTool(
      workspaceDir: workspaceDir,
      resolvePython: resolvePython,
      envStore: envStore,
    ),
    RunTerminalCommandTool(
      enqueueCommand: enqueueCommand,
      getResult: getTerminalResult,
    ),
    ReadExistingCredentialTool(projectRoot: projectRoot),
    SaveCredentialTool(),
    // 环境变量写入/列出（用户账号密码等凭据；探索模式同样可用）
    if (envStore != null) ...[
      SetEnvVarTool(envStore: envStore),
      ListEnvVarsTool(envStore: envStore),
    ],
    GetRequestLogsTool(getLogsSummary: getLogsSummary),
    ReadWorkspaceFileTool(workspaceDir: workspaceDir),
    ExportAndRegisterScraperTool(
      runExportAndRegister: exportAndRegister,
      dataNameProvider: dataNameProvider,
    ),
    SetDataNameTool(setDataName: setDataName),
    GuardOverrideTool(requestOverride: requestOverride),
    ReadRequestSnapshotTool(getSnapshotSummary: getLogsSummary),
  ];
}

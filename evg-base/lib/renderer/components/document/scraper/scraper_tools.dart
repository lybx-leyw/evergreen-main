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

import 'package:evergreen_base/core/agent/tool.dart';
import 'package:evergreen_base/core/utils/python_env.dart';

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

  RunPythonScraperTool({
    required this.workspaceDir,
    required this.resolvePython,
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
              final result = await Process.run(
                pyExe,
                [scriptPath],
                workingDirectory: workspaceDir,
                runInShell: true,
                environment: Map<String, String>.from(
                  Platform.environment,
                )..['PROJECT_ROOT'] = workspaceDir,
              ).timeout(const Duration(seconds: 60));

              final stdout = (result.stdout as String).trim();
              final stderr = (result.stderr as String).trim();

              if (result.exitCode == 0) {
                debugPrint('[RunPythonScraper] ✅ 执行成功');
                return '✅ 爬虫执行成功 (exitCode=0)\n'
                    '--- STDOUT ---\n$stdout\n'
                    '${stderr.isNotEmpty ? '--- STDERR ---\n$stderr\n' : ''}';
              } else {
                debugPrint(
                    '[RunPythonScraper] ❌ 执行失败 (exitCode=${result.exitCode})');
                return '❌ 爬虫执行失败 (exitCode=${result.exitCode})\n'
                    '--- STDOUT ---\n$stdout\n'
                    '--- STDERR ---\n$stderr\n'
                    '请根据错误信息修改代码后，再次调用 run_python_scraper 重试。';
              }
            } catch (e) {
              debugPrint('[RunPythonScraper] 💥 执行异常: $e');
              return '[error: Python 执行异常: $e]';
            }
          },
        );
}

// ═══════ save_credential ═══════

/// 工具：通过 ConfigHttpServer 保存凭证。
///
/// 凭证写入 SharedPreferences，后续生成的 Python 脚本通过
/// `_get_config(key)` 从 HTTP API 读取。
class SaveCredentialTool extends SimpleTool {
  /// 项目根目录（含 .config_port 文件）。
  final String projectRoot;

  SaveCredentialTool({required this.projectRoot})
      : super(
          name: 'save_credential',
          description: '将爬虫所需凭证写入平台配置。'
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

            // 读取 ConfigHttpServer 端口
            final portFile = File(p.join(projectRoot, '.config_port'));
            if (!portFile.existsSync()) {
              return '[error: .config_port 文件未找到，ConfigHttpServer 可能未启动]';
            }

            final port = portFile.readAsStringSync().trim();
            debugPrint('[SaveCredential] 保存 $key → Config:${port}');

            try {
              // 通过 HTTP POST 写入配置
              final client = HttpClient();
              try {
                final request = await client.postUrl(
                  Uri.parse('http://127.0.0.1:$port/config/settings'),
                );
                request.headers.contentType =
                    ContentType.json;
                request.write(jsonEncode({'key': key, 'value': value}));
                final response = await request.close();

                if (response.statusCode == 200) {
                  debugPrint('[SaveCredential] ✅ $key 已保存');
                  return '✅ 凭证 "$key" 已保存到项目配置。';
                } else {
                  debugPrint(
                      '[SaveCredential] ⚠ HTTP ${response.statusCode}');
                  return '⚠ 保存凭证 "$key" 失败 (HTTP ${response.statusCode})';
                }
              } finally {
                client.close();
              }
            } catch (e) {
              debugPrint('[SaveCredential] 💥 HTTP 请求异常: $e');
              return '[error: 保存凭证失败: $e]';
            }
          },
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
              '用法：先用 write_file 写 scraper.py，再用 run_terminal_command 执行 `python scraper.py`。'
              '若执行失败，分析错误输出后修改代码并重新执行（最多 5 轮）。',
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

// ═══════ 工具集工厂 ═══════

/// 为爬虫生成器 Agent 构造所有自定义工具。
///
/// 返回的工具有两个需要 UI 层注入的回调：
/// - [resolvePython] — Python 解释器发现函数
/// - [getLogsSummary] — 日志摘要获取函数
/// - [enqueueCommand] — 终端命令入队回调
/// - [getTerminalResult] — 获取终端执行结果的 Future
List<Tool> createScraperTools({
  required String workspaceDir,
  required String projectRoot,
  required Future<String?> Function() resolvePython,
  required String Function() getLogsSummary,
  required void Function(String command) enqueueCommand,
  required Future<String> Function() getTerminalResult,
}) {
  return [
    RunPythonScraperTool(
      workspaceDir: workspaceDir,
      resolvePython: resolvePython,
    ),
    RunTerminalCommandTool(
      enqueueCommand: enqueueCommand,
      getResult: getTerminalResult,
    ),
    SaveCredentialTool(projectRoot: projectRoot),
    GetRequestLogsTool(getLogsSummary: getLogsSummary),
  ];
}

/// 爬虫终端输出面板——左下角 bash 风格终端，支持 AI 驱动命令执行。
///
/// AI 通过 run_terminal_command 工具将命令入队到 workflow，
/// 终端监听 workflow.pendingTerminalCommand 变化后执行命令，
/// 执行完成后将 stdout/stderr 写入 workflow.terminalResult 回传给 AI。
library scraper_terminal;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'scraper_workflow.dart';
import 'scraper_json_validator.dart';

/// 仿 bash 终端输出面板。
///
/// 监听 [workflow.pythonOutput] 和阶段变化，在暗色终端中滚动展示
/// Python 脚本的 stdout/stderr 输出。
///
/// 同时监听 [workflow.hasPendingTerminalCommand]，当 AI 通过
/// run_terminal_command 工具入队命令时自动执行。
class ScraperTerminal extends StatefulWidget {
  final ScraperWorkflow workflow;

  /// 工作目录（Python 脚本所在目录）。
  final String workspaceDir;

  /// Python 可执行文件路径解析函数。
  final Future<String?> Function() resolvePython;

  const ScraperTerminal({
    super.key,
    required this.workflow,
    required this.workspaceDir,
    required this.resolvePython,
  });

  @override
  State<ScraperTerminal> createState() => _ScraperTerminalState();
}

class _ScraperTerminalState extends State<ScraperTerminal> {
  final ScrollController _scrollCtrl = ScrollController();
  String _lastOutput = '';
  final List<_TerminalLine> _lines = [];
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    _addBootLine();
    widget.workflow.addListener(_onWorkflowChanged);
  }

  @override
  void dispose() {
    widget.workflow.removeListener(_onWorkflowChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onWorkflowChanged() {
    if (!mounted) return;
    final phase = widget.workflow.phase;
    final output = widget.workflow.pythonOutput;

    setState(() {
      // 检测阶段变化
      _checkPhaseChange(phase);

      // 检测 Python 输出变化
      if (output != _lastOutput && output.isNotEmpty) {
        if (_lastOutput.isNotEmpty && output.startsWith(_lastOutput)) {
          final delta = output.substring(_lastOutput.length);
          if (delta.isNotEmpty) {
            for (final line in delta.split('\n')) {
              _lines.add(_TerminalLine.stdout(line));
            }
          }
        } else {
          _removeLastExecutionLines();
          _lines.add(_TerminalLine.prompt(
              '\$ python scraper.py  ${_phaseEmoji(phase)}'));
          for (final line in output.split('\n')) {
            _lines.add(_TerminalLine.stdout(line));
          }
        }
        _lastOutput = output;
      }
    });

    _scrollToBottom();

    // 检测 AI 入队的终端命令
    if (!_executing && widget.workflow.hasPendingTerminalCommand) {
      _executing = true;
      final cmd = widget.workflow.consumeTerminalCommand();
      _executeCommand(cmd);
    }
  }

  /// 执行终端命令（AI 通过 run_terminal_command 工具入队）。
  Future<void> _executeCommand(String command) async {
    if (!mounted) return;

    setState(() {
      _lines.add(_TerminalLine.system('── AI 执行终端命令 ──'));
      _lines.add(_TerminalLine.prompt('\$ $command'));
    });
    _scrollToBottom();

    try {
      // 解析命令（支持 "python scraper.py" 和 "pip install xxx" 等）
      final parts = _parseCommand(command);
      if (parts.isEmpty) {
        final errMsg = '[error: 无法解析命令: $command]';
        setState(() => _lines.add(_TerminalLine.error(errMsg)));
        widget.workflow.setTerminalResult(errMsg);
        _executing = false;
        return;
      }

      final executable = parts.first;
      final args = parts.sublist(1);

      // 如果是 python 命令，解析实际 Python 路径
      String? resolvedExe = executable;
      if (executable.toLowerCase() == 'python' || executable.toLowerCase() == 'python3') {
        resolvedExe = await widget.resolvePython();
        if (resolvedExe == null) {
          final errMsg = '[error: 未找到 Python 解释器]';
          setState(() => _lines.add(_TerminalLine.error(errMsg)));
          widget.workflow.setTerminalResult(errMsg);
          _executing = false;
          return;
        }
      }

      debugPrint('[ScraperTerminal] 执行: $resolvedExe ${args.join(" ")}');

      final result = await Process.run(
        resolvedExe!,
        args,
        workingDirectory: widget.workspaceDir,
        runInShell: true,
        environment: Map<String, String>.from(Platform.environment)
          ..['PROJECT_ROOT'] = widget.workspaceDir,
      ).timeout(const Duration(seconds: 60));

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();

      setState(() {
        for (final line in stdout.split('\n')) {
          if (line.isNotEmpty) _lines.add(_TerminalLine.stdout(line));
        }
        if (stderr.isNotEmpty) {
          for (final line in stderr.split('\n')) {
            _lines.add(_TerminalLine.stderr(line));
          }
        }
        if (result.exitCode == 0) {
          _lines.add(_TerminalLine.system('── 命令执行成功 (exitCode=0) ──'));
        } else {
          _lines.add(_TerminalLine.system(
              '── 命令执行失败 (exitCode=${result.exitCode}) ──'));
        }
        _lines.add(_TerminalLine.prompt('\$ '));
      });
      _scrollToBottom();

      // 构造回传给 AI 的结果
      String resultMsg;
      if (result.exitCode == 0) {
        // 对 scraper 运行额外做与平台一致的 JSON 校验：stdout 必须是合法 JSON。
        // 校验失败则把 ❌ 校验日志回传 AI，使其经 _onAgentEvent 进入调试分支自我修正。
        if (isScraperRunCommand(command)) {
          final validation = validateScraperStdout(stdout);
          if (!validation.isValid) {
            setState(() => _lines.add(_TerminalLine.system(
                '── ⚠️ JSON 输出校验未通过（stdout 非合法 JSON）──')));
            resultMsg = buildJsonValidationFailureMessageForTerminal(
              stdout,
              error: validation.error,
            );
          } else {
            resultMsg = buildJsonValidationSuccessMessageForTerminal(stdout, stderr);
          }
        } else {
          resultMsg = '✅ 命令执行成功 (exitCode=0)\n--- STDOUT ---\n$stdout\n${stderr.isNotEmpty ? '--- STDERR ---\n$stderr\n' : ''}';
        }
      } else {
        resultMsg = '❌ 命令执行失败 (exitCode=${result.exitCode})\n--- STDOUT ---\n$stdout\n--- STDERR ---\n$stderr\n请根据错误信息修改代码后重试。';
      }

      widget.workflow.setTerminalResult(resultMsg);

      // 同步更新 pythonOutput 以兼容现有监听
      widget.workflow.setPythonOutput(result.exitCode == 0 ? stdout : '$stdout\n$stderr');
    } on TimeoutException {
      const errMsg = '[error: 命令执行超时 (60s)]';
      setState(() => _lines.add(_TerminalLine.error(errMsg)));
      widget.workflow.setTerminalResult(errMsg);
    } catch (e) {
      final errMsg = '[error: 命令执行异常: $e]';
      setState(() => _lines.add(_TerminalLine.error(errMsg)));
      widget.workflow.setTerminalResult(errMsg);
    } finally {
      _executing = false;
    }
  }

  /// 简单命令解析（支持引号参数）。
  List<String> _parseCommand(String cmd) {
    final parts = <String>[];
    final current = StringBuffer();
    bool inQuote = false;
    String quoteChar = '';

    for (var i = 0; i < cmd.length; i++) {
      final c = cmd[i];
      if (inQuote) {
        if (c == quoteChar) {
          inQuote = false;
        } else {
          current.write(c);
        }
      } else if (c == '"' || c == "'") {
        inQuote = true;
        quoteChar = c;
      } else if (c == ' ') {
        if (current.isNotEmpty) {
          parts.add(current.toString());
          current.clear();
        }
      } else {
        current.write(c);
      }
    }
    if (current.isNotEmpty) parts.add(current.toString());

    return parts;
  }

  void _addBootLine() {
    _lines.add(_TerminalLine.system('Evergreen Scraper Terminal v1.1'));
    _lines.add(_TerminalLine.system('AI 可通过 run_terminal_command 直接执行命令'));
    _lines.add(_TerminalLine.system('等待 AI 生成爬虫并执行...'));
    _lines.add(_TerminalLine.prompt('\$ '));
  }

  void _checkPhaseChange(ScraperPhase phase) {
    switch (phase) {
      case ScraperPhase.analyzing:
        _lines.add(_TerminalLine.system('── AI 开始分析请求日志 ──'));
        break;
      case ScraperPhase.generating:
        _lines.add(_TerminalLine.system('── AI 正在生成 Python 爬虫 ──'));
        break;
      case ScraperPhase.running:
        _lines.add(_TerminalLine.system('── 正在执行爬虫脚本 ──'));
        break;
      case ScraperPhase.debugging:
        _lines.add(_TerminalLine.system(
            '── 调试第 ${widget.workflow.debugCount} 轮 ──'));
        break;
      case ScraperPhase.done:
        _lines.add(_TerminalLine.system('── ✅ 爬虫执行成功 ──'));
        _lines.add(_TerminalLine.prompt('\$ '));
        break;
      case ScraperPhase.failed:
        _lines.add(_TerminalLine.system('── ❌ 爬虫执行失败 ──'));
        _lines.add(_TerminalLine.error(widget.workflow.errorMessage));
        _lines.add(_TerminalLine.prompt('\$ '));
        break;
      default:
        break;
    }
  }

  void _removeLastExecutionLines() {
    _lines.removeWhere((l) => l.kind == _LineKind.stdout);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _phaseEmoji(ScraperPhase p) => switch (p) {
        ScraperPhase.running => '🚀',
        ScraperPhase.debugging => '🔧',
        ScraperPhase.done => '✅',
        ScraperPhase.failed => '❌',
        _ => ''
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117), // GitHub dark terminal bg
        border: Border(
          top: BorderSide(color: Color(0xFF30363D), width: 0.5),
          left: BorderSide(color: Color(0xFF30363D), width: 0.5),
          right: BorderSide(color: Color(0xFF30363D), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          _buildTitleBar(),
          // 终端内容
          Expanded(
            child: _lines.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    itemCount: _lines.length,
                    itemBuilder: (_, i) => _buildLine(_lines[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(
          bottom: BorderSide(color: Color(0xFF30363D), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // macOS 风格红绿灯
          _dot(const Color(0xFFFF5F57)),
          const SizedBox(width: 6),
          _dot(const Color(0xFFFFBD2E)),
          const SizedBox(width: 6),
          _dot(const Color(0xFF28C840)),
          const SizedBox(width: 12),
          const Text(
            'Scraper Terminal — Python Output',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF8B949E),
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          // 输出行数
          Text(
            '${_lines.where((l) => l.kind == _LineKind.stdout).length} lines',
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF484F58),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        '等待 Python 爬虫执行...\n输出将在此终端中实时展示',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF484F58),
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildLine(_TerminalLine line) {
    final color = switch (line.kind) {
      _LineKind.prompt => const Color(0xFF58A6FF), // 蓝色命令提示
      _LineKind.stdout => const Color(0xFFC9D1D9), // 灰白正常输出
      _LineKind.stderr => const Color(0xFFF85149), // 红色错误输出
      _LineKind.system => const Color(0xFF8B949E), // 灰色系统消息
      _LineKind.error => const Color(0xFFF85149), // 红色错误
    };

    final bold = line.kind == _LineKind.prompt || line.kind == _LineKind.system;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        line.text,
        style: TextStyle(
          fontSize: 11,
          height: 1.45,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          fontFamily: 'Consolas',
        ),
      ),
    );
  }
}

// ── 内部模型 ──

enum _LineKind { prompt, stdout, stderr, system, error }

class _TerminalLine {
  final _LineKind kind;
  final String text;

  const _TerminalLine(this.kind, this.text);

  factory _TerminalLine.prompt(String text) =>
      _TerminalLine(_LineKind.prompt, text);
  factory _TerminalLine.stdout(String text) =>
      _TerminalLine(_LineKind.stdout, text);
  factory _TerminalLine.stderr(String text) =>
      _TerminalLine(_LineKind.stderr, text);
  factory _TerminalLine.system(String text) =>
      _TerminalLine(_LineKind.system, text);
  factory _TerminalLine.error(String text) =>
      _TerminalLine(_LineKind.error, text);
}

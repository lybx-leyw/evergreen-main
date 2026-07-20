/// 真终端槽位——基于 xterm + flutter_pty 的真实交互式终端。
///
/// 替代原先的静态只读终端模拟器，现在通过 [Pty.start] 启动真实 shell 进程，
/// [Terminal] + [TerminalView] 提供完整的 ANSI/VT100 终端渲染。
///
/// 平台自动检测：
/// - Windows → cmd.exe
/// - Linux/macOS → bash
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

/// 真终端组件——`terminal` 类型。
class TerminalSlot extends StatefulWidget {
  final ComponentDescriptor config;

  const TerminalSlot({super.key, required this.config});

  @override
  State<TerminalSlot> createState() => _TerminalSlotState();
}

class _TerminalSlotState extends State<TerminalSlot> {
  late final Terminal _terminal;
  Pty? _pty;
  StreamSubscription? _ptySub;
  late final FocusNode _focusNode;

  bool _hasPty = false;
  String _shell = 'cmd.exe';

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _focusNode = FocusNode();

    final cfg = widget.config.config;
    final cwd = cfg['cwd'] as String?;
    _shell = _detectShell(cfg['shell'] as String?);

    _startPty(cwd);

    // 确保终端在构建后获得焦点（解决页面切换时焦点丢失）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  /// 检测 shell：显式指定 > 平台默认。
  String _detectShell(String? explicitShell) {
    if (explicitShell != null && explicitShell.isNotEmpty) return explicitShell;
    if (Platform.isWindows) return r'C:\Windows\System32\cmd.exe';
    return '/bin/bash';
  }

  /// 平台路径规范化：展开 ~ → 用户主目录，检查目录是否存在。
  String? _normalizeCwd(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    // 展开 ~ 符号（跨平台）
    var path = raw;
    if (path.startsWith('~/') || path == '~') {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          (Platform.isWindows
              ? '${Platform.environment['HOMEDRIVE'] ?? 'C:'}${Platform.environment['HOMEPATH'] ?? '\\Users\\${Platform.environment['USERNAME'] ?? 'default'}'}'
              : '/');
      path = path.replaceFirst('~', home);
    }

    final dir = Directory(path);
    if (!dir.existsSync()) {
      debugPrint('[Terminal] ⚠ cwd 不存在: $raw → 将使用当前工作目录');
      return null;
    }
    return dir.absolute.path;
  }

  Future<void> _startPty(String? cwd) async {
    final normalizedCwd = _normalizeCwd(cwd);
    debugPrint('[Terminal] 启动 PTY: shell=$_shell, cwd=$normalizedCwd');
    try {
      _pty = Pty.start(
        _shell,
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
        workingDirectory: normalizedCwd,
      );

      // 终端输入 → PTY 写入（xterm 输出 String，PTY 接收 Uint8List）
      _terminal.onOutput = (data) {
        _pty?.write(utf8.encode(data));
      };

      // PTY 输出 → 终端写入（PTY 输出 Uint8List，终端接收 String）
      _ptySub = _pty!.output.listen((data) {
        _terminal.write(utf8.decode(data));
      });

      // 尺寸同步
      _terminal.onResize = (w, h, pixelW, pixelH) {
        _pty?.resize(h, w);
      };

      // PTY 进程退出时清理
      _pty!.exitCode.then((code) {
        if (mounted) {
          setState(() {
            _hasPty = false;
          });
          debugPrint('[Terminal] 进程退出，退出码: $code');
        }
      });

      if (mounted) {
        setState(() => _hasPty = true);
      }
    } catch (e) {
      debugPrint('[Terminal] PTY 启动失败: $e');
      // 降级——显示静态提示
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ptySub?.cancel();
    _pty?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题栏（shell 信息）
        _buildTitleBar(context),
        // 终端视图
        Expanded(
          child: _hasPty
              ? TerminalView(
                  _terminal,
                  focusNode: _focusNode,
                  autofocus: true,
                  hardwareKeyboardOnly: Platform.isWindows,
                  padding: const EdgeInsets.all(8),
                  theme: const TerminalTheme(
                    cursor: Color(0XAAAEAFAD),
                    selection: Color(0XAAAEAFAD),
                    foreground: Color(0XFFCCCCCC),
                    background: Color(0xFF0D1117),
                    black: Color(0XFF000000),
                    red: Color(0XFFCD3131),
                    green: Color(0XFF0DBC79),
                    yellow: Color(0XFFE5E510),
                    blue: Color(0XFF2472C8),
                    magenta: Color(0XFFBC3FBC),
                    cyan: Color(0XFF11A8CD),
                    white: Color(0XFFE5E5E5),
                    brightBlack: Color(0XFF666666),
                    brightRed: Color(0XFFF14C4C),
                    brightGreen: Color(0XFF23D18B),
                    brightYellow: Color(0XFFF5F543),
                    brightBlue: Color(0XFF3B8EEA),
                    brightMagenta: Color(0XFFD670D6),
                    brightCyan: Color(0XFF29B8DB),
                    brightWhite: Color(0XFFFFFFFF),
                    searchHitBackground: Color(0XFFFFFF2B),
                    searchHitBackgroundCurrent: Color(0XFF31FF26),
                    searchHitForeground: Color(0XFF000000),
                  ),
                  textStyle: const TerminalStyle(
                    fontFamily: 'Cascadia Code, Consolas, monospace',
                    fontSize: 13,
                  ),
                )
              : _buildFallback(context),
        ),
      ],
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final cwd = widget.config.config['cwd'] as String? ?? '~';
    final shellName = _shell.split(Platform.pathSeparator).last;
    final statusColor = _hasPty ? Colors.green : Colors.yellow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF30363D)),
        ),
      ),
      child: Row(
        children: [
          _dot(Colors.red),
          _dot(Colors.amber),
          _dot(statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$cwd — $shellName',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
          ),
          if (!_hasPty)
            Text(
              '无 PTY',
              style: TextStyle(
                  color: Colors.yellow.shade700, fontSize: 10),
            ),
        ],
      ),
    );
  }

  /// 降级静态终端——当 PTY 不可用时。
  Widget _buildFallback(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(12),
      child: const Text(
        r'$ ',
        style: TextStyle(
          color: Color(0xFF58A6FF),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

/// Agent 工具：读取工作区内的文件。
///
/// 所有读取操作限定在工作区根目录内，使用 [PathSandbox] 防止路径遍历逃逸。
///
/// # [ReadFileTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ReadFileTool({workspaceDir, maxSize})` | 工作区路径 + 最大字节数 | `ReadFileTool` | 构造 |
/// | `execute(args)` | `Map` | `Future<String>` | 读取文件内容 |
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ ReadFileTool ═══════

/// 读取工作区内的文件内容。
///
/// 路径相对于 [workspaceDir]，使用 [PathSandbox] 确保不越界。
class ReadFileTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;
  final int _maxSize;

  ReadFileTool({
    required String workspaceDir,
    int maxSize = 100 * 1024,
  })  : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir),
        _maxSize = maxSize;

  @override
  String get name => 'read_file';

  @override
  String get description =>
      '读取工作区内的文件内容。路径相对于工作区根目录，只能访问工作区内的文件。'
      '用于查看源代码、配置文件、日志等文本文件。'
      '二进制文件返回十六进制摘要。'
      '\n\n参数：'
      '- path: 文件相对路径（必填，相对于工作区根目录）\n'
      '- offset: 起始行号（可选，从 1 开始，与 grep 返回的行号一致）\n'
      '- limit: 读取行数（可选，默认全部；分段读取大文件时生效）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '文件相对路径（相对于工作区根目录）。不能使用 .. 逃逸到工作区外。',
          },
          'offset': {
            'type': 'integer',
            'description': '起始行号（从 1 开始，与 grep 的行号一致）。不传从开头读。',
          },
          'limit': {
            'type': 'integer',
            'description': '读取行数。不传读全部。',
          },
        },
        'required': ['path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) return '请提供 path（文件相对路径）。';

    // 沙箱校验
    final safePath = _sandbox.confine(rawPath);
    if (safePath == null) {
      return '[越界拒绝] 路径 "$rawPath" 不在工作区内。文件操作仅限工作区内。';
    }

    try {
      final file = File(safePath);
      if (!file.existsSync()) return '文件不存在：$rawPath';
      if (FileSystemEntity.typeSync(safePath) == FileSystemEntityType.directory) {
        return '$rawPath 是一个目录，请指定具体文件。';
      }

      final size = file.lengthSync();
      if (size == 0) return '## $rawPath\n\n（空文件）';

      // 二进制检测（前若干字节含 NUL 视为二进制）→ 十六进制摘要
      if (await _isBinary(file)) {
        final bytes = await file.readAsBytes();
        return '## $rawPath (${_fmtSize(size)}, 二进制)\n\n'
            '```\n${_hexDump(bytes.take(256).toList())}\n```\n'
            '_（显示前 256 字节的十六进制摘要）_';
      }

      // offset 1-based（与 grep 返回的行号一致）；limit 为读取行数
      final offset = (args['offset'] as int?) ?? 0;
      final limit = (args['limit'] as int?) ?? 0;
      final wantSlice = offset > 0 || limit > 0;

      // 未分段且文件过大 → 提示用 offset/limit（流式切片可读取任意大文件）
      if (!wantSlice && size > _maxSize) {
        return '文件过大（${_fmtSize(size)}），限制 ${_fmtSize(_maxSize)}。'
            '请用 offset/limit 分段读取。';
      }

      final start0 = offset > 0 ? offset - 1 : 0;
      final take = limit > 0 ? limit.clamp(1, 10000) : 0; // 单次切片上限 1 万行
      final selected = await _readSlice(file, start0, take);

      if (wantSlice && selected.isEmpty) {
        return 'offset=$offset 超出文件行数。';
      }

      // 总行数：小文件直接统计；大文件切片读取时省略（避免整文件扫描）
      int? totalLines;
      if (size <= _maxSize) {
        totalLines = (await file.readAsString()).split('\n').length;
      }

      final buf = StringBuffer();
      final ext = rawPath.split('.').last.toLowerCase();
      final totalLabel = totalLines != null ? '$totalLines 行' : '大文件';
      buf.writeln('## $rawPath (${_fmtSize(size)}, $totalLabel)');
      buf.writeln('```$ext');
      for (final l in selected) {
        buf.writeln(l);
      }
      buf.writeln('```');
      if (wantSlice) {
        final startLine = offset > 0 ? offset : 1;
        final endLine = startLine + selected.length - 1;
        buf.writeln('_（显示第 $startLine-$endLine 行'
            '${totalLines != null ? '，共 $totalLines 行' : ''}）_');
      } else if (totalLines != null && totalLines > selected.length) {
        buf.writeln('_（显示全部 $totalLines 行）_');
      }
      return buf.toString();
    } catch (e) {
      return '[读取文件失败: $e]';
    }
  }

  @override
  bool get readOnly => true;

  /// 流式读取文件的指定行范围。
  ///
  /// [start0] 为 0-based 起始行；[take] 为读取行数（0 表示读到文件末尾）。
  /// 通过 [LineSplitter] 逐行迭代，不整文件载入，可读取任意大文件。
  static Future<List<String>> _readSlice(File file, int start0, int take) async {
    final lines = <String>[];
    var idx = 0;
    await for (final line
        in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      if (idx >= start0 && (take == 0 || lines.length < take)) {
        lines.add(line);
      }
      idx++;
      if (take > 0 && lines.length >= take && idx >= start0 + take) break;
    }
    return lines;
  }

  /// 检测文件是否为二进制（前 8KB 含 NUL 字节即判定为二进制）。
  static Future<bool> _isBinary(File file) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, 8192)) {
      bytes.addAll(chunk);
      if (bytes.length >= 8192) break;
    }
    return bytes.contains(0);
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _hexDump(List<int> bytes) {
    final buf = StringBuffer();
    for (var i = 0; i < bytes.length; i += 16) {
      final hex = bytes
          .skip(i)
          .take(16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final ascii = bytes
          .skip(i)
          .take(16)
          .map((b) => b >= 32 && b < 127 ? String.fromCharCode(b) : '.')
          .join();
      buf.writeln('${i.toRadixString(16).padLeft(8, '0')}  $hex${' ' * (48 - hex.length)}  $ascii');
    }
    return buf.toString();
  }
}

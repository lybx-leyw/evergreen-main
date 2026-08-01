/// Agent 工具：读取文件头/尾的 N 行（类 head/tail）。
///
/// 适用于快速查看大日志、数据文件的开头或尾部错误信息，无需整文件读取。
/// 通过 [LineSplitter] 流式读取：head 只读前 N 行即停；tail 用滚动缓冲只保留
/// 末尾 N 行，均不整文件载入，可处理任意大文件。二进制文件会被拒绝（请改用
/// read_file 的十六进制摘要）。所有路径经 [PathSandbox] 限制在工作区内。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ ReadHeadTool ═══════

/// 读取文件开头的 N 行。
class ReadHeadTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;

  ReadHeadTool({required String workspaceDir})
      : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'read_head';

  @override
  String get description =>
      '读取文件开头的 N 行（默认 50）。适合快速查看日志头、配置、数据文件开头。'
      '仅读取文件头部，不加载整个文件，可用于大文件。'
      '\n\n参数：'
      '- path: 文件相对路径（必填）\n'
      '- lines: 读取行数（可选，默认 50，上限 5000）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '文件相对路径（相对于工作区根目录）。',
          },
          'lines': {
            'type': 'integer',
            'description': '读取的行数，默认 50，范围 1-5000。',
          },
        },
        'required': ['path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) =>
      _runHeadTail(_workspaceDir, _sandbox, args, tail: false);
}

// ═══════ ReadTailTool ═══════

/// 读取文件末尾的 N 行。
class ReadTailTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;

  ReadTailTool({required String workspaceDir})
      : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'read_tail';

  @override
  String get description =>
      '读取文件末尾的 N 行（默认 50）。适合查看日志尾部的最新错误信息。'
      '流式读取，仅保留末尾 N 行滚动缓冲，不加载整个文件，可用于大文件。'
      '\n\n参数：'
      '- path: 文件相对路径（必填）\n'
      '- lines: 读取行数（可选，默认 50，上限 5000）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '文件相对路径（相对于工作区根目录）。',
          },
          'lines': {
            'type': 'integer',
            'description': '读取的行数，默认 50，范围 1-5000。',
          },
        },
        'required': ['path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) =>
      _runHeadTail(_workspaceDir, _sandbox, args, tail: true);
}

// ═══════ 共享实现 ═══════

/// head/tail 共享执行逻辑。
Future<String> _runHeadTail(
  String workspaceDir,
  PathSandbox sandbox,
  Map<String, dynamic> args, {
  required bool tail,
}) async {
  final rawPath = args['path']?.toString().trim() ?? '';
  if (rawPath.isEmpty) return '请提供 path（文件相对路径）。';

  final safePath = sandbox.confine(rawPath);
  if (safePath == null) {
    return '[越界拒绝] 路径 "$rawPath" 不在工作区内。文件操作仅限工作区内。';
  }

  final file = File(safePath);
  if (!file.existsSync()) return '文件不存在：$rawPath';
  if (FileSystemEntity.typeSync(safePath) == FileSystemEntityType.directory) {
    return '$rawPath 是一个目录，请指定具体文件。';
  }

  // 二进制文件不支持 head/tail（行概念无意义）
  if (await _isBinary(file)) {
    return '$rawPath 是二进制文件，read_head/read_tail 不支持。'
        '请用 read_file 读取其十六进制摘要。';
  }

  final lines = (args['lines'] as int?) ?? 50;
  final take = lines.clamp(1, 5000);
  final size = file.lengthSync();

  List<String> selected;
  if (tail) {
    // 滚动缓冲：只保留末尾 take 行
    final buf = <String>[];
    await for (final line
        in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      buf.add(line);
      if (buf.length > take) buf.removeAt(0);
    }
    selected = buf;
  } else {
    // head：只读前 take 行即停
    selected = [];
    await for (final line
        in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      selected.add(line);
      if (selected.length >= take) break;
    }
  }

  final ext = rawPath.split('.').last.toLowerCase();
  final verb = tail ? '末尾' : '开头';
  final buf = StringBuffer();
  buf.writeln('## $rawPath (${_fmtSize(size)}, $verb $take 行)');
  buf.writeln('```$ext');
  for (final l in selected) {
    buf.writeln(l);
  }
  buf.writeln('```');
  buf.writeln('_（显示文件$verb ${selected.length} 行）_');
  return buf.toString();
}

/// 检测文件是否为二进制（前 8KB 含 NUL 字节即判定为二进制）。
Future<bool> _isBinary(File file) async {
  final bytes = <int>[];
  await for (final chunk in file.openRead(0, 8192)) {
    bytes.addAll(chunk);
    if (bytes.length >= 8192) break;
  }
  return bytes.contains(0);
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

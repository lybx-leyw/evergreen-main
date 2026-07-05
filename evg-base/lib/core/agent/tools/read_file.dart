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
      '- offset: 起始行号（可选，从 0 开始）\n'
      '- limit: 读取行数（可选，默认全部）';

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
            'description': '起始行号（从 0 开始）。不传从开头读。',
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
      return '[越界拒绝] 路径 "$rawPath" 不在工作区内。只能访问 $_workspaceDir 下的文件。';
    }

    try {
      final file = File(safePath);
      if (!file.existsSync()) return '文件不存在：$rawPath （工作区: $_workspaceDir）';
      if (FileSystemEntity.typeSync(safePath) == FileSystemEntityType.directory) {
        return '$rawPath 是一个目录，请指定具体文件。';
      }

      final size = file.lengthSync();
      if (size > _maxSize) {
        return '文件过大（${_fmtSize(size)}），限制 ${_fmtSize(_maxSize)}。'
            '请用 offset/limit 分段读取。';
      }

      // 尝试按文本读
      try {
        final content = await file.readAsString();
        final lines = content.split('\n');
        final offset = (args['offset'] as int?) ?? 0;
        final limit = (args['limit'] as int?) ?? lines.length;

        if (offset >= lines.length) return 'offset=$offset 超出文件行数（${lines.length} 行）。';

        final end = (offset + limit).clamp(0, lines.length);
        final selected = lines.sublist(offset, end);

        final buf = StringBuffer();
        final ext = rawPath.split('.').last.toLowerCase();
        buf.writeln('## $rawPath (${_fmtSize(size)}, ${lines.length} 行)');
        buf.writeln('```$ext');
        for (var i = 0; i < selected.length; i++) {
          buf.writeln(selected[i]);
        }
        buf.writeln('```');
        if (end < lines.length) {
          buf.writeln('_（显示第 ${offset + 1}-$end 行，共 ${lines.length} 行）_');
        }
        return buf.toString();
      } on FormatException {
        // 二进制文件——显示十六进制摘要
        final bytes = await file.readAsBytes();
        return '## $rawPath (${_fmtSize(size)}, 二进制)\n\n'
            '```\n${_hexDump(bytes.take(256).toList())}\n```\n'
            '_（显示前 256 字节的十六进制摘要）_';
      }
    } catch (e) {
      return '[读取文件失败: $e]';
    }
  }

  @override
  bool get readOnly => true;

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

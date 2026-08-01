/// Agent 工具：查询文件元数据（类 stat / wc -l）。
///
/// 返回文件是否存在、是否目录、字节大小、总行数、是否二进制、扩展名、修改时间，
/// 不读取文件内容本身。行数通过 [LineSplitter] 流式统计（超大文件封顶以避免长时间阻塞）。
/// 适合在读取大文件前先摸清规模（总行数/大小），再决定用 read_file/grep 怎么读。
/// 所有路径经 [PathSandbox] 限制在工作区内。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ FileInfoTool ═══════

/// 查询文件元数据与行数。
class FileInfoTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;

  /// 行数统计上限，超过则标记为大文件行数未知（避免超大文件长时间扫描）。
  final int maxCountLines;

  FileInfoTool({
    required String workspaceDir,
    this.maxCountLines = 10 * 1000 * 1000,
  })  : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'file_info';

  @override
  String get description =>
      '查询文件元数据：是否存在、是否目录、字节大小、总行数、是否二进制、扩展名、修改时间。'
      '不读取文件内容，适合在读取大文件前先摸清规模（总行数/大小）。'
      '\n\n参数：'
      '- path: 文件相对路径（必填）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '文件相对路径（相对于工作区根目录）。',
          },
        },
        'required': ['path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) return '请提供 path（文件相对路径）。';

    final safePath = _sandbox.confine(rawPath);
    if (safePath == null) {
      return '[越界拒绝] 路径 "$rawPath" 不在工作区内。文件操作仅限工作区内。';
    }

    final entityType = FileSystemEntity.typeSync(safePath);
    if (entityType == FileSystemEntityType.notFound) {
      return '文件不存在：$rawPath';
    }
    if (entityType == FileSystemEntityType.directory) {
      final dir = Directory(safePath);
      final count = dir.listSync(recursive: true, followLinks: false).length;
      return '## $rawPath\n\n'
          '- 类型：目录\n'
          '- 条目数（递归）：$count\n'
          '- 修改时间：${_fmtTime(Directory(safePath).statSync().modified)}';
    }

    final file = File(safePath);
    final stat = file.statSync();
    final size = stat.size;
    final isBinary = await _isBinary(file);

    // 流式统计行数（封顶）
    int? lineCount;
    String lineNote = '';
    if (!isBinary) {
      var count = 0;
      var capped = false;
      await for (final _ in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        count++;
        if (count >= maxCountLines) {
          capped = true;
          break;
        }
      }
      if (capped) {
        lineCount = null;
        lineNote = '（> ${_fmtInt(maxCountLines)}，未完整统计）';
      } else {
        lineCount = count;
      }
    }

    final ext = rawPath.contains('.') ? rawPath.split('.').last.toLowerCase() : '(无)';
    final buf = StringBuffer();
    buf.writeln('## $rawPath');
    buf.writeln();
    buf.writeln('- 类型：${isBinary ? '二进制文件' : '文本文件'}');
    buf.writeln('- 扩展名：$ext');
    buf.writeln('- 字节大小：${_fmtSize(size)}（$size B）');
    buf.writeln('- 行数：${lineCount != null ? _fmtInt(lineCount) : '未知'} $lineNote');
    buf.writeln('- 修改时间：${_fmtTime(stat.modified)}');
    return buf.toString();
  }
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

String _fmtInt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );

String _fmtTime(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

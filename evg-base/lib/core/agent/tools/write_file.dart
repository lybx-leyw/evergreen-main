/// Agent 工具：精准文件编辑——覆盖、追加、插入、替换行、删除行、文本替换。
///
/// 所有写操作限定在工作区根目录内，使用 [PathSandbox] 防止路径遍历逃逸。
///
/// # [WriteFileTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `WriteFileTool({workspaceDir})` | 工作区路径 | `WriteFileTool` | 构造 |
/// | `execute(args)` | `Map` | `Future<String>` | 按 action 执行编辑 |
library;

import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ WriteFileTool ═══════

/// 精准文件编辑。
///
/// 六种操作模式覆盖常见编辑需求：
/// - write：覆盖/新建整个文件
/// - append：追加到末尾
/// - insert：在第 N 行前插入
/// - replace_lines：替换第 A 到 B 行
/// - delete_lines：删除第 A 到 B 行
/// - replace_text：查找替换文本（支持正则）
///
/// 所有路径相对于工作区根目录，使用 [PathSandbox] 确保不越界。
class WriteFileTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;

  WriteFileTool({required String workspaceDir})
      : _workspaceDir = workspaceDir,
        _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'write_file';

  @override
  String get description =>
      '精准编辑工作区内的文件。所有路径相对于工作区根目录，不能逃逸到工作区外。'
      '六种操作模式：'
      'write（覆盖/新建整个文件）、'
      'append（追加到文件末尾）、'
      'insert（在第 N 行前插入内容）、'
      'replace_lines（替换第 A 到 B 行）、'
      'delete_lines（删除第 A 到 B 行）、'
      'replace_text（查找替换文本，支持正则）。'
      '\n\n参数：'
      '- action: write / append / insert / replace_lines / delete_lines / replace_text（必填）\n'
      '- path: 文件相对路径（必填，相对于工作区根目录）\n'
      '- content: 内容（write/append/insert/replace_lines 时必填）\n'
      '- start_line: 起始行号 0-indexed（insert/replace_lines/delete_lines 时必填）\n'
      '- end_line: 结束行号 含（replace_lines/delete_lines，默认 = start_line）\n'
      '- old_text: 要替换的文本（replace_text 时必填）\n'
      '- new_text: 替换为（replace_text 时必填）\n'
      '- regex: old_text 是否为正则（replace_text，默认 false）';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '操作类型。',
            'enum': ['write', 'append', 'insert', 'replace_lines', 'delete_lines', 'replace_text'],
          },
          'path': {'type': 'string', 'description': '文件相对路径（相对于工作区根目录）。'},
          'content': {'type': 'string', 'description': '要写入/追加/插入/替换的内容。'},
          'start_line': {'type': 'integer', 'description': '起始行号（0-indexed）。'},
          'end_line': {'type': 'integer', 'description': '结束行号（含）。默认 = start_line。'},
          'old_text': {'type': 'string', 'description': '要替换的文本（replace_text）。'},
          'new_text': {'type': 'string', 'description': '替换为（replace_text）。'},
          'regex': {'type': 'boolean', 'description': 'old_text 是否作为正则（默认 false）。'},
        },
        'required': ['action', 'path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final action = args['action']?.toString() ?? 'write';
    final rawPath = args['path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) return '请提供 path（文件相对路径）。';

    try {
      final fullPath = _sandbox.confine(rawPath);
      if (fullPath == null) {
        return '[越界拒绝] 路径 "$rawPath" 不在工作区内。文件操作仅限工作区内。';
      }

      if (action == 'write') return _doWrite(fullPath, rawPath, args);
      if (action == 'append') return _doAppend(fullPath, rawPath, args);
      if (action == 'insert') return _doInsert(fullPath, rawPath, args);
      if (action == 'replace_lines') return _doReplaceLines(fullPath, rawPath, args);
      if (action == 'delete_lines') return _doDeleteLines(fullPath, rawPath, args);
      if (action == 'replace_text') return _doReplaceText(fullPath, rawPath, args);
      return '未知操作 "$action"。支持：write, append, insert, replace_lines, delete_lines, replace_text。';
    } catch (e) {
      return '[文件编辑失败: $e]';
    }
  }

  // ═══ 操作实现 ═══

  /// write：覆盖/新建整个文件。
  Future<String> _doWrite(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final content = args['content']?.toString() ?? '';
    if (content.isEmpty) return '请提供 content。';
    await _ensureParent(fullPath);
    await File(fullPath).writeAsString(content);
    return _result(displayPath, content);
  }

  /// append：追加到文件末尾。
  Future<String> _doAppend(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final content = args['content']?.toString() ?? '';
    if (content.isEmpty) return '请提供 content。';

    final file = File(fullPath);
    final oldLines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    oldLines.add(content);
    await _ensureParent(fullPath);
    await file.writeAsString(oldLines.join('\n'));
    return '✅ 已追加到 $displayPath（+${content.split('\n').length} 行，共 ${oldLines.length} 行）。';
  }

  /// insert：在第 N 行前插入。0 = 文件开头。
  Future<String> _doInsert(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final content = args['content']?.toString() ?? '';
    final startLine = args['start_line'] as int?;
    if (content.isEmpty) return '请提供 content。';
    if (startLine == null) return '请提供 start_line（插入位置，0-indexed）。';

    final file = File(fullPath);
    final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    if (startLine < 0 || startLine > lines.length) {
      return 'start_line=$startLine 越界（文件共 ${lines.length} 行，允许范围 0-${lines.length}）。';
    }

    final newLines = content.split('\n');
    lines.insertAll(startLine, newLines);
    await _ensureParent(fullPath);
    await file.writeAsString(lines.join('\n'));
    return '✅ 已在第 $startLine 行前插入 ${newLines.length} 行（$displayPath，共 ${lines.length} 行）。';
  }

  /// replace_lines：替换第 A 到 B 行（含）。
  Future<String> _doReplaceLines(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final content = args['content']?.toString() ?? '';
    final startLine = args['start_line'] as int?;
    if (content.isEmpty) return '请提供 content。';
    if (startLine == null) return '请提供 start_line。';
    final endLine = (args['end_line'] as int?) ?? startLine;

    final file = File(fullPath);
    if (!file.existsSync()) return '文件不存在：$displayPath。新建文件请用 action: write。';

    final lines = file.readAsLinesSync();
    if (startLine < 0 || startLine >= lines.length) {
      return 'start_line=$startLine 越界（文件共 ${lines.length} 行，允许范围 0-${lines.length - 1}）。';
    }
    final end = endLine.clamp(startLine, lines.length - 1);

    final newLines = content.split('\n');
    final removed = end - startLine + 1;
    lines.replaceRange(startLine, end + 1, newLines);
    await file.writeAsString(lines.join('\n'));
    return '✅ 已替换第 $startLine-${end} 行（-$removed 行 +${newLines.length} 行，$displayPath，共 ${lines.length} 行）。';
  }

  /// delete_lines：删除第 A 到 B 行（含）。
  Future<String> _doDeleteLines(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final startLine = args['start_line'] as int?;
    if (startLine == null) return '请提供 start_line。';
    final endLine = (args['end_line'] as int?) ?? startLine;

    final file = File(fullPath);
    if (!file.existsSync()) return '文件不存在：$displayPath。';

    final lines = file.readAsLinesSync();
    if (startLine < 0 || startLine >= lines.length) {
      return 'start_line=$startLine 越界（文件共 ${lines.length} 行，允许范围 0-${lines.length - 1}）。';
    }
    final end = endLine.clamp(startLine, lines.length - 1);
    final deleted = lines.sublist(startLine, end + 1);
    lines.removeRange(startLine, end + 1);
    await file.writeAsString(lines.join('\n'));
    return '✅ 已删除第 $startLine-${end} 行（${deleted.length} 行，$displayPath，剩余 ${lines.length} 行）。\n'
        '```\n${deleted.take(5).join('\n')}${deleted.length > 5 ? '\n...' : ''}\n```';
  }

  /// replace_text：查找替换文本。
  Future<String> _doReplaceText(String fullPath, String displayPath, Map<String, dynamic> args) async {
    final oldText = args['old_text']?.toString() ?? '';
    final newText = args['new_text']?.toString() ?? '';
    final useRegex = args['regex'] as bool? ?? false;
    if (oldText.isEmpty) return '请提供 old_text。';
    if (newText.isEmpty) return '请提供 new_text。';

    final file = File(fullPath);
    if (!file.existsSync()) return '文件不存在：$displayPath。';

    final content = file.readAsStringSync();
    int count;
    String result;

    if (useRegex) {
      final re = RegExp(oldText, multiLine: true);
      count = re.allMatches(content).length;
      result = content.replaceAll(re, newText);
    } else {
      count = oldText.allMatches(content).length;
      result = content.replaceAll(oldText, newText);
    }

    if (count == 0) return '未找到匹配的文本（${useRegex ? "正则" : "字面"}: "$oldText"）。';
    await file.writeAsString(result);
    return '✅ 已替换 $count 处（${useRegex ? "正则" : "字面"}，$displayPath）。';
  }

  // ═══ helpers ═══

  Future<void> _ensureParent(String path) async {
    await File(path).parent.create(recursive: true);
  }

  String _result(String path, String content) {
    final lines = content.split('\n').length;
    final size = content.length;
    return '✅ 已写入 $path（$lines 行，${_fmtSize(size)}）。';
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  bool get readOnly => false;
}

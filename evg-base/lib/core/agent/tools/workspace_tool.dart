/// Agent 工具：访问文件工作区——列出/读取工作区文件。
///
/// 使用 [PathSandbox] 防止路径遍历逃逸。
///
/// # [WorkspaceTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `WorkspaceTool(workspaceDir)` | `String` | `WorkspaceTool` | 构造，指定工作区根目录 |
/// | `execute(args)` | `Map` | `Future<String>` | action: list / read |
library;

import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ WorkspaceTool ═══════

/// 访问文件工作区。
///
/// 与 module/ 的 [WorkspaceDescriptor] 对应。
/// 工作区根目录由外部注入（通常指向 `.greenix/workspaces/<moduleId>`）。
/// 所有路径操作使用 [PathSandbox] 确保不越界。
class WorkspaceTool extends Tool {
  final String _workspaceDir;
  final PathSandbox _sandbox;

  WorkspaceTool(this._workspaceDir) : _sandbox = PathSandbox(_workspaceDir);

  @override
  String get name => 'workspace';

  @override
  String get description =>
      '访问文件工作区——用户和 AI 共享的持久文件池。'
      '列出工作区文件，或读取指定文件内容。'
      '所有操作限定在工作区内，无法逃逸到工作区外。'
      '\n\n参数：'
      '- action: list（列出全部文件）/ read（读取指定文件）\n'
      '- path: 文件路径（read 时必填），相对于工作区根目录';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': '操作：list 列出所有文件，read 读取指定文件',
            'enum': ['list', 'read'],
          },
          'path': {
            'type': 'string',
            'description': '文件路径（read 时必填），相对于工作区根目录。不能使用 .. 逃逸。',
          },
        },
        'required': ['action'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final action = args['action']?.toString() ?? 'list';

    try {
      final dir = Directory(_workspaceDir);
      if (!dir.existsSync()) {
        return '工作区目录不存在：$_workspaceDir。'
            '如需使用工作区，模块需在 manifest.json 中声明 `"workspace": {"enabled": true}`。';
      }

      switch (action) {
        case 'list':
          return _list(dir);
        case 'read':
          return _read(args);
        default:
          return '未知操作 "$action"。支持：list, read。';
      }
    } catch (e) {
      return '[工作区访问失败: $e]';
    }
  }

  String _list(Directory dir) {
    final files = dir.listSync(recursive: true).whereType<File>().toList();
    if (files.isEmpty) return '工作区为空（$_workspaceDir）。';

    final buf = StringBuffer();
    buf.writeln('## 文件工作区\n');
    buf.writeln('| 文件 | 大小 | 修改时间 |');
    buf.writeln('|------|------|----------|');

    for (final f in files) {
      final rel = f.path.substring(dir.path.length + 1);
      final size = _fmtSize(f.lengthSync());
      final mtime = f.lastModifiedSync().toIso8601String().substring(0, 19);
      buf.writeln('| $rel | $size | $mtime |');
    }

    buf.writeln('\n_共 ${files.length} 个文件_');
    return buf.toString();
  }

  Future<String> _read(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) return '请提供 path（要读取的文件路径）。';

    // 沙箱校验——防止 ../../../etc/passwd 等路径遍历
    final safePath = _sandbox.confine(rawPath);
    if (safePath == null) {
      return '[越界拒绝] 路径 "$rawPath" 不在工作区内。只能读取 $_workspaceDir 下的文件。';
    }

    final file = File(safePath);
    if (!file.existsSync()) return '文件不存在：$rawPath （工作区: $_workspaceDir）';

    // 限制读取大小（最大 100KB）
    final size = file.lengthSync();
    if (size > 100 * 1024) {
      return '文件过大（${_fmtSize(size)}），最大支持 100KB。'
          '请分段读取或使用其他方式访问。';
    }

    final content = await file.readAsString();
    return '## $rawPath\n\n```\n$content\n```';
  }

  @override
  bool get readOnly => true;

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

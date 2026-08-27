/// Agent 工具：向用户展示工作区指定文件（show_file4u = show file for you）。
///
/// 工具本身只做两件事：路径沙箱校验（防 `../` 越界）+ 文件存在性确认。
/// **真正的文件卡片渲染在渲染层**——renderer 侧（chat_controller_view）在
/// `toolDispatch` 事件分支按 `arguments.file_path` 参数构造文件卡片
/// （文件名 + 预览 + 下载），无需解析本工具的 output 文本。
///
/// # [ShowFile4uTool]
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `ShowFile4uTool({workspaceDir})` | 工作区根路径 | `ShowFile4uTool` | 构造 |
/// | `execute(args)` | `Map` | `Future<String>` | 校验并确认文件存在 |
library;

import 'dart:io';

import '../../utils/path_sandbox.dart';
import '../tool.dart';

// ═══════ ShowFile4uTool ═══════

/// 向用户展示工作区指定文件。
///
/// [workspaceDir] 为工作区根目录（如 `.greenix/workspaces/ai-assistant`），
/// 与 [ReadFileTool] 等文件工具同款 [PathSandbox] 防护。
class ShowFile4uTool extends Tool {
  final PathSandbox _sandbox;

  ShowFile4uTool({required String workspaceDir})
      : _sandbox = PathSandbox(workspaceDir);

  @override
  String get name => 'show_file4u';

  @override
  String get description =>
      '向用户展示工作区内的指定文件（show file for you）。'
      '调用后用户界面会弹出该文件的预览卡片，用户可点击预览或下载。'
      '参数为工作区根目录下的相对路径，只能访问工作区内的文件。'
      '\n\nShow a workspace file to the user. The UI will display a file '
      'card with preview and download actions. The path must be relative '
      'to the workspace root.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': '文件相对路径（相对于工作区根目录）。不能使用 .. 逃逸到工作区外。',
          },
        },
        'required': ['file_path'],
      };

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    final rawPath = args['file_path']?.toString().trim() ?? '';
    if (rawPath.isEmpty) {
      return '[error: 请提供 file_path（工作区相对路径）]';
    }

    // 沙箱校验——防止 ../../../etc/passwd 等路径遍历
    final safePath = _sandbox.confine(rawPath);
    if (safePath == null) {
      return '[error: 路径 "$rawPath" 不在工作区内，仅允许工作区内的相对路径]';
    }

    try {
      // 先判类型再判存在：File.existsSync 对目录返回 false，目录需单独提示。
      final type = FileSystemEntity.typeSync(safePath);
      if (type == FileSystemEntityType.directory) {
        return '[error: $rawPath 是一个目录，请指定具体文件]';
      }
      if (type == FileSystemEntityType.notFound) {
        return '[error: 文件不存在: $rawPath]';
      }
      final file = File(safePath);
      final size = file.lengthSync();
      return '[ok: 已展示工作区文件 $rawPath (${_fmtSize(size)})]';
    } catch (e) {
      return '[error: 展示文件失败: $e]';
    }
  }

  @override
  bool get readOnly => true;

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

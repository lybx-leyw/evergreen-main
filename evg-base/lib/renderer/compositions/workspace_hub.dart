/// 工作区中枢——编辑器 + 文件面板 + Chat 侧栏 三合一组合。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import '../widgets/file_tree.dart';
import '../widgets/models.dart';
import '../shared/editor_view.dart';
import '../shared/chat_controller_view.dart';

/// 工作区中枢——文件树 + 编辑器 + Chat 侧栏。
class WorkspaceHub extends StatefulWidget {
  final ModuleDescriptor descriptor;

  const WorkspaceHub({super.key, required this.descriptor});

  @override
  State<WorkspaceHub> createState() => _WorkspaceHubState();
}

class _WorkspaceHubState extends State<WorkspaceHub> {
  bool _showFiles = true;
  bool _showChat = false;
  final GlobalKey<FileTreeState> _fileTreeKey = GlobalKey<FileTreeState>();
  final GlobalKey<EditorViewState> _editorKey = GlobalKey<EditorViewState>();

  // 当前打开的 WorkspaceFile（含绝对路径用于读取）
  WorkspaceFile? _currentFile;
  String? _currentAbsPath;

  String get _workspaceDir {
    final ws = widget.descriptor.workspace;
    if (ws == null || !ws.enabled) return '';
    return greenixWorkspaceDir(widget.descriptor.id);
  }

  void _openFile(WorkspaceFile file) {
    if (_workspaceDir.isEmpty) return;
    final absPath = '${_workspaceDir.replaceAll('\\', '/')}/${file.path}';
    setState(() {
      _currentFile = file;
      _currentAbsPath = absPath;
    });
    _editorKey.currentState?.openFile(file, absPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左侧：文件树
          if (_showFiles)
            SizedBox(
              width: 240,
              child: _buildFilePanel(),
            ),

          // 中间：编辑器
          Expanded(
            child: EditorView(
              key: _editorKey,
              descriptor: widget.descriptor,
              onFileClosed: () => setState(() {
                _currentFile = null;
                _currentAbsPath = null;
              }),
            ),
          ),

          // 右侧：Chat 侧栏
          if (_showChat)
            SizedBox(
              width: 320,
              child: ChatControllerView(
                descriptor: widget.descriptor,
                embedded: true,
                compact: true,
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.folder_outlined,
                color: _showFiles
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: '文件面板',
              onPressed: () => setState(() => _showFiles = !_showFiles),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(
                Icons.chat_bubble_outline,
                color: _showChat
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'AI 助手',
              onPressed: () => setState(() => _showChat = !_showChat),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePanel() {
    if (_workspaceDir.isEmpty) {
      return const Center(child: Text('工作区未配置'));
    }
    return FileTree(
      key: _fileTreeKey,
      rootDir: _workspaceDir,
      onFileTap: _openFile,
    );
  }
}

/// 工作区中枢——编辑器 + 文件面板 + Chat 侧栏 三合一组合。
///
/// 公开类：[WorkspaceHub]
///
/// | 构造函数 | 参数 | 说明 |
/// |---------|------|------|
/// | `WorkspaceHub({descriptor})` | ModuleDescriptor | 构建三栏工作区 |
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/workspace_panel.dart';
import '../shared/editor_view.dart';
import '../shared/chat_view.dart';

/// 工作区中枢——将编辑器、文件面板、Chat 侧栏组合为统一工作区。
///
/// 对标 IDE 式三栏布局：文件面板 | 编辑器 | Chat。
/// 这是 `compositions/` 层的范例组件——组合多个 `shared/` 视图。
class WorkspaceHub extends StatefulWidget {
  final ModuleDescriptor descriptor;

  const WorkspaceHub({super.key, required this.descriptor});

  @override
  State<WorkspaceHub> createState() => _WorkspaceHubState();
}

class _WorkspaceHubState extends State<WorkspaceHub> {
  bool _showFiles = true;
  bool _showChat = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 左侧：文件面板
          if (_showFiles)
            SizedBox(
              width: 240,
              child: WorkspacePanel(
                workspace: widget.descriptor.workspace,
                files: _sampleFiles,
              ),
            ),

          // 中间：编辑器
          Expanded(
            child: EditorView(descriptor: widget.descriptor),
          ),

          // 右侧：Chat 侧栏
          if (_showChat)
            SizedBox(
              width: 320,
              child: ChatView(descriptor: widget.descriptor),
            ),
        ],
      ),
      // 底部切换栏
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
              onPressed: () =>
                  setState(() => _showFiles = !_showFiles),
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
              onPressed: () =>
                  setState(() => _showChat = !_showChat),
            ),
          ],
        ),
      ),
    );
  }
}

final _sampleFiles = [
  const WorkspaceFile(name: 'main.dart', path: '/src/main.dart'),
  const WorkspaceFile(name: 'README.md', path: '/README.md'),
  const WorkspaceFile(name: 'manifest.json', path: '/module/manifest.json'),
];

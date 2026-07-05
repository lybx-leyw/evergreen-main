/// Editor 视图——代码/文本编辑器 + 文件标签页。
///
/// 公开类：[EditorView]
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../widgets/code_editor.dart';
import '../widgets/empty_state.dart';

/// 代码编辑器范式完整视图。
///
/// 读取 [ModuleDescriptor.input]、[workspace] 配置。
class EditorView extends StatefulWidget {
  final ModuleDescriptor descriptor;

  const EditorView({super.key, required this.descriptor});

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final List<_FileTab> _tabs = [];
  int _activeTab = 0;

  @override
  Widget build(BuildContext context) {
    final workspace = widget.descriptor.workspace;
    final input = widget.descriptor.input;

    return Column(
      children: [
        // 文件标签栏
        _buildTabBar(context),

        // 编辑区域
        Expanded(
          child: _tabs.isNotEmpty
              ? CodeEditor(
                  language: input?.language ?? 'text',
                  // TODO: 绑定文件内容
                )
              : EmptyState(
                  icon: Icons.code,
                  title: '打开文件以开始编辑',
                  subtitle: workspace != null
                      ? '拖入文件或从工作区选择'
                      : '通过菜单打开文件',
                ),
        ),

        // 状态栏
        _buildStatusBar(context),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isActive = index == _activeTab;
          return InkWell(
            onTap: () => setState(() => _activeTab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _closeTab(index),
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Text(
            'UTF-8',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: 16),
          Text(
            '第 1 行，第 1 列',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_activeTab >= _tabs.length) {
        _activeTab = (_tabs.length - 1).clamp(0, _tabs.length);
      }
    });
  }
}

class _FileTab {
  final String name;
  final String path;
  const _FileTab({required this.name, required this.path});
}

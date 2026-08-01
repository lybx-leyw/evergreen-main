/// Editor 视图——代码/文本编辑器 + 文件标签页。
///
/// 支持：多标签页管理、文件内容读取/保存、语法高亮切换。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/code_editor.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/empty_state.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/slot_scale.dart';

/// 代码编辑器范式完整视图。
class EditorView extends StatefulWidget {
  final ModuleDescriptor descriptor;

  /// V2: 组件级配置（language / path / src / content / readonly 等）。
  final ComponentDescriptor? component;

  /// 插件根目录绝对路径，用于解析 manifest 中的相对资源路径。
  final String? pluginsDir;

  /// 文件关闭回调。
  final VoidCallback? onFileClosed;

  const EditorView({
    super.key,
    required this.descriptor,
    this.component,
    this.pluginsDir,
    this.onFileClosed,
  });

  @override
  State<EditorView> createState() => EditorViewState();
}

class EditorViewState extends State<EditorView> {
  final List<_FileTab> _tabs = [];
  int _activeTab = -1;

  @override
  void initState() {
    super.initState();
    _loadInitialFile();
  }

  /// 根据 manifest 配置自动打开初始文件或加载初始内容。
  void _loadInitialFile() {
    final cfg = widget.component?.config ?? const <String, dynamic>{};
    final rawPath = cfg['path'] as String? ?? cfg['src'] as String?;

    if (rawPath != null && rawPath.isNotEmpty) {
      final pluginsDir = widget.pluginsDir ?? resolvePluginsRoot();
      final absPath = resolvePluginAssetPath(rawPath, widget.descriptor.id, pluginsDir);
      if (absPath != null) {
        _openFileByAbsPath(rawPath, absPath);
      }
      return;
    }

    final content = cfg['content'] as String?;
    if (content != null && content.isNotEmpty) {
      _openContentTab(content);
    }
  }

  /// 用相对路径 + 绝对路径打开文件。
  void _openFileByAbsPath(String relPath, String absPath) {
    final name = p.basename(relPath);
    openFile(WorkspaceFile(name: name, path: relPath), absPath);
  }

  /// 用纯内容创建临时标签页（兼容旧版 manifest）。
  void _openContentTab(String content) {
    final language = widget.component?.config['language'] as String? ?? 'text';
    setState(() {
      _tabs.add(_FileTab(
        name: 'untitled.$language',
        absPath: '',
        content: content,
        ext: language,
      ));
      _activeTab = 0;
    });
  }

  /// 打开文件（外部调用）。
  void openFile(WorkspaceFile file, String absPath) {
    // 检查是否已打开
    final existing = _tabs.indexWhere((t) => t.absPath == absPath);
    if (existing >= 0) {
      setState(() => _activeTab = existing);
      return;
    }

    try {
      final f = File(absPath);
      if (!f.existsSync()) return;
      final content = f.readAsStringSync();
      final ext = p.extension(file.name).replaceFirst('.', '');

      setState(() {
        _tabs.add(_FileTab(
          name: file.name,
          absPath: absPath,
          content: content,
          ext: ext.isNotEmpty ? ext : 'text',
        ));
        _activeTab = _tabs.length - 1;
      });
    } catch (_) {
      // 读取失败——静默
    }
  }

  /// 保存当前文件。
  void saveCurrentFile() {
    if (_activeTab < 0 || _activeTab >= _tabs.length) return;
    final tab = _tabs[_activeTab];
    try {
      File(tab.absPath).writeAsStringSync(tab.content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存: ${tab.name}'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 刷新当前文件内容（AI 写入后调用）。
  void refreshCurrentFile() {
    if (_activeTab < 0 || _activeTab >= _tabs.length) return;
    final tab = _tabs[_activeTab];
    try {
      final f = File(tab.absPath);
      if (!f.existsSync()) return;
      setState(() {
        tab.content = f.readAsStringSync();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.descriptor.workspace;
    final language = widget.component?.config['language'] as String? ?? 'text';
    final s = SlotScale.of(context).scale;
    final statusH = 26.0 * s;

    return LayoutBuilder(
      builder: (context, constraints) {
        final editH = constraints.maxHeight - statusH;
        final needsScroll = editH < 120 * s;

        if (needsScroll) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTabBar(context),
                SizedBox(
                  height: editH.clamp(80.0 * s, 500.0 * s),
                  // 去掉 SCSV：re_editor 有内置滚动控制器，外置 SCSV 会
                  // 给子组件无限宽度 → _CodeField 缺显式宽度报错。
                  child: _tabs.isNotEmpty && _activeTab >= 0
                      ? _buildEditor()
                      : Padding(
                          padding: EdgeInsets.all(16 * s),
                          child: EmptyState(
                            icon: Icons.code,
                            title: '打开文件以开始编辑',
                          ),
                        ),
                ),
                _buildStatusBar(context, language),
              ],
            ),
          );
        }

        return Column(
          children: [
            _buildTabBar(context),
            Expanded(
              child: _tabs.isNotEmpty && _activeTab >= 0
                  ? _buildEditor()
                  : EmptyState(
                      icon: Icons.code,
                      title: '打开文件以开始编辑',
                      subtitle: workspace != null
                          ? '从左侧文件树选择文件'
                          : '通过菜单打开文件',
                    ),
            ),
            _buildStatusBar(context, language),
          ],
        );
      },
    );
  }

  Widget _buildEditor() {
    final tab = _tabs[_activeTab];
    final readOnly = widget.component?.config['readonly'] as bool? ?? false;
    return CodeEditor(
      key: ValueKey(tab.absPath),
      language: tab.ext,
      initialContent: tab.content,
      readOnly: readOnly,
      onChanged: (value) => tab.content = value,
    );
  }

  Widget _buildTabBar(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox.shrink();
    final s = SlotScale.of(context).scale;

    return Container(
      height: 36 * s,
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
              padding: EdgeInsets.symmetric(horizontal: 12 * s),
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
                      fontSize: 12 * s,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  SizedBox(width: 4 * s),
                  InkWell(
                    onTap: () => _closeTab(index),
                    child: Icon(Icons.close, size: 14 * s),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, String language) {
    final s = SlotScale.of(context).scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 2 * s),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Text(language,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: (Theme.of(context).textTheme.labelSmall?.fontSize ?? 11) * s)),
          SizedBox(width: 16 * s),
          Text('UTF-8',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontSize: (Theme.of(context).textTheme.labelSmall?.fontSize ?? 11) * s)),
          const Spacer(),
          if (_activeTab >= 0 && _tabs.isNotEmpty)
            InkWell(
              onTap: saveCurrentFile,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8 * s),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save, size: 14 * s,
                        color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 4 * s),
                    Text('保存',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                                fontSize: (Theme.of(context).textTheme.labelSmall?.fontSize ?? 11) * s,
                                color: Theme.of(context).colorScheme.primary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTab = -1;
        widget.onFileClosed?.call();
      } else if (_activeTab >= _tabs.length) {
        _activeTab = (_tabs.length - 1).clamp(0, _tabs.length);
      }
    });
  }
}

class _FileTab {
  final String name;
  final String absPath;
  String content;
  final String ext;

  _FileTab({
    required this.name,
    required this.absPath,
    required this.content,
    required this.ext,
  });
}

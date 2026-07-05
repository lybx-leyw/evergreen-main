/// 文件查看器——工作区点击文件后打开的内置预览/编辑页。
///
/// 支持：
/// - Markdown 渲染（调用 MarkdownRenderer）
/// - 图片预览
/// - 代码/文本（语法高亮 + 编辑模式）
/// - 二进制文件（元信息展示）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:evergreen_base/renderer/widgets/markdown_renderer.dart';
import 'package:evergreen_base/renderer/widgets/models.dart';

/// 文件查看器页面——由 ChatControllerView 通过 Navigator.push 打开。
class FileViewer extends StatefulWidget {
  final WorkspaceFile file;

  const FileViewer({super.key, required this.file});

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  String _content = '';
  bool _loading = true;
  String? _error;
  FileType _type = FileType.unsupported;
  final TextEditingController _editCtrl = TextEditingController();

  WorkspaceFile get _file => widget.file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _type = _detectType(_file.name);
      final f = File(_file.path);
      if (!f.existsSync()) {
        setState(() { _error = '文件不存在'; _loading = false; });
        return;
      }
      if (_type == FileType.image) {
        setState(() => _loading = false);
        return;
      }
      final bytes = await f.readAsBytes();
      if (_type == FileType.binary) {
        _content = '${bytes.length} 字节';
        setState(() => _loading = false);
        return;
      }
      _content = await f.readAsString(encoding: utf8);
      _editCtrl.text = _content;
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  FileType _detectType(String name) {
    final ext = name.split('.').last.toLowerCase();
    // 图片
    if (['jpg','jpeg','png','gif','svg','bmp','webp','ico'].contains(ext)) return FileType.image;
    // Markdown
    if (['md','markdown'].contains(ext)) return FileType.markdown;
    // 代码/文本
    if (['dart','py','js','ts','java','cpp','c','h','go','rs','swift',
         'json','yaml','yml','xml','html','css','scss','less',
         'txt','csv','log','sh','bat','ps1','toml','ini','cfg','props',
         'sql','r','m','kt','rb','php','pl','lua'].contains(ext)) return FileType.text;
    // PDF / Office (不能直接渲染，显示元信息)
    if (['pdf','docx','pptx','xlsx'].contains(ext)) return FileType.binary;
    // 默认尝试当文本
    return FileType.text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_file.name, style: theme.textTheme.titleSmall),
        actions: [
          // 复制内容
          if (_type == FileType.text || _type == FileType.markdown)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制内容',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
            ),
          // 编辑/查看切换（文本文件）
          if (_type == FileType.text)
            _EditToggleButton(
              onSave: _saveEdit,
              onToggle: (editing) {
                if (!editing) {
                  _editCtrl.text = _content;
                }
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error.withValues(alpha: 0.6)),
                    const SizedBox(height: 12),
                    Text(_error!, style: theme.textTheme.bodyMedium),
                  ],
                ))
              : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_type) {
      case FileType.markdown:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: MarkdownRenderer(text: _content, useCard: false),
          ),
        );
      case FileType.image:
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(_file.path),
              fit: BoxFit.contain,
              errorBuilder: (_, e, __) => Center(
                child: Text('图片加载失败: $e', style: theme.textTheme.bodyMedium),
              ),
            ),
          ),
        );
      case FileType.text:
        return _TextCodeView(
          content: _content,
          fileName: _file.name,
          editCtrl: _editCtrl,
          onSave: _saveEdit,
        );
      case FileType.unsupported:
      case FileType.binary:
        return _BinaryInfoView(file: _file, theme: theme);
    }
  }

  Future<void> _saveEdit() async {
    try {
      await File(_file.path).writeAsString(_editCtrl.text);
      setState(() => _content = _editCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }
}

enum FileType { text, markdown, image, binary, unsupported }

// ═══════ _EditToggleButton ═══════

class _EditToggleButton extends StatefulWidget {
  final Future<void> Function() onSave;
  final void Function(bool editing) onToggle;

  const _EditToggleButton({required this.onSave, required this.onToggle});

  @override
  State<_EditToggleButton> createState() => _EditToggleButtonState();
}

class _EditToggleButtonState extends State<_EditToggleButton> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '保存',
            onPressed: () async {
              await widget.onSave();
              setState(() => _editing = false);
              widget.onToggle(false);
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_off),
            tooltip: '取消编辑',
            onPressed: () {
              setState(() => _editing = false);
              widget.onToggle(false);
            },
          ),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.edit),
      tooltip: '编辑',
      onPressed: () {
        setState(() => _editing = true);
        widget.onToggle(true);
      },
    );
  }
}

// ═══════ _TextCodeView ═══════

class _TextCodeView extends StatefulWidget {
  final String content;
  final String fileName;
  final TextEditingController editCtrl;
  final Future<void> Function() onSave;

  const _TextCodeView({
    required this.content,
    required this.fileName,
    required this.editCtrl,
    required this.onSave,
  });

  @override
  State<_TextCodeView> createState() => _TextCodeViewState();
}

class _TextCodeViewState extends State<_TextCodeView> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: _editing ? null : (details) {
        // 不移除——保留手势区域防止冲突
      },
      child: _editing ? _buildEditor() : _buildViewer(),
    );
  }

  Widget _buildViewer() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          widget.content,
          style: TextStyle(
            fontFamily: 'Consolas, Courier New, monospace',
            fontSize: 13,
            height: 1.5,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 编辑工具栏
        Container(
          height: 36,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('编辑模式', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () async {
                  await widget.onSave();
                  setState(() => _editing = false);
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.close, size: 16),
                label: const Text('取消'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () {
                  widget.editCtrl.text = widget.content;
                  setState(() => _editing = false);
                },
              ),
            ],
          ),
        ),
        // 编辑器正文
        Expanded(
          child: TextField(
            controller: widget.editCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontFamily: 'Consolas, Courier New, monospace',
              fontSize: 13,
              height: 1.5,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              hintText: '编辑 ${widget.fileName}…',
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontFamily: 'Consolas, Courier New, monospace',
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════ _BinaryInfoView ═══════

class _BinaryInfoView extends StatelessWidget {
  final WorkspaceFile file;
  final ThemeData theme;

  const _BinaryInfoView({required this.file, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _fileIcon(),
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(file.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            _formatSize(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '此文件格式暂不支持预览\n请使用外部应用打开',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon() {
    final ext = file.name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf,
      'pptx' || 'ppt' => Icons.slideshow,
      'docx' || 'doc' => Icons.description,
      'xlsx' || 'xls' => Icons.table_chart,
      'zip' || 'tar' || 'gz' || 'rar' => Icons.archive,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatSize() {
    final bytes = file.sizeBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

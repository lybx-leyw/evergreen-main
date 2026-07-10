/// 文件查看器——工作区点击文件后打开的内置预览/编辑页。
///
/// 使用 re_editor CodeEditor 提供即开即编的代码/文本编辑体验，
/// 替换了旧的 SelectableText + TextField 两段式方案。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/code_editor.dart';

/// 文件查看器页面——由 ChatControllerView 通过 Navigator.push 打开。
class FileViewer extends StatefulWidget {
  final WorkspaceFile file;

  const FileViewer({super.key, required this.file});

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  String _content = '';
  String _editContent = '';
  bool _loading = true;
  String? _error;
  FileType _type = FileType.unsupported;

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
      _editContent = _content;
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  static FileType _detectType(String name) {
    final ext = name.split('.').last.toLowerCase();
    // 图片
    if (['jpg','jpeg','png','gif','svg','bmp','webp','ico'].contains(ext)) return FileType.image;
    // 代码/文本（含 markdown——不再区分为单独类型）
    if (['dart','py','js','ts','java','cpp','c','h','go','rs','swift',
         'json','yaml','yml','xml','html','css','scss','less',
         'txt','csv','log','sh','bat','ps1','toml','ini','cfg','props',
         'sql','r','m','kt','rb','php','pl','lua',
         'md','markdown'].contains(ext)) return FileType.text;
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
          if (_type == FileType.text)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: '复制内容',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editContent));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
            ),
          // 保存
          if (_type == FileType.text)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存',
              onPressed: _saveEdit,
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
      case FileType.text:
        final ext = _file.name.split('.').last;
        return CodeEditor(
          language: ext,
          initialContent: _content,
          onChanged: (v) => _editContent = v,
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
      case FileType.binary:
      case FileType.unsupported:
        return _BinaryInfoView(file: _file, theme: theme);
    }
  }

  Future<void> _saveEdit() async {
    try {
      await File(_file.path).writeAsString(_editContent);
      setState(() => _content = _editContent);
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
    super.dispose();
  }
}

enum FileType { text, image, binary, unsupported }

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

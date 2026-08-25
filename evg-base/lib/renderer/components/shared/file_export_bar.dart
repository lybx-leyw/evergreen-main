/// 文件导出入口通用组件（renderer 共享层，T8b）。
///
/// 给定文件条目列表（`List<FileEntry>`）+ 凭据 headers 注入回调 + core
/// [DataFileService]，提供「导出」按钮：点击 → 选目录（[pickExportDirectory]）→
/// 批量下载（[exportFileEntries]）→ SnackBar 展示结果（成功路径数 / 失败原因）。
///
/// 供 module 播放/查看页复用，**不绑定特定模块**（zju 播放/下载页迁移属 T9 之后
/// 评估，本任务不接 zju_modle）。
library;

import 'package:flutter/material.dart';

import 'package:evergreen_base/core/data/file_entries.dart';
import 'package:evergreen_base/core/services/data_file_service.dart';

import 'file_export.dart';

/// 凭据 headers 注入回调：返回本次下载要携带的请求头（如 Cookie/Referer/UA）。
/// 返回 `null` 表示无凭据（匿名下载）。由调用方（T2 会话中心）提供，本组件不实作。
typedef ExportHeadersProvider = Map<String, String>? Function();

/// 导出结果摘要（供 [FileExportButton.onDone] / [FileExportBar.onDone] 消费）。
class FileExportSummary {
  /// 成功落盘的文件数。
  final int successCount;

  /// 失败文件数。
  final int failureCount;

  /// 目标目录（用户选定，成功时非空）。
  final String? targetDir;

  /// 成功落盘的文件绝对路径列表。
  final List<String> savedPaths;

  /// 失败原因（中文，[AppError.userMessage]，与成功/失败逐项对齐）。
  final List<String> failures;

  const FileExportSummary({
    required this.successCount,
    required this.failureCount,
    this.targetDir,
    this.savedPaths = const [],
    this.failures = const [],
  });
}

/// 通用「导出」按钮：选目录 → 批量下载 → SnackBar 结果。
class FileExportButton extends StatefulWidget {
  /// 要导出的文件条目列表（core `extractFileEntries` 结果）。
  final List<FileEntry> entries;

  /// core 下载服务实例（由调用方注入；可带 `sandboxRoot` 限制落盘边界）。
  final DataFileService service;

  /// 凭据 headers 注入回调（可选；匿名下载传 null / 不传）。
  final ExportHeadersProvider? headersProvider;

  /// 导出完成回调（可选）。
  final ValueChanged<FileExportSummary>? onDone;

  /// 按钮文案（默认「导出」）。
  final String label;

  /// 是否可用（条目为空时由调用方置 false）。
  final bool enabled;

  /// 按钮样式（可选）。
  final ButtonStyle? style;

  const FileExportButton({
    super.key,
    required this.entries,
    required this.service,
    this.headersProvider,
    this.onDone,
    this.label = '导出',
    this.enabled = true,
    this.style,
  });

  @override
  State<FileExportButton> createState() => _FileExportButtonState();
}

class _FileExportButtonState extends State<FileExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    if (widget.entries.isEmpty) {
      _snack('没有可导出的文件');
      return;
    }
    setState(() => _busy = true);
    try {
      final dir = await pickExportDirectory();
      if (!mounted) return;
      if (dir == null) {
        _snack('已取消导出');
        return;
      }
      final headers = widget.headersProvider?.call();
      final results = await exportFileEntries(
        entries: widget.entries,
        service: widget.service,
        targetDir: dir,
        headers: headers,
      );
      if (!mounted) return;
      final saved = <String>[];
      final failures = <String>[];
      for (final r in results) {
        r.fold(
          (path) => saved.add(path),
          (err) => failures.add(err.userMessage),
        );
      }
      final summary = FileExportSummary(
        successCount: saved.length,
        failureCount: failures.length,
        targetDir: dir,
        savedPaths: saved,
        failures: failures,
      );
      _snack(_summarize(summary));
      widget.onDone?.call(summary);
    } catch (e) {
      if (mounted) _snack('导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _summarize(FileExportSummary s) {
    if (s.failureCount == 0) {
      return '已导出 ${s.successCount} 个文件到 ${s.targetDir ?? ''}';
    }
    if (s.successCount == 0) {
      return '导出失败：${s.failures.first}';
    }
    return '已导出 ${s.successCount} 个文件，失败 ${s.failureCount} 个'
        '（${s.failures.first}…）';
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: widget.enabled && !_busy ? _export : null,
      style: widget.style,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download),
      label: Text(_busy ? '导出中…' : widget.label),
    );
  }
}

/// 导出栏：文件条目概览 + [FileExportButton]，供 module 页底部/顶部复用。
///
/// 与 [FileExportButton] 同参数，额外展示「N 个可导出文件」概览文案。
class FileExportBar extends StatelessWidget {
  final List<FileEntry> entries;
  final DataFileService service;
  final ExportHeadersProvider? headersProvider;
  final ValueChanged<FileExportSummary>? onDone;
  final String label;

  const FileExportBar({
    super.key,
    required this.entries,
    required this.service,
    this.headersProvider,
    this.onDone,
    this.label = '导出',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${entries.length} 个可导出文件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            FileExportButton(
              entries: entries,
              service: service,
              headersProvider: headersProvider,
              onDone: onDone,
              label: label,
            ),
          ],
        ),
      ),
    );
  }
}

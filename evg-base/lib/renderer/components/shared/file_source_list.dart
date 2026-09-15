/// 文件型数据源列表 —— **选择性下载** UI（方案 P2）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §6 P2。
///
/// 与既有 `FileExportBar`（"一键导出到用户自选目录"）**语义不同**，故独立新建：
/// | 组件 | 语义 | 落盘目标 |
/// | --- | --- | --- |
/// | `FileExportBar` | 把业务数据的**附件**导出到用户目录 | 用户自选目录 |
/// | **本组件** | 文件型数据源的**主体文件**：选择性下载 + 打开 | 应用缓存（`targetDir`） |
///
/// # 行内行为（按 `FileSourceEntry.isCached` 分叉）
/// | 形态 | UI | 交互 |
/// | --- | --- | --- |
/// | 已落盘（`path`） | 「已缓存 · 12.3 MB」 | 点击 → [onOpen]（零下载） |
/// | 待下载（`url`） | 勾选框 + 名称/大小 | 勾选 → 「下载选中」 |
///
/// # 下载
/// - 走 [DataFileService]（**已流式落盘 + 进度回调**，见 P0）；
/// - **串行**执行（与 `downloadFiles` 同理由：确定性 + 避免并发磁盘竞争）；
/// - 目标文件名经 [sanitizeFileName] 净化（防路径穿越）；
/// - 已完成项**不重复下载**（配合 F1 后端缓存，二次进入列表即刻命中）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:evergreen_base/core/data/file_source_entries.dart';
import 'package:evergreen_base/core/services/data_file_service.dart';

import 'file_export_names.dart';

/// 单项状态。
enum _ItemState { idle, downloading, done, failed }

/// 文件型数据源列表（选择性下载）。
class FileSourceList extends StatefulWidget {
  /// 待展示条目（来自 [parseFileSourceEntries]）。
  final List<FileSourceEntry> entries;

  /// 下载服务（调用方宜带 `sandboxRoot: targetDir` 限制落盘边界）。
  final DataFileService service;

  /// 下载目标目录（应用缓存；已落盘项的 [FileSourceEntry.path] 不受此影响）。
  final String targetDir;

  /// 凭据头（可选；如 Cookie/Referer）。
  final Map<String, String>? headers;

  /// 单项下载超时（大文件应显式传更长值）。
  final Duration timeout;

  /// 点击已缓存项的回调（通常是「播放 / 打开」）。
  final void Function(FileSourceEntry entry)? onOpen;

  /// 列表为空时的提示。
  final String emptyHint;

  const FileSourceList({
    super.key,
    required this.entries,
    required this.service,
    required this.targetDir,
    this.headers,
    this.timeout = const Duration(minutes: 10),
    this.onOpen,
    this.emptyHint = '暂无可下载文件',
  });

  @override
  State<FileSourceList> createState() => _FileSourceListState();
}

class _FileSourceListState extends State<FileSourceList> {
  /// 已勾选的**待下载项**索引。
  final Set<int> _selected = {};

  final Map<int, _ItemState> _state = {};
  final Map<int, int> _received = {};
  final Map<int, int?> _total = {};
  final Map<int, String> _error = {};

  /// 下载完成后落盘路径（供 onOpen 使用）。
  final Map<int, String> _savedPath = {};

  bool _busy = false;

  /// 可勾选项（仅 url 形态）。
  List<int> get _selectable => [
        for (var i = 0; i < widget.entries.length; i++)
          if (!widget.entries[i].isCached) i
      ];

  @override
  void initState() {
    super.initState();
    for (final i in _selectable) {
      _state[i] = _ItemState.idle;
    }
  }

  void _toggle(int i) {
    if (_busy) return;
    setState(() {
      if (_selected.contains(i)) {
        _selected.remove(i);
      } else {
        _selected.add(i);
      }
    });
  }

  void _toggleAll() {
    if (_busy) return;
    setState(() {
      if (_selected.length == _selectable.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_selectable.where(
              (i) => _state[i] != _ItemState.done));
      }
    });
  }

  /// 串行下载 [indices] 中的项。
  Future<void> _download(Iterable<int> indices) async {
    final todo = indices
        .where((i) => _state[i] != _ItemState.done)
        .toList(growable: false);
    if (todo.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      for (final i in todo) {
        _state[i] = _ItemState.downloading;
        _received[i] = 0;
        _total[i] = null;
        _error.remove(i);
      }
    });

    for (final i in todo) {
      final entry = widget.entries[i];
      final url = entry.url;
      if (url == null || url.isEmpty) continue;

      final safe = sanitizeFileName(entry.name);
      final target = p.join(widget.targetDir, safe);

      final r = await widget.service.downloadFile(
        url: url,
        targetPath: target,
        headers: widget.headers,
        timeout: widget.timeout,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received[i] = received;
            _total[i] = total;
          });
        },
        // 已完成项不重复下载：目标已存在时由服务层覆盖写；
        // 后端 F1（内容寻址缓存）保证真正不重下。
      );

      if (!mounted) return;
      setState(() {
        if (r.isOk) {
          _state[i] = _ItemState.done;
          _savedPath[i] = r.fold((v) => v, (_) => target);
          _selected.remove(i);
        } else {
          _state[i] = _ItemState.failed;
          _error[i] = r.fold((_) => '', (e) => '$e');
        }
      });
    }

    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(widget.emptyHint, style: theme.textTheme.bodySmall),
      );
    }

    final pending = _selectable.where((i) => _state[i] != _ItemState.done);
    final allSelected =
        _selectable.isNotEmpty && _selected.length == pending.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(theme, pending.length, allSelected),
        const Divider(height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.entries.length,
            itemBuilder: (ctx, i) => _row(theme, i),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ThemeData theme, int pendingCount, bool allSelected) {
    final n = _selected.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (pendingCount > 0)
            TextButton(
              onPressed: _busy ? null : _toggleAll,
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
          const SizedBox(width: 4),
          Text('${widget.entries.length} 个文件',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          if (n > 0)
            FilledButton.icon(
              onPressed: _busy ? null : () => _download(_selected.toList()),
              icon: const Icon(Icons.download, size: 18),
              label: Text('下载选中 ($n)'),
            ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, int i) {
    final e = widget.entries[i];
    final st = _state[i] ?? _ItemState.idle;

    if (e.isCached) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.check_circle_outline, size: 20),
        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('已缓存 · ${e.sizeLabel}',
            style: theme.textTheme.bodySmall),
        trailing: widget.onOpen == null
            ? null
            : IconButton(
                icon: const Icon(Icons.play_arrow, size: 20),
                tooltip: '打开',
                onPressed: () => widget.onOpen!(e),
              ),
      );
    }

    final received = _received[i] ?? 0;
    final total = _total[i];
    final ratio = (total != null && total > 0)
        ? (received / total).clamp(0.0, 1.0)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          dense: true,
          value: st == _ItemState.done || _selected.contains(i),
          onChanged: st == _ItemState.done || _busy ? null : (_) => _toggle(i),
          title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            switch (st) {
              _ItemState.downloading => ratio == null
                  ? '下载中 · ${_fmtBytes(received)}'
                  : '下载中 · ${(ratio * 100).toStringAsFixed(0)}%',
              _ItemState.done => '已下载',
              _ItemState.failed => '失败：${_error[i] ?? '未知错误'}',
              _ItemState.idle => '待下载 · ${e.sizeLabel}',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: st == _ItemState.failed ? theme.colorScheme.error : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (st == _ItemState.downloading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(value: ratio),
          ),
      ],
    );
  }

  static String _fmtBytes(int b) {
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }
}

/// 左侧数据面板 —— 数据中枢数据源列表 + 选中源缓存格式预览。
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/data_preview_service.dart';

class DataPanel extends StatefulWidget {
  final DataPreviewService dataService;
  final ValueChanged<String>? onSelectSource;

  /// 当前画布绑定的数据源名（null = 未绑定）。
  ///
  /// 由视图层从画布 meta 注入；切换画布时 didUpdateWidget 自动
  /// 恢复选中态并拉取预览，保证「绑定随板走、切板即恢复」。
  final String? selectedSource;

  const DataPanel({
    super.key,
    required this.dataService,
    this.onSelectSource,
    this.selectedSource,
  });

  @override
  State<DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends State<DataPanel> {
  List<DataSourcePreview> _sources = [];
  Map<String, dynamic> _selected = {};
  String? _selectedName;
  bool _loadingPreview = false;

  /// 正在行内刷新的数据源名集合（B3）。
  final Set<String> _refreshing = {};
  /// 连通性测试进行中（B3）。
  bool _testingConn = false;

  /// 记录上次传入的绑定源（didUpdateWidget 对比用）。
  String? _oldBound;

  @override
  void initState() {
    super.initState();
    _oldBound = widget.selectedSource;
    _refresh();
    // 恢复画布绑定源（首次进入即有绑定态）
    final bound = widget.selectedSource;
    if (bound != null && bound.isNotEmpty) {
      _selectedName = bound;
      _loadPreviewSilently(bound);
    }
  }

  @override
  void didUpdateWidget(covariant DataPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切画布：绑定源变化 → 恢复选中态并拉取预览（不串台）
    final bound = widget.selectedSource;
    if (bound != _oldBound) {
      _oldBound = bound;
      if (bound != null && bound.isNotEmpty) {
        setState(() => _selectedName = bound);
        _loadPreviewSilently(bound);
      } else {
        setState(() => _selectedName = null);
      }
    }
  }

  void _refresh() {
    setState(() => _sources = widget.dataService.listSources());
  }

  Future<void> _loadPreview(String name) async {
    setState(() {
      _selectedName = name;
      _loadingPreview = true;
    });
    final data = await widget.dataService.fetchPreview(name);
    setState(() {
      _selected[name] = data;
      _loadingPreview = false;
    });
    widget.onSelectSource?.call(name);
  }

  /// 静默恢复绑定源预览：只选中 + 拉取缓存，不回调 onSelectSource
  /// （切画布自动恢复场景，避免再次触发占位符替换/绑定写回）。
  Future<void> _loadPreviewSilently(String name) async {
    setState(() => _loadingPreview = true);
    final data = await widget.dataService.fetchPreview(name);
    if (!mounted) return;
    setState(() {
      _selected[name] = data;
      _loadingPreview = false;
    });
  }

  /// 行内刷新数据源（B3）：走 DataHttpServer，成功后刷新列表 + 预览。
  Future<void> _refreshSource(String name) async {
    setState(() => _refreshing.add(name));
    final data = await widget.dataService.refresh(name);
    if (!mounted) return;
    setState(() {
      _refreshing.remove(name);
      if (data != null) _selected[name] = data;
    });
    _refresh(); // 状态（freshness/connected）可能变化
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(data != null ? '已刷新: $name' : '刷新失败: $name'),
      duration: const Duration(seconds: 1),
      backgroundColor: data != null ? null : Colors.red,
    ));
  }

  /// 连通性测试（B3）：全部数据源走 DataHttpServer 探测，弹结果对话框。
  Future<void> _testConnectivity() async {
    setState(() => _testingConn = true);
    final result = await widget.dataService.testConnectivity();
    if (!mounted) return;
    setState(() => _testingConn = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('数据源连通性测试', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 360,
          child: result == null
              ? const Text('Data 服务不可用（.data_port 缺失）\n'
                  '请确认 core DataHttpServer 已启动。',
                  style: TextStyle(fontSize: 12))
              : SingleChildScrollView(
                  child: _buildConnResult(result),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildConnResult(Map<String, dynamic> result) {
    final theme = Theme.of(context);
    if (result.containsKey('error')) {
      return Text('测试失败: ${result['error']}',
          style: TextStyle(fontSize: 12, color: Colors.red));
    }
    final results = result['results'];
    if (results is! List || results.isEmpty) {
      return const Text('无数据源', style: TextStyle(fontSize: 12));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in results)
          if (r is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    (r['connected'] == true) ? Icons.check_circle : Icons.error_outline,
                    size: 14,
                    color: (r['connected'] == true)
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${r['name'] ?? '?'}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r['displayName'] ?? ''}',
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  String _formatJson(dynamic d) {
    if (d == null) return '(null)';
    try {
      if (d is List && d.length > 3) {
        return const JsonEncoder.withIndent('  ')
                .convert(d.sublist(0, 3)) +
            '\n... (共 ${d.length} 条)';
      }
      return const JsonEncoder.withIndent('  ').convert(d);
    } catch (_) {
      return d.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: _sources.length,
            itemBuilder: (ctx, i) {
              final s = _sources[i];
              final isSelected = _selectedName == s.name;
              return ListTile(
                dense: true,
                selected: isSelected,
                title: Text(s.displayName,
                    style: const TextStyle(fontSize: 12)),
                subtitle: Text(s.freshnessLabel,
                    style: TextStyle(
                        fontSize: 10,
                        color: s.connected ? Colors.green : Colors.red)),
                onTap: () => _loadPreview(s.name),
                // 行内刷新（B3）
                trailing: _refreshing.contains(s.name)
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5))
                    : IconButton(
                        icon: const Icon(Icons.refresh, size: 13),
                        tooltip: '刷新 ${s.name}',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _refreshSource(s.name),
                      ),
              );
            },
          ),
        ),
        if (_selectedName != null) _buildPreview(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.storage, size: 14),
          const SizedBox(width: 4),
          const Text('数据中枢', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const Spacer(),
          // 连通性测试（B3）
          IconButton(
            icon: _testingConn
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                : const Icon(Icons.network_check, size: 14),
            tooltip: '测试全部数据源连通性',
            onPressed: _testingConn ? null : _testConnectivity,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14),
            onPressed: _refresh,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text('📋 $_selectedName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          Expanded(
            child: _loadingPreview
                ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(6),
                    child: SelectableText(
                      _formatJson(_selected[_selectedName]),
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

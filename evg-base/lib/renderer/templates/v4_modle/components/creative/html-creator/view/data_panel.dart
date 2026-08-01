/// 左侧数据面板 —— 数据中枢数据源列表 + 选中源缓存格式预览。
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/services/data_preview_service.dart';

class DataPanel extends StatefulWidget {
  final DataPreviewService dataService;
  final ValueChanged<String>? onSelectSource;

  const DataPanel({super.key, required this.dataService, this.onSelectSource});

  @override
  State<DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends State<DataPanel> {
  List<DataSourcePreview> _sources = [];
  Map<String, dynamic> _selected = {};
  String? _selectedName;
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
    final theme = Theme.of(context);
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

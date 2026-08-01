/// 中间编辑器面板 —— 多标签 HTML/CSS/JS 编辑。
library;

import 'package:flutter/material.dart';

class EditorPanel extends StatefulWidget {
  final TextEditingController htmlController;
  final TextEditingController cssController;
  final TextEditingController jsController;
  final VoidCallback? onChanged;

  const EditorPanel({
    super.key,
    required this.htmlController,
    required this.cssController,
    required this.jsController,
    this.onChanged,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _activeTab = 'html';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _activeTab = ['html', 'css', 'js'][_tabController.index];
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.code, size: 14),
              const SizedBox(width: 4),
              const Text('编辑器', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 16),
              _tab('html', 'HTML'),
              _tab('css', 'CSS'),
              _tab('js', 'JS'),
              const Spacer(),
              Flexible(
                child: Text(
                  '行 ${_currentLineCount()}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEditor(widget.htmlController, 'html'),
              _buildEditor(widget.cssController, 'css'),
              _buildEditor(widget.jsController, 'javascript'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(String id, String label) {
    final active = _activeTab == id;
    return GestureDetector(
      onTap: () => _tabController.animateTo(['html','css','js'].indexOf(id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: active ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildEditor(TextEditingController ctrl, String language) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: ctrl,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4),
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: Theme.of(context).dividerColor),
          ),
          contentPadding: const EdgeInsets.all(8),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
        onChanged: (_) => widget.onChanged?.call(),
      ),
    );
  }

  int _currentLineCount() {
    return switch (_activeTab) {
      'html' => widget.htmlController.text.split('\n').length,
      'css'  => widget.cssController.text.split('\n').length,
      'js'   => widget.jsController.text.split('\n').length,
      _      => 0,
    };
  }
}

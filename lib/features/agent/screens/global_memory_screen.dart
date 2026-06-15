import 'package:flutter/material.dart';
import '../../../../core/agent/memory/memory.dart' show Memory, MemoryStore, MemoryType;

/// 全局记忆管理全屏页——查看/添加/修改/删除。
class GlobalMemoryScreen extends StatefulWidget {
  const GlobalMemoryScreen({super.key});

  @override
  State<GlobalMemoryScreen> createState() => _GlobalMemoryScreenState();
}

class _GlobalMemoryScreenState extends State<GlobalMemoryScreen> {
  List<Memory> _memories = [];
  bool _loading = true;
  static const _dir = '.greenix/memories';

  @override
  void initState() { super.initState(); _load(); }

  void _load() {
    final store = MemoryStore(_dir);
    store.load();
    final all = store.all().toList();
    all.sort((a, b) {
      const order = {'cardinal': 0, 'central': 1, 'secondary': 2,
                     'requirement': 3, 'high': 4, 'medium': 5, 'low': 6};
      return (order[a.priority] ?? 6).compareTo(order[b.priority] ?? 6);
    });
    if (mounted) setState(() { _memories = all; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cardinals = _memories.where((m) => m.priority == 'cardinal').toList();
    final centrals  = _memories.where((m) => m.priority == 'central').toList();
    final secondaries = _memories.where((m) => m.priority == 'secondary').toList();
    final requirements = _memories.where((m) => m.priority == 'requirement').toList();
    final facts = _memories.where((m) =>
        !['cardinal', 'central', 'secondary', 'requirement'].contains(m.priority)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加记忆',
            onPressed: () => _showEditDialog(),
          ),
          if (_memories.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空全部',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.memory, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('暂无全局记忆', style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      Text('AI 会在对话中自动提取你的特质和需求',
                          style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('手动添加'),
                        onPressed: () => _showEditDialog(),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (cardinals.isNotEmpty) ...[
                      _sectionHeader('👑 首要特质'),
                      ...cardinals.map(_memoryCard),
                    ],
                    if (centrals.isNotEmpty) ...[
                      _sectionHeader('🏷️ 中心特质 (${centrals.length})'),
                      _centralsChipBar(centrals),
                    ],
                    if (secondaries.isNotEmpty) ...[
                      _sectionHeader('💬 次要特质'),
                      ...secondaries.map(_memoryCard),
                    ],
                    if (requirements.isNotEmpty) ...[
                      _sectionHeader('📝 用户需求'),
                      ...requirements.map(_memoryCard),
                    ],
                    if (facts.isNotEmpty) ...[
                      _sectionHeader('📌 关键事实'),
                      ...facts.map(_memoryCard),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
  );

  Widget _centralsChipBar(List<Memory> centrals) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 8, runSpacing: 8,
      children: centrals.map((m) => InputChip(
        label: Text(m.title),
        deleteIcon: const Icon(Icons.close, size: 16),
        onDeleted: () { _deleteOne(m.name); },
        onPressed: () => _showEditDialog(existing: m),
      )).toList(),
    ),
  );

  Widget _memoryCard(Memory m) {
    final icon = m.priority == 'cardinal' ? '👑' :
                 m.priority == 'secondary' ? '💬' :
                 m.priority == 'requirement' ? '📝' : '📌';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 20)),
        title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: m.body.isNotEmpty && m.body != m.title
            ? Text(m.body, maxLines: 3, overflow: TextOverflow.ellipsis,
                   style: const TextStyle(fontSize: 12))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showEditDialog(existing: m),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              onPressed: () => _deleteOne(m.name),
            ),
          ],
        ),
        onTap: () => _showEditDialog(existing: m),
      ),
    );
  }

  void _deleteOne(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记忆'),
        content: const Text('确定要删除这条记忆吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = MemoryStore(_dir);
    store.delete(name);
    _load();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全局记忆'),
        content: const Text('删除所有跨会话的特质和关键事实？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = MemoryStore(_dir);
    store.load();
    for (final m in store.all().toList()) { store.delete(m.name); }
    _load();
  }

  Future<void> _showEditDialog({Memory? existing}) async {
    final typeCtrl = TextEditingController(
      text: existing?.priority == 'cardinal' ? 'cardinal' :
            existing?.priority == 'central' ? 'central' :
            existing?.priority == 'secondary' ? 'secondary' :
            existing?.priority == 'requirement' ? 'requirement' : 'key_fact',
    );
    // 优先用 title（特质始终存在 title），若 body 更长则用 body（关键事实的完整文本）
    final initText = existing != null
        ? (existing.body.length > existing.title.length ? existing.body : existing.title)
        : '';
    final contentCtrl = TextEditingController(text: initText);
    String selectedType = typeCtrl.text;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? '编辑记忆' : '添加记忆'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedType,
                items: const [
                  DropdownMenuItem(value: 'key_fact', child: Text('📌 关键事实')),
                  DropdownMenuItem(value: 'cardinal', child: Text('👑 首要特质')),
                  DropdownMenuItem(value: 'central', child: Text('🏷️ 中心特质')),
                  DropdownMenuItem(value: 'secondary', child: Text('💬 次要特质')),
                  DropdownMenuItem(value: 'requirement', child: Text('📝 用户需求')),
                ],
                onChanged: (v) { if (v != null) { setDialogState(() => selectedType = v); } },
                decoration: const InputDecoration(labelText: '类型', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                autofocus: existing == null,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () {
              typeCtrl.text = selectedType;
              Navigator.pop(ctx, true);
            }, child: const Text('保存')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final content = contentCtrl.text.trim();
    if (content.isEmpty) return;

    final store = MemoryStore(_dir);
    final priority = selectedType == 'cardinal' ? 'cardinal' :
                     selectedType == 'central' ? 'central' :
                     selectedType == 'secondary' ? 'secondary' :
                     selectedType == 'requirement' ? 'requirement' : 'high';
    final name = selectedType == 'central'
        ? 'central-$content'
        : '${selectedType}-${content.hashCode.toRadixString(16)}';

    // Delete old if editing
    if (existing != null) store.delete(existing.name);
    // cardinal replaces old
    if (selectedType == 'cardinal') {
      store.load();
      for (final old in store.all().where((m) => m.priority == 'cardinal')) {
        store.delete(old.name);
      }
    }

    store.save(Memory(
      name: name,
      title: content.length > 80 ? '${content.substring(0, 80)}...' : content,
      description: selectedType == 'cardinal' ? '首要特质' :
                   selectedType == 'central' ? '中心特质' :
                   selectedType == 'secondary' ? '次要特质' :
                   selectedType == 'requirement' ? '用户需求' : '关键事实',
      type: MemoryType.user,
      body: content,
      priority: priority,
    ));

    typeCtrl.dispose();
    contentCtrl.dispose();
    _load();
  }
}

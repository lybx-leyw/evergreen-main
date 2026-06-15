import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../core/agent/skill/skill.dart';

/// Skill 管理全屏页——查看/添加/编辑 Skill 文件。
class SkillManagerScreen extends StatefulWidget {
  const SkillManagerScreen({super.key});

  @override
  State<SkillManagerScreen> createState() => _SkillManagerScreenState();
}

class _SkillManagerScreenState extends State<SkillManagerScreen> {
  List<Skill> _skills = [];
  final Set<int> _expanded = {};
  bool _loading = true;
  static const _dir = '.greenix/skills';

  @override
  void initState() { super.initState(); _load(); }

  void _load() {
    final loader = SkillLoader([_dir]);
    final skills = loader.loadAll();
    skills.sort((a, b) => a.name.compareTo(b.name));
    if (mounted) setState(() { _skills = skills; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skill 管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建 Skill',
            onPressed: () => _showEditDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skills.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_fix_high, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('暂无自定义 Skill', style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      const Text('将 .md 文件放入 .greenix/skills/ 目录即可加载',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('新建 Skill'),
                        onPressed: () => _showEditDialog(),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('${_skills.length} 个 Skill 已加载',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      ),
                      ...List.generate(_skills.length, (i) => _skillCard(_skills[i], i)),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _skillCard(Skill s, int index) {
    final isExpanded = _expanded.contains(index);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.auto_fix_high, color: Colors.deepPurple),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() {
              if (isExpanded) _expanded.remove(index); else _expanded.add(index);
            }),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      s.body,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(s.runAs.name, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Text(s.scope.name, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: '编辑',
                        onPressed: () => _showEditDialog(existing: s),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18),
                        tooltip: '删除',
                        onPressed: () => _deleteSkill(s),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteSkill(Skill s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Skill'),
        content: Text('删除 "${s.name}"？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    // 删除 .md 文件
    try {
      if (s.path != '(builtin)' && s.path.isNotEmpty) {
        File(s.path).deleteSync();
      } else {
        File('$_dir/${s.name}.md').deleteSync();
      }
    } catch (_) {}
    _load();
  }

  Future<void> _showEditDialog({Skill? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final bodyCtrl = TextEditingController(text: existing?.body ?? '');
    String runAs = existing?.runAs.name ?? 'inline';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing != null ? '编辑 Skill' : '新建 Skill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称 (name)', hintText: 'my-skill',
                    border: OutlineInputBorder(),
                  ),
                  enabled: existing == null, // name 不可改
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: '描述 (description)',
                    hintText: '一行描述，告诉 AI 何时使用',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: '内容 (body)',
                    hintText: 'Markdown 格式的 Skill 正文...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 12,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: runAs,
                  items: const [
                    DropdownMenuItem(value: 'inline', child: Text('inline — 内联展开')),
                    DropdownMenuItem(value: 'subagent', child: Text('subagent — 子Agent执行')),
                  ],
                  onChanged: (v) { if (v != null) setDialogState(() => runAs = v); },
                  decoration: const InputDecoration(
                    labelText: '执行方式', border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final desc = descCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (name.isEmpty || desc.isEmpty) return;

    // 写入 .md 文件
    final path = existing?.path != null && existing!.path != '(builtin)'
        ? existing.path
        : '$_dir/$name.md';
    final frontmatter = '---\nname: $name\ndescription: $desc\nrun_as: $runAs\n---\n';
    File(path).writeAsStringSync('$frontmatter\n$body');

    nameCtrl.dispose();
    descCtrl.dispose();
    bodyCtrl.dispose();
    _load();
  }
}

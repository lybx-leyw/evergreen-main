/// 全局记忆页面——按 Allport 特质理论分类展示 AI 记忆。
///
/// 分类（记忆的 priority 维度）：
/// - cardinal    👑 首要特质（决定整体行为方式的核心形容词）
/// - central     🏷️ 中心特质（5-10 个核心形容词，人格主干）
/// - secondary   💬 次要特质（特定情境下显现的偏好/风格）
/// - requirement 📝 用户需求（希望 AI 始终遵循的要求）
/// - key_fact    📌 关键事实（客观、带时间锚定的硬事实，priority 存为 high/medium/low）
///
/// 该分类与 [core/agent] 的存储层（write_global_memory）及
/// .reference/agent_from/screens/global_memory_screen.dart 完全一致。
///
/// 公开类：[GlobalMemoryView]
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/memory/memory.dart' as mem;
import '../components/shared/widgets/markdown_renderer.dart';


/// Allport 特质分类（UI 维度的"类型"），对应记忆的 [mem.Memory.priority]。
const List<String> _allportTraits = [
  'cardinal',
  'central',
  'secondary',
  'requirement',
  'key_fact',
];

String _allportLabel(String trait) {
  switch (trait) {
    case 'cardinal':
      return '👑 首要特质';
    case 'central':
      return '🏷️ 中心特质';
    case 'secondary':
      return '💬 次要特质';
    case 'requirement':
      return '📝 用户需求';
    default:
      return '📌 关键事实';
  }
}

/// Allport 分类 → 记忆 priority 的映射（与 write_global_memory / 参考实现一致）。
/// key_fact 在存储层以 high 优先级记录（关键事实默认高优先级）。
String _allportPriority(String trait) {
  switch (trait) {
    case 'cardinal':
      return 'cardinal';
    case 'central':
      return 'central';
    case 'secondary':
      return 'secondary';
    case 'requirement':
      return 'requirement';
    default:
      return 'high';
  }
}

String _allportDescription(String trait) {
  switch (trait) {
    case 'cardinal':
      return '首要特质';
    case 'central':
      return '中心特质';
    case 'secondary':
      return '次要特质';
    case 'requirement':
      return '用户需求';
    default:
      return '关键事实';
  }
}

/// 将一条记忆映射回 Allport 分类（用于编辑对话框初值）。
String _allportTraitFromMemory(mem.Memory? m) {
  if (m == null) return 'key_fact';
  switch (m.priority) {
    case 'cardinal':
      return 'cardinal';
    case 'central':
      return 'central';
    case 'secondary':
      return 'secondary';
    case 'requirement':
      return 'requirement';
    default:
      return 'key_fact';
  }
}

/// 全局记忆页面。
///
/// 读取 [memoryStoreProvider] 获取所有记忆，按 Allport 特质 priority 分组展示。
class GlobalMemoryView extends ConsumerStatefulWidget {
  const GlobalMemoryView({super.key});

  @override
  ConsumerState<GlobalMemoryView> createState() => _GlobalMemoryViewState();
}

class _GlobalMemoryViewState extends ConsumerState<GlobalMemoryView> {
  List<mem.Memory> _memories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMemories());
  }

  Future<void> _loadMemories() async {
    try {
      final store = ref.read(memoryStoreProvider);
      final list = await store.all();
      if (!mounted) return;
      setState(() {
        _memories = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '无法加载记忆: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteMemory(String name) async {
    try {
      final store = ref.read(memoryStoreProvider);
      await store.delete(name);
      await _loadMemories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _saveMemory(mem.Memory memory) async {
    try {
      final store = ref.read(memoryStoreProvider);
      await store.save(memory);
      await _loadMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('记忆已保存'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog({mem.Memory? memory}) async {
    final isNew = memory == null;
    final nameCtrl = TextEditingController(text: memory?.name ?? '');
    final titleCtrl = TextEditingController(text: memory?.title ?? '');
    final descCtrl = TextEditingController(text: memory?.description ?? '');
    final bodyCtrl = TextEditingController(text: memory?.body ?? '');
    // Allport 特质分类（与 core/agent 存储层、.reference/agent_from 一致）
    var selectedTrait = _allportTraitFromMemory(memory);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MemoryEditDialog(
        isNew: isNew,
        nameCtrl: nameCtrl,
        titleCtrl: titleCtrl,
        descCtrl: descCtrl,
        bodyCtrl: bodyCtrl,
        selectedTrait: selectedTrait,
        onTraitChanged: (t) => selectedTrait = t,
      ),
    );

    if (result == true && mounted) {
      final name = nameCtrl.text.trim();
      final title = titleCtrl.text.trim();
      if (name.isEmpty && title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名称或标题不能为空')),
        );
        return;
      }
      // 自动从标题生成 name
      final effectiveName = name.isNotEmpty
          ? name.replaceAll(RegExp(r'[\s]+'), '-').toLowerCase()
          : title.replaceAll(RegExp(r'[\s]+'), '-').toLowerCase();
      // Allport 分类 → priority 映射（与 write_global_memory / 参考实现一致）
      final priority = _allportPriority(selectedTrait);
      // 新建记忆默认归入用户维度；编辑时保留原有 type
      final type = memory?.type ?? mem.MemoryType.user;
      await _saveMemory(mem.Memory(
        name: effectiveName,
        title: title.isNotEmpty ? title : effectiveName,
        description: _allportDescription(selectedTrait),
        type: type,
        body: bodyCtrl.text.trim(),
        priority: priority,
      ));
    }

    nameCtrl.dispose();
    titleCtrl.dispose();
    descCtrl.dispose();
    bodyCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局记忆'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建记忆',
            onPressed: () => _showEditDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadMemories,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadMemories, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_memories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined,
                size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无记忆',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              'AI 助手会在对话中按奥尔波特特质理论自动记录你的特质与关键事实',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // 按奥尔波特特质理论分组（与 core/agent 存储层、.reference/agent_from 一致）
    final grouped = mem.groupMemoriesByAllport(_memories);
    final cardinals = grouped['cardinal']!;
    final centrals = grouped['central']!;
    final secondaries = grouped['secondary']!;
    final requirements = grouped['requirement']!;
    final facts = grouped['key_fact']!;

    final sections = <_AllportSection>[
      _AllportSection(_allportLabel('cardinal'), Icons.star_rounded, cardinals,
          '决定用户整体行为方式的核心特质'),
      _AllportSection(_allportLabel('central'), Icons.sell_outlined, centrals,
          '5-10 个核心形容词，构成用户人格主干',
          isCentral: true),
      _AllportSection(_allportLabel('secondary'), Icons.chat_bubble_outline,
          secondaries, '特定情境下显现的偏好与风格'),
      _AllportSection(_allportLabel('requirement'), Icons.assignment_outlined,
          requirements, '用户希望 AI 始终遵循的要求'),
      _AllportSection(_allportLabel('key_fact'), Icons.push_pin_outlined, facts,
          '客观、带时间锚定的硬事实'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 概览卡片
        _MemoryOverviewCard(memories: _memories, theme: theme),
        const SizedBox(height: 20),
        // 按 Allport 特质分组
        for (final sec in sections)
          if (sec.memories.isNotEmpty)
            _AllportSectionView(
              section: sec,
              onDelete: (name) => _deleteMemory(name),
              onTap: (m) => _showEditDialog(memory: m),
            ),
      ],
    );
  }
}

// ═══════ _AllportSection ═══════

class _AllportSection {
  final String label;
  final IconData icon;
  final List<mem.Memory> memories;
  final String description;
  final bool isCentral;
  const _AllportSection(
    this.label,
    this.icon,
    this.memories,
    this.description, {
    this.isCentral = false,
  });
}

// ═══════ _MemoryOverviewCard ═══════

class _MemoryOverviewCard extends StatelessWidget {
  final List<mem.Memory> memories;
  final ThemeData theme;

  const _MemoryOverviewCard({required this.memories, required this.theme});

  @override
  Widget build(BuildContext context) {
    int count(String p) => memories.where((m) => m.priority == p).length;
    final traits =
        count('cardinal') + count('central') + count('secondary') + count('requirement');
    final facts = memories.length - traits;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.memory,
                  size: 32, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('记忆总览',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${memories.length} 条记忆',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (traits > 0 || facts > 0)
                    Text(
                      '$traits 条特质/需求 • $facts 条关键事实',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════ _AllportSectionView ═══════

class _AllportSectionView extends StatelessWidget {
  final _AllportSection section;
  final void Function(String name) onDelete;
  final void Function(mem.Memory) onTap;

  const _AllportSectionView({
    required this.section,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(section.icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.label,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${section.memories.length} 条 • ${section.description}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (section.isCentral)
          _CentralsChipBar(
            memories: section.memories,
            onEdit: onTap,
            onDelete: onDelete,
          )
        else ...[
          const SizedBox(height: 4),
          ...section.memories.map((m) => _MemoryCard(
                memory: m,
                onDelete: () => onDelete(m.name),
                onTap: () => onTap(m),
              )),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

// ═══════ _CentralsChipBar ═══════

class _CentralsChipBar extends StatelessWidget {
  final List<mem.Memory> memories;
  final void Function(mem.Memory) onEdit;
  final void Function(String name) onDelete;

  const _CentralsChipBar({
    required this.memories,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: memories.map((m) {
          final label = m.title.isNotEmpty ? m.title : m.name;
          return InputChip(
            label: Text(label),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => onDelete(m.name),
            onPressed: () => onEdit(m),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════ _MemoryCard ═══════

class _MemoryCard extends StatelessWidget {
  final mem.Memory memory;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _MemoryCard({
    required this.memory,
    required this.onDelete,
    required this.onTap,
  });

  String get _icon {
    switch (memory.priority) {
      case 'cardinal':
        return '👑';
      case 'central':
        return '🏷️';
      case 'secondary':
        return '💬';
      case 'requirement':
        return '📝';
      default:
        return '📌';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      memory.title.isNotEmpty ? memory.title : memory.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              if (memory.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  memory.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (memory.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: MarkdownRenderer(
                    text: memory.body.length > 300
                        ? '${memory.body.substring(0, 300)}...'
                        : memory.body,
                    useCard: false,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════ _MemoryEditDialog ═══════

class _MemoryEditDialog extends StatefulWidget {
  final bool isNew;
  final TextEditingController nameCtrl;
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final TextEditingController bodyCtrl;
  final String selectedTrait;
  final void Function(String) onTraitChanged;

  const _MemoryEditDialog({
    required this.isNew,
    required this.nameCtrl,
    required this.titleCtrl,
    required this.descCtrl,
    required this.bodyCtrl,
    required this.selectedTrait,
    required this.onTraitChanged,
  });

  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late String _trait;

  @override
  void initState() {
    super.initState();
    _trait = widget.selectedTrait;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? '新建记忆' : '编辑记忆'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isNew) ...[
                TextField(
                  controller: widget.nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '标识名 (name)',
                    hintText: '英文短横线标识，留空则自动生成',
                    border: OutlineInputBorder(),
                    helperText: '例: my-user-profile',
                    helperMaxLines: 1,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: widget.titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题 (title) *',
                  hintText: '人类可读的标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _trait,
                decoration: const InputDecoration(
                  labelText: '奥尔波特分类',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cardinal', child: Text('👑 首要特质')),
                  DropdownMenuItem(value: 'central', child: Text('🏷️ 中心特质')),
                  DropdownMenuItem(value: 'secondary', child: Text('💬 次要特质')),
                  DropdownMenuItem(value: 'requirement', child: Text('📝 用户需求')),
                  DropdownMenuItem(value: 'key_fact', child: Text('📌 关键事实')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _trait = v);
                    widget.onTraitChanged(v);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.descCtrl,
                decoration: const InputDecoration(
                  labelText: '描述 (description)',
                  hintText: '一行摘要，用于索引和召回',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.bodyCtrl,
                decoration: const InputDecoration(
                  labelText: '正文 (body)',
                  hintText: 'Markdown 格式正文',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
                minLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

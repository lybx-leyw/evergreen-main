/// 全局记忆页面——按 Allport 特质理论分类展示 AI 记忆。
///
/// 记忆类型：user（身份）| feedback（反馈）| project（项目）| reference（引用）
///
/// 公开类：[GlobalMemoryView]
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/memory/memory.dart' as mem;
import '../widgets/markdown_renderer.dart';
import 'theme_provider.dart';

/// 全局记忆页面。
///
/// 读取 [memoryStoreProvider] 获取所有记忆，按 [MemoryType] 分组展示。
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

  void _deleteMemory(String name) async {
    try {
      final store = ref.read(memoryStoreProvider);
      await store.delete(name);
      _loadMemories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  void _saveMemory(mem.Memory memory) async {
    try {
      final store = ref.read(memoryStoreProvider);
      store.save(memory);
      _loadMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记忆已保存'), duration: Duration(seconds: 1)),
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
    var selectedType = memory?.type ?? mem.MemoryType.project;
    var selectedPriority = memory?.priority ?? 'medium';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MemoryEditDialog(
        isNew: isNew,
        nameCtrl: nameCtrl,
        titleCtrl: titleCtrl,
        descCtrl: descCtrl,
        bodyCtrl: bodyCtrl,
        selectedType: selectedType,
        selectedPriority: selectedPriority,
        onTypeChanged: (t) => selectedType = t,
        onPriorityChanged: (p) => selectedPriority = p,
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
      _saveMemory(mem.Memory(
        name: effectiveName,
        title: title.isNotEmpty ? title : effectiveName,
        description: descCtrl.text.trim(),
        type: selectedType,
        body: bodyCtrl.text.trim(),
        priority: selectedPriority,
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
              'AI 助手会在对话中自动记录重要信息',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // 按类型分组
    final grouped = <mem.MemoryType, List<mem.Memory>>{};
    for (final m in _memories) {
      grouped.putIfAbsent(m.type, () => []).add(m);
    }

    final categories = [
      (_Category('用户身份', Icons.person, mem.MemoryType.user,
          '关于您的角色、偏好和专长')),
      (_Category('反馈指导', Icons.feedback, mem.MemoryType.feedback,
          '工作方式指导（含原因 + 应用方法）')),
      (_Category('项目上下文', Icons.work, mem.MemoryType.project,
          '当前工作、目标和约束')),
      (_Category('外部引用', Icons.link, mem.MemoryType.reference,
          '外部资源指针（URL、工单等）')),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 概览卡片
        _MemoryOverviewCard(memories: _memories, theme: theme),
        const SizedBox(height: 20),
        // 按类型分组
        for (final cat in categories)
          if (grouped.containsKey(cat.type) &&
              grouped[cat.type]!.isNotEmpty) ...[
            _CategorySection(
              category: cat,
              memories: grouped[cat.type]!,
              onDelete: _deleteMemory,
              onTap: (m) => _showEditDialog(memory: m),
            ),
          ],
      ],
    );
  }
}

// ═══════ _Category ═══════

class _Category {
  final String label;
  final IconData icon;
  final mem.MemoryType type;
  final String description;
  const _Category(this.label, this.icon, this.type, this.description);
}

// ═══════ _MemoryOverviewCard ═══════

class _MemoryOverviewCard extends StatelessWidget {
  final List<mem.Memory> memories;
  final ThemeData theme;

  const _MemoryOverviewCard({required this.memories, required this.theme});

  @override
  Widget build(BuildContext context) {
    final highCount = memories.where((m) => m.priority == 'high').length;

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
                  if (highCount > 0)
                    Text(
                      '$highCount 条高优先级 • ${memories.length - highCount} 条常规',
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

// ═══════ _CategorySection ═══════

class _CategorySection extends StatefulWidget {
  final _Category category;
  final List<mem.Memory> memories;
  final void Function(String name) onDelete;
  final void Function(mem.Memory) onTap;

  const _CategorySection({
    required this.category,
    required this.memories,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(widget.category.icon,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category.label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.memories.length} 条 • ${widget.category.description}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          ...widget.memories.map((m) => _MemoryCard(
                memory: m,
                onDelete: () => widget.onDelete(m.name),
                onTap: () => widget.onTap(m),
              )),
          const SizedBox(height: 12),
        ],
      ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHigh = memory.priority == 'high';

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
                  Expanded(
                    child: Text(
                      memory.title.isNotEmpty ? memory.title : memory.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isHigh)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('高优先级',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 10)),
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
  final mem.MemoryType selectedType;
  final String selectedPriority;
  final void Function(mem.MemoryType) onTypeChanged;
  final void Function(String) onPriorityChanged;

  const _MemoryEditDialog({
    required this.isNew,
    required this.nameCtrl,
    required this.titleCtrl,
    required this.descCtrl,
    required this.bodyCtrl,
    required this.selectedType,
    required this.selectedPriority,
    required this.onTypeChanged,
    required this.onPriorityChanged,
  });

  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late mem.MemoryType _type;
  late String _priority;

  @override
  void initState() {
    super.initState();
    _type = widget.selectedType;
    _priority = widget.selectedPriority;
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
              DropdownButtonFormField<mem.MemoryType>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: '类型',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: mem.MemoryType.user, child: Text('👤 用户身份')),
                  DropdownMenuItem(value: mem.MemoryType.feedback, child: Text('💬 反馈指导')),
                  DropdownMenuItem(value: mem.MemoryType.project, child: Text('📁 项目上下文')),
                  DropdownMenuItem(value: mem.MemoryType.reference, child: Text('🔗 外部引用')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _type = v);
                    widget.onTypeChanged(v);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(
                  labelText: '优先级',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('🟢 低')),
                  DropdownMenuItem(value: 'medium', child: Text('🟡 中')),
                  DropdownMenuItem(value: 'high', child: Text('🔴 高')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _priority = v);
                    widget.onPriorityChanged(v);
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

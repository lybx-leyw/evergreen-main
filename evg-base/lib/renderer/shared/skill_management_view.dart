/// 技能管理页面——列举 + 新建自定义 Skill。
///
/// 公开类：[SkillManagementView]
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/core/agent/skill/skill.dart';
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'theme_provider.dart';

/// 技能管理页面。
///
/// 读取 [skillIndexProvider] 列举所有技能，支持新建自定义 Skill。
class SkillManagementView extends ConsumerStatefulWidget {
  const SkillManagementView({super.key});

  @override
  ConsumerState<SkillManagementView> createState() =>
      _SkillManagementViewState();
}

class _SkillManagementViewState extends ConsumerState<SkillManagementView> {
  List<Skill> _skills = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSkills());
  }

  void _loadSkills() {
    try {
      final index = ref.read(skillIndexProvider);
      setState(() {
        _skills = index.all();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '无法加载技能: $e';
        _loading = false;
      });
    }
  }

  void _showNewSkillDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _NewSkillDialog(),
    ).then((_) => _loadSkills());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('技能管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadSkills,
          ),
          IconButton.filled(
            icon: const Icon(Icons.add),
            tooltip: '新建技能',
            onPressed: _showNewSkillDialog,
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
            ElevatedButton(onPressed: _loadSkills, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_skills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_fix_high,
                size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无技能',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('点击右上角 + 创建自定义技能',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showNewSkillDialog,
              icon: const Icon(Icons.add),
              label: const Text('新建技能'),
            ),
          ],
        ),
      );
    }

    // 按 scope 分组
    final scopes = <SkillScope, List<Skill>>{};
    for (final s in _skills) {
      scopes.putIfAbsent(s.scope, () => []).add(s);
    }

    final scopeLabels = {
      SkillScope.builtin: ('内置技能', Icons.settings),
      SkillScope.global: ('全局技能', Icons.public),
      SkillScope.project: ('项目技能', Icons.folder),
      SkillScope.custom: ('自定义技能', Icons.auto_fix_high),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 概览卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_fix_high,
                      size: 32, color: theme.colorScheme.secondary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('技能总览',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${_skills.length} 个技能',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // 按 scope 分组
        for (final scope in [SkillScope.builtin, SkillScope.global,
            SkillScope.project, SkillScope.custom])
          if (scopes.containsKey(scope) && scopes[scope]!.isNotEmpty) ...[
            _ScopeSection(
              label: scopeLabels[scope]?.$1 ?? scope.name,
              icon: scopeLabels[scope]?.$2 ?? Icons.help,
              skills: scopes[scope]!,
            ),
          ],
      ],
    );
  }
}

// ═══════ _ScopeSection ═══════

class _ScopeSection extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Skill> skills;

  const _ScopeSection({
    required this.label,
    required this.icon,
    required this.skills,
  });

  @override
  State<_ScopeSection> createState() => _ScopeSectionState();
}

class _ScopeSectionState extends State<_ScopeSection> {
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
                Icon(widget.icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.label} (${widget.skills.length})',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
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
        if (_expanded)
          ...widget.skills.map((s) => _SkillCard(skill: s)),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ═══════ _SkillCard ═══════

class _SkillCard extends StatelessWidget {
  final Skill skill;
  const _SkillCard({required this.skill});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSubagent = skill.runAs == SkillRunAs.subagent;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSubagent ? Icons.smart_toy : Icons.auto_fix_high,
                  size: 18,
                  color: isSubagent
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isSubagent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('subagent',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                            fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              skill.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (skill.allowedTools.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: skill.allowedTools
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(t,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════ _NewSkillDialog ═══════

class _NewSkillDialog extends StatefulWidget {
  const _NewSkillDialog();

  @override
  State<_NewSkillDialog> createState() => _NewSkillDialogState();
}

class _NewSkillDialogState extends State<_NewSkillDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _scope = 'custom';
  String _runAs = 'inline';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入技能名称')),
      );
      return;
    }
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入技能描述')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final skillsDir = Directory(greenixSkillsDir);
      if (!skillsDir.existsSync()) {
        skillsDir.createSync(recursive: true);
      }

      final filename = '${name.replaceAll(RegExp(r'\s+'), '-').toLowerCase()}.md';
      final frontmatter = StringBuffer();
      frontmatter.writeln('---');
      frontmatter.writeln('name: $name');
      frontmatter.writeln('description: $desc');
      frontmatter.writeln('run_as: $_runAs');
      frontmatter.writeln('---');
      frontmatter.writeln();
      frontmatter.writeln(body);

      final file = File('${skillsDir.path}${Platform.pathSeparator}$filename');
      await file.writeAsString(frontmatter.toString());

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('技能 "$name" 创建成功')),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建技能'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '技能名称 *',
                  hintText: '例如: summarize-code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: '描述 *',
                  hintText: '一行描述，显示在技能列表中',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _scope,
                      decoration: const InputDecoration(
                        labelText: '作用域',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'custom', child: Text('自定义')),
                        DropdownMenuItem(value: 'project', child: Text('项目')),
                        DropdownMenuItem(value: 'global', child: Text('全局')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _scope = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _runAs,
                      decoration: const InputDecoration(
                        labelText: '运行方式',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'inline', child: Text('内联 (inline)')),
                        DropdownMenuItem(
                            value: 'subagent', child: Text('子 Agent (subagent)')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _runAs = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '技能内容 (Markdown)',
                  hintText: '# 技能说明\n\n详细描述这个技能的功能...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: Text(_saving ? '保存中...' : '创建'),
        ),
      ],
    );
  }
}

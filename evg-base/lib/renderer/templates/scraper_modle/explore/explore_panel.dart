/// 探索模式 UI（Phase 4 · D1-D6）。
///
/// - [ExplorePanel]：探索进度面板（阶段/页数/请求计数 + 候选/选择展示）
/// - [showExploreSourcePicker]：数据源多选弹窗（D4：勾选 + 可改名 → 用户确认）
///
/// 颜色一律从 `Theme.of(context).colorScheme` 派生（全局 theme 规约，不硬编码）。
library explore_panel;

import 'package:flutter/material.dart';

import 'explore_workflow.dart';

// ═══════ ExplorePanel ═══════

/// 探索进度面板（嵌入生成器右侧面板，探索模式替代请求日志面板）。
class ExplorePanel extends StatelessWidget {
  final ExploreWorkflow exploreWorkflow;

  /// 「开始探索」按钮回调（idle 阶段；AI 面板负责确认弹窗 + 发 prompt）。
  final Future<void> Function()? onStartExplore;

  /// 「重新打开选择框」回调（confirming 阶段）。
  final VoidCallback? onReselectSources;

  const ExplorePanel({
    super.key,
    required this.exploreWorkflow,
    this.onStartExplore,
    this.onReselectSources,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = exploreWorkflow.phase;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, phase),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: _buildBody(theme, phase),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ExplorePhase phase) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.travel_explore_rounded, size: 14),
          const SizedBox(width: 4),
          Text(
            '探索模式',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _phaseColor(phase, scheme).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _phaseLabel(phase),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _phaseColor(phase, scheme),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'GET-only · 同域',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ExplorePhase phase) {
    final scheme = theme.colorScheme;
    final wf = exploreWorkflow;

    switch (phase) {
      case ExplorePhase.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🧭 让 AI 探索当前网站的所有 GET 接口，自动归类为候选数据源，'
              '由你勾选后批量构建注册。',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 12, color: scheme.tertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '请先在左侧浏览器登录目标网站（凭证沿用已保存配置）。',
                    style: TextStyle(fontSize: 11, color: scheme.tertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: FilledButton.icon(
                onPressed:
                    onStartExplore == null ? null : () => onStartExplore!(),
                icon: const Icon(Icons.play_arrow_rounded, size: 14),
                label: const Text('开始探索', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        );

      case ExplorePhase.exploring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔎 AI 正在探索（循环：枚举链接 → GET 导航 → 读捕获日志）…',
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
            const SizedBox(height: 10),
            _counterRow(theme, '页数', wf.uniquePages, wf.limits.maxPages),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: wf.limits.maxPages == 0
                  ? 0
                  : (wf.uniquePages / wf.limits.maxPages).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 6),
            _counterRow(theme, '请求', wf.requestsCaptured, wf.limits.maxRequests),
            if (wf.baseHost.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '🌐 锁定同域: ${wf.baseHost}',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '节流 ${wf.limits.minNavigateInterval.inMilliseconds}ms · '
              '触达上限后 AI 会自动结束探索进入归类',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        );

      case ExplorePhase.categorizing:
        return Text(
          '🗂 AI 正在把 GET 接口归类为候选数据源…',
          style: TextStyle(fontSize: 11, color: scheme.onSurface),
        );

      case ExplorePhase.confirming:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '☑️ 候选数据源 ${wf.candidates.length} 个，请勾选要构建的数据源（可改名）',
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            _candidateChips(theme, wf.candidates),
            const SizedBox(height: 8),
            if (onReselectSources != null)
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  onPressed: onReselectSources,
                  icon: const Icon(Icons.checklist_rounded, size: 14),
                  label:
                      const Text('重新打开选择框', style: TextStyle(fontSize: 10)),
                ),
              ),
          ],
        );

      case ExplorePhase.building:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔧 正在逐源构建 ${wf.selected.length} 个数据源插件（data-{name}）…',
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            _selectedChips(theme, wf.selected),
          ],
        );

      case ExplorePhase.registering:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔗 正在批量注册 ${wf.selected.length} 个数据源并验证数据中心拉取…',
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            _selectedChips(theme, wf.selected),
          ],
        );

      case ExplorePhase.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🎉 探索完成：${wf.selected.length} 个数据源已批量注册，'
              '数据看板可查看新数据源。',
              style: TextStyle(
                fontSize: 11,
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _selectedChips(theme, wf.selected),
          ],
        );

      case ExplorePhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '❌ 探索失败',
              style: TextStyle(
                fontSize: 11,
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              wf.errorMessage.isEmpty ? '（无详细信息）' : wf.errorMessage,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '可在对话中让 AI 重新归类/重建/重注册。',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }

  Widget _counterRow(ThemeData theme, String label, int value, int max) {
    final scheme = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(
            '$value / $max',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: value >= max ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _candidateChips(ThemeData theme, List<CandidateDataSource> list) {
    return _chips(theme, list, showCategory: true);
  }

  Widget _selectedChips(ThemeData theme, List<CandidateDataSource> list) {
    return _chips(theme, list, showCategory: false);
  }

  Widget _chips(ThemeData theme, List<CandidateDataSource> list,
      {required bool showCategory}) {
    final scheme = theme.colorScheme;
    if (list.isEmpty) {
      return Text('（暂无）',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final c in list)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              showCategory && c.category.isNotEmpty
                  ? '${c.name} · ${c.category}'
                  : c.name,
              style: TextStyle(
                fontSize: 10,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
      ],
    );
  }

  static String _phaseLabel(ExplorePhase p) => switch (p) {
        ExplorePhase.idle => '待开始',
        ExplorePhase.exploring => '探索中',
        ExplorePhase.categorizing => '归类中',
        ExplorePhase.confirming => '等待确认',
        ExplorePhase.building => '构建中',
        ExplorePhase.registering => '注册中',
        ExplorePhase.done => '✅ 完成',
        ExplorePhase.failed => '❌ 失败',
      };

  static Color _phaseColor(ExplorePhase p, ColorScheme scheme) => switch (p) {
        ExplorePhase.exploring => scheme.tertiary,
        ExplorePhase.categorizing ||
        ExplorePhase.confirming ||
        ExplorePhase.building ||
        ExplorePhase.registering =>
          scheme.secondary,
        ExplorePhase.done => scheme.primary,
        ExplorePhase.failed => scheme.error,
        _ => scheme.outline,
      };
}

// ═══════ 数据源多选弹窗 ═══════

/// 数据源多选确认弹窗（D4：勾选 + 可改名）。
///
/// 默认全选；用户可取消勾选、修改 name（实时校验）；
/// 确认返回勾选列表（含改名）；取消返回空列表。
Future<List<CandidateDataSource>> showExploreSourcePicker(
  BuildContext context,
  List<CandidateDataSource> candidates,
) async {
  final result = await showDialog<List<CandidateDataSource>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExploreSourcePickerDialog(candidates: candidates),
  );
  return result ?? const [];
}

class _ExploreSourcePickerDialog extends StatefulWidget {
  const _ExploreSourcePickerDialog({required this.candidates});

  final List<CandidateDataSource> candidates;

  @override
  State<_ExploreSourcePickerDialog> createState() =>
      _ExploreSourcePickerDialogState();
}

class _ExploreSourcePickerDialogState
    extends State<_ExploreSourcePickerDialog> {
  late final List<bool> _checked = List.filled(widget.candidates.length, true);

  /// ⚠️ controller 生命周期由 State 管理（弹窗退出动画期间仍被 TextField 访问，
  /// await showDialog 返回后立即 dispose 会 "used after being disposed"）。
  late final List<TextEditingController> _nameCtrls = [
    for (final c in widget.candidates)
      TextEditingController(text: c.name),
  ];

  @override
  void dispose() {
    for (final c in _nameCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final anyChecked = _checked.any((c) => c);

    return AlertDialog(
      title: const Text('☑️ 选择要构建的数据源', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 归类出 ${widget.candidates.length} 个候选数据源。'
              '勾选要构建的（可修改名称），确认后 AI 将逐源构建并批量注册。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.candidates.length; i++)
                      _buildItem(context, i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: anyChecked ? () => _confirm(context) : null,
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext context, int i) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.candidates[i];
    final nameErr = sanitizeSourceName(_nameCtrls[i].text);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _checked[i] ? scheme.primary.withValues(alpha: 0.4) : theme.dividerColor,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: _checked[i],
                onChanged: (v) => setState(() => _checked[i] = v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _nameCtrls[i],
                  enabled: _checked[i],
                  style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    labelText: 'data-',
                    errorText: _checked[i] ? nameErr : null,
                    errorStyle: const TextStyle(fontSize: 9),
                    errorMaxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayName.isEmpty ? c.name : c.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      c.url,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (c.category.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    c.category,
                    style: TextStyle(
                        fontSize: 10, color: scheme.onTertiaryContainer),
                  ),
                ),
              ],
            ],
          ),
          if (c.fields.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                '字段: ${c.fields.map((f) => f.name).join(', ')}',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirm(BuildContext context) {
    final out = <CandidateDataSource>[];
    for (var i = 0; i < widget.candidates.length; i++) {
      if (!_checked[i]) continue;
      final name = _nameCtrls[i].text.trim();
      if (sanitizeSourceName(name) != null) continue; // 非法名称跳过
      final c = widget.candidates[i];
      out.add(name == c.name ? c : c.copyWith(name: name));
    }
    if (out.isEmpty) return;
    Navigator.pop(context, out);
  }
}

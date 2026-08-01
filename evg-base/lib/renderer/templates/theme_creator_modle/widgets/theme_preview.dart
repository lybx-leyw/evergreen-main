/// Dart 实时预览——与真实应用**同一渲染路径**。
///
/// 与真实预览的办法一致（app.dart 同款）：
/// - 用 [buildAppThemeFromDescriptor] 构建 light/dark 两套 [ThemeData]
/// - 包进真实 [MaterialApp]（theme/darkTheme/themeMode.system 与主应用完全一致）
/// - 壳层结构与真实 [AppShell] 一致（Material 侧边栏 + VerticalDivider + 内容区）
///
/// 只是不展示插件：内容区换成**我们定义的主题演示页**（真实 Material 组件：
/// 按钮/输入框/开关/下拉/卡片/表格/气泡/进度条/弹层），让创作者看到
/// 主题在真实组件上的效果。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/renderer/app/service/theme/theme_provider.dart';

/// 主题实时预览（真实 MaterialApp 路径）。
class ThemePreview extends StatelessWidget {
  /// 实时草稿（随编辑即时重建）。
  final ThemeDescriptor draft;

  const ThemePreview({super.key, required this.draft});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 与主应用完全一致的取数方式：同一 descriptor → light/dark 两套 ThemeData
      theme: buildAppThemeFromDescriptor(draft, brightness: Brightness.light),
      darkTheme: buildAppThemeFromDescriptor(draft, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: _PreviewHome(name: draft.name),
    );
  }
}

// ═══════ 预览壳层（镜像真实 AppShell 桌面布局） ═══════

/// 预览首页：真实 Scaffold + 侧边栏 + 演示内容页。
class _PreviewHome extends StatelessWidget {
  final String name;

  const _PreviewHome({required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 侧边栏宽度自适应：目标 230（真实 AppShell 展开宽度），
          // 预览面板窄时按比例收缩，避免溢出。
          final sidebarWidth =
              (constraints.maxWidth * 0.32).clamp(140.0, 230.0);
          final scale = sidebarWidth / 230.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewSidebar(width: sidebarWidth, scale: scale),
              const VerticalDivider(width: 1),
              Expanded(child: _DemoPage(name: name)),
            ],
          );
        },
      ),
    );
  }
}

/// 侧边栏——镜像真实 _ExpandedSidebar 的结构与配色（头部/分组/悬停/折叠钮）。
class _PreviewSidebar extends StatelessWidget {
  final double width;
  final double scale;

  const _PreviewSidebar({required this.width, required this.scale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 品牌头部（镜像真实：标题 primary 加粗 + 副标题）
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16 * scale, 14 * scale, 16 * scale, 10 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Evergreen',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                          fontSize: 16 * scale)),
                  const SizedBox(height: 2),
                  Text('Evergreen 多工具集成版',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10 * scale)),
                ],
              ),
            ),
            const Divider(height: 1),
            // 分组标题（镜像真实 _SectionHeader）
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16 * scale, 12 * scale, 16 * scale, 4 * scale),
              child: Text('base主功能',
                  style: TextStyle(
                      fontSize: 10 * scale,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ),
            _NavItem(Icons.home, '首页', active: true, scale: scale),
            _NavItem(Icons.school, '课程', scale: scale),
            _NavItem(Icons.insights, '成绩', scale: scale),
            _NavItem(Icons.store, '市场', scale: scale),
            const Divider(),
            const Spacer(),
            _NavItem(Icons.settings, '设置', scale: scale),
            // 折叠按钮（镜像真实，非功能展示）
            Center(
              child: IconButton(
                icon: Icon(Icons.chevron_left, size: 18 * scale),
                tooltip: '收起侧栏',
                onPressed: () {},
                visualDensity: VisualDensity.compact,
              ),
            ),
            SizedBox(height: 4 * scale),
          ],
        ),
      ),
    );
  }
}

/// 侧边栏导航项（与真实 AppShell 的 _NavItem 同构：悬停/激活态 + 真实尺寸）。
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final double scale;

  const _NavItem(this.icon, this.label,
      {this.active = false, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
      child: Material(
        color: active ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8 * scale),
        child: InkWell(
          onTap: () {},
          hoverColor: scheme.primary.withValues(alpha: 0.08),
          splashColor: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8 * scale),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 12 * scale, vertical: 10 * scale),
            child: Row(
              children: [
                Icon(icon,
                    size: 20 * scale,
                    color: active
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    semanticLabel: label),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                    fontSize: 14 * scale,
                    color: active
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════ 演示内容页（我们定义的内容，真实 Material 组件） ═══════

/// 主题演示页——覆盖真实应用的主要 UI 结构与状态。
class _DemoPage extends StatelessWidget {
  final String name;

  const _DemoPage({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 页头（对齐真实模块页头：padding 16,16,16,4 + 标题加粗） ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题演示 · $name',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('真实 MaterialApp + 真实组件渲染，明暗随系统',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                // 弹层演示（Wrap 自动换行，窄窗口不溢出）
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('SnackBar · 主题 $name'),
                          action:
                              SnackBarAction(label: '撤销', onPressed: () {}),
                        ),
                      ),
                      icon: const Icon(Icons.notifications, size: 14),
                      label: const Text('SnackBar',
                          style: TextStyle(fontSize: 11)),
                    ),
                    OutlinedButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('对话框'),
                          content:
                              const Text('弹层也跟随主题（边框/阴影/按钮色）。'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('确定')),
                          ],
                        ),
                      ),
                      child:
                          const Text('对话框', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── TabBar ──
          const TabBar(
            tabs: [
              Tab(text: '组件', icon: Icon(Icons.widgets, size: 14)),
              Tab(text: '数据', icon: Icon(Icons.table_chart, size: 14)),
            ],
            labelStyle: TextStyle(fontSize: 12),
          ),
          // ── 内容 ──
          Expanded(
            child: TabBarView(
              children: [
                _ComponentsTab(),
                _DataTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 组件页——控件、卡片、气泡、进度。
class _ComponentsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── 按钮行 ──
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: () {}, child: const Text('主按钮')),
            FilledButton.tonal(onPressed: () {}, child: const Text('柔和按钮')),
            OutlinedButton(onPressed: () {}, child: const Text('描边按钮')),
            TextButton(onPressed: () {}, child: const Text('文字按钮')),
            IconButton(
                onPressed: () {}, icon: const Icon(Icons.favorite, size: 18)),
            const Chip(label: Text('Chip 标签')),
            const Badge(label: Text('3'), child: Icon(Icons.mail, size: 18)),
          ],
        ),
        const SizedBox(height: 14),
        // ── 输入行 ──
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: '文本框',
                  hintText: '边框/聚焦色跟随主题',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownMenu<String>(
                label: const Text('下拉', style: TextStyle(fontSize: 12)),
                textStyle: const TextStyle(fontSize: 12),
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 'a', label: '选项 A'),
                  DropdownMenuEntry(value: 'b', label: '选项 B'),
                  DropdownMenuEntry(value: 'c', label: '选项 C'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ── 开关 / 复选 ──
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('开关 Switch', style: TextStyle(fontSize: 12)),
          value: true,
          onChanged: (_) {},
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('复选 Checkbox', style: TextStyle(fontSize: 12)),
          value: true,
          onChanged: (_) {},
        ),
        // ── 进度 ──
        const LinearProgressIndicator(value: 0.6),
        const SizedBox(height: 8),
        Slider(value: 0.4, onChanged: (_) {}),
        const SizedBox(height: 4),
        // ── 卡片 + 列表 ──
        Card(
          child: ListTile(
            leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.person, size: 16,
                    color: scheme.onPrimaryContainer)),
            title: const Text('列表项标题', style: TextStyle(fontSize: 12)),
            subtitle: const Text('次要文字 textSecondary',
                style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16),
          ),
        ),
        const SizedBox(height: 10),
        // ── 消息气泡 ──
        _Bubble(
          color: scheme.primaryContainer,
          textColor: scheme.onPrimaryContainer,
          alignRight: true,
          text: '用户消息 · 主色容器气泡',
        ),
        const SizedBox(height: 6),
        _Bubble(
          color: scheme.surfaceContainerHighest,
          textColor: scheme.onSurface,
          alignRight: false,
          text: '助手消息 · 表面色气泡',
        ),
      ],
    );
  }
}

/// 数据页——表格、状态徽章、指标卡。
class _DataTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // ── 指标卡 ──
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: '平均绩点',
                value: '3.72',
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: '待办事项',
                value: '5',
                color: scheme.secondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(label: '异常项', value: '1', color: scheme.error),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── 状态徽章 ──
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(label: '成功', color: Colors.green.shade600),
            _StatusChip(label: '警告', color: Colors.orange.shade700),
            _StatusChip(label: '错误', color: scheme.error),
            _StatusChip(label: '次要', color: scheme.secondary),
          ],
        ),
        const SizedBox(height: 14),
        // ── 表格（横向滚动，窄预览区不溢出） ──
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            headingRowHeight: 32,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 36,
            headingRowColor:
                WidgetStatePropertyAll(scheme.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('课程', style: TextStyle(fontSize: 11))),
              DataColumn(label: Text('学分', style: TextStyle(fontSize: 11))),
              DataColumn(label: Text('成绩', style: TextStyle(fontSize: 11))),
              DataColumn(label: Text('状态', style: TextStyle(fontSize: 11))),
            ],
            rows: [
              for (final r in const [
                ['高等数学', '5.0', '95', '优秀'],
                ['大学物理', '4.0', '88', '良好'],
                ['程序设计', '4.0', '82', '良好'],
              ])
                DataRow(cells: [
                  for (final c in r)
                    DataCell(Text(c, style: const TextStyle(fontSize: 11))),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}

/// 指标卡。
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 状态徽章。
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

/// 消息气泡。
class _Bubble extends StatelessWidget {
  final Color color;
  final Color textColor;
  final bool alignRight;
  final String text;

  const _Bubble({
    required this.color,
    required this.textColor,
    required this.alignRight,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(alignRight ? 12 : 2),
            bottomRight: Radius.circular(alignRight ? 2 : 12),
          ),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: textColor)),
      ),
    );
  }
}

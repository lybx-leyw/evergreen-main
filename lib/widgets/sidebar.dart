import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'breakpoints.dart';
import '../features/todo/providers/todo_provider.dart';
import '../features/exams/providers/exams_provider.dart';

/// Navigation sidebar — ports the sidebar from app/index.html.
///
/// Organized into 4 categories matching the original:
/// - Learning: courses, todo, scores, exams, downloads
/// - AI Tools: notes, wordpecker, quiz, classroom
/// - Campus: autosign, ecard, library, teachers, rvpn
/// - System: dashboard, scheduler, settings
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On narrow screens, use bottom navigation bar
        if (constraints.maxWidth <= Breakpoints.mobile) {
          return _MobileShell(child: child);
        }
        return _DesktopShell(child: child);
      },
    );
  }
}

class _DesktopShell extends ConsumerStatefulWidget {
  final Widget child;
  const _DesktopShell({required this.child});

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell>
    with SingleTickerProviderStateMixin {
  bool _collapsed = false;
  bool _initialized = false;

  static const double _expandedWidth = 230;
  static const double _collapsedWidth = 60;
  static const double _autoCollapseThreshold = 800;

  @override
  void initState() {
    super.initState();
    _loadCollapsedPref();
  }

  Future<void> _loadCollapsedPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _collapsed = prefs.getBool('sidebar_collapsed') ?? false;
        _initialized = true;
      });
    }
  }

  Future<void> _setCollapsed(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sidebar_collapsed', v);
    setState(() => _collapsed = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Scaffold(
        body: Row(
          children: [
            const SizedBox(width: _expandedWidth, child: SizedBox()),
            const VerticalDivider(width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final autoCollapse = constraints.maxWidth <= _autoCollapseThreshold;
        final collapsed = autoCollapse || _collapsed;
        final sidebarWidth = collapsed ? _collapsedWidth : _expandedWidth;

        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: sidebarWidth,
                child: collapsed
                    ? _CollapsedSidebar(
                        onExpand: () => _setCollapsed(false),
                      )
                    : _ExpandedSidebar(
                        onCollapse: () => _setCollapsed(true),
                      ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: widget.child),
            ],
          ),
        );
      },
    );
  }
}

/// Collapsed sidebar — icons only with tooltips.
class _CollapsedSidebar extends ConsumerWidget {
  final VoidCallback onExpand;

  const _CollapsedSidebar({required this.onExpand});

  static final _icons = <IconData>[
    Icons.dashboard,
    Icons.school,
    Icons.checklist,
    Icons.assignment,
    Icons.grade,
    Icons.event,
    Icons.auto_awesome,
    Icons.smart_toy,
    Icons.video_library,
    Icons.settings,
  ];

  static final _routes = <String>[
    '/dashboard',
    '/courses',
    '/todo',
    '/plan',
    '/scores',
    '/exams',
    '/notes',
    '/agent',
    '/classroom',
    '/settings',
  ];

  static final _labels = <String>[
    '仪表盘',
    '课程',
    '待办',
    '计划管理',
    '成绩',
    '考试',
    'AI 笔记',
    'AI 助手',
    '智云课堂',
    '设置',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Logo icon
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Icon(
              Icons.eco,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const Divider(),
          // Icon-only nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: List.generate(_icons.length, (i) {
                final isActive = location == _routes[i] ||
                    (location.startsWith(_routes[i]) && _routes[i] != '/dashboard');
                return Tooltip(
                  message: _labels[i],
                  waitDuration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Material(
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.go(_routes[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Icon(
                            _icons[i],
                            size: 20,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Expand button
          Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '展开侧栏',
              onPressed: onExpand,
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _MobileNavBar(),
    );
  }
}

class _ExpandedSidebar extends ConsumerWidget {
  final VoidCallback onCollapse;

  const _ExpandedSidebar({required this.onCollapse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZJU live better\nand better',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Evergreen 多工具集成版',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                _SectionHeader(title: '学习'),
                _NavItem(icon: Icons.school, label: '课程', path: '/courses', current: location),
                _NavItem(icon: Icons.book, label: '开课情况', path: '/course-offerings', current: location),
                _NavItem(icon: Icons.account_tree, label: '培养方案', path: '/training-plans', current: location),
                _NavItemWithBadge(
                  icon: Icons.checklist, label: '待办', path: '/todo', current: location,
                  badge: ref.watch(todoListProvider).when(
                    data: (todos) {
                      final now = DateTime.now();
                      final urgent = todos.where((t) {
                        if (t.deadline == null) return false;
                        final deadline = DateTime.tryParse(t.deadline!);
                        if (deadline == null || deadline.isBefore(now)) return false;
                        final diffDays = deadline.difference(now).inDays;
                        return diffDays >= 0 && diffDays <= 7;
                      }).length;
                      return urgent > 0 ? urgent : null;
                    },
                    error: (_, __) => null,
                    loading: () => null,
                  ),
                ),
                _NavItem(icon: Icons.assignment, label: '计划管理', path: '/plan', current: location),
                _NavItem(icon: Icons.grade, label: '成绩', path: '/scores', current: location),
                _NavItemWithBadge(
                  icon: Icons.event, label: '考试', path: '/exams', current: location,
                  badge: ref.watch(examsListProvider).when(
                    data: (exams) {
                      final now = DateTime.now();
                      final upcoming = exams.where((e) {
                        if (e.startTime == null) return false;
                        final start = e.startTime!;
                        if (start.isBefore(now)) return false;
                        final diffDays = start.difference(now).inDays;
                        return diffDays >= 0 && diffDays <= 21;
                      }).length;
                      return upcoming > 0 ? upcoming : null;
                    },
                    error: (_, __) => null,
                    loading: () => null,
                  ),
                ),
                _NavItem(icon: Icons.download, label: '下载', path: '/downloads', current: location),
                const Divider(),
                _SectionHeader(title: 'AI 工具'),
                _NavItem(icon: Icons.auto_awesome, label: 'AI 笔记', path: '/notes', current: location),
                _NavItem(icon: Icons.smart_toy, label: 'AI 助手', path: '/agent', current: location),
                _NavItem(icon: Icons.video_library, label: '智云课堂', path: '/classroom', current: location),
                const Divider(),
                _SectionHeader(title: '校园'),
                _NavItem(icon: Icons.campaign, label: '教务通知', path: '/zdbk-notifications', current: location),
                _NavItem(icon: Icons.person_search, label: '查老师', path: '/teachers', current: location),
                const Divider(),
                _SectionHeader(title: '系统'),
                _NavItem(icon: Icons.dashboard, label: '仪表盘', path: '/dashboard', current: location),
                _NavItem(icon: Icons.wifi_tethering, label: '数据状态', path: '/quick-connect', current: location),
                _NavItem(icon: Icons.settings, label: '设置', path: '/settings', current: location),
              ],
            ),
          ),
          // Collapse button
          Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '收起侧栏',
              onPressed: onCollapse,
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileNavBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;

    return NavigationBar(
      selectedIndex: _getMobileIndex(location),
      onDestinationSelected: (index) {
        final paths = [
          '/dashboard', '/courses', '/todo', '/notes',
        ];
        if (index < paths.length) {
          context.go(paths[index]);
        }
      },
      destinations: [
        const NavigationDestination(icon: Icon(Icons.dashboard), label: '仪表盘'),
        const NavigationDestination(icon: Icon(Icons.school), label: '课程'),
        const NavigationDestination(icon: Icon(Icons.checklist), label: '待办'),
        const NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI笔记'),
        const NavigationDestination(icon: Icon(Icons.smart_toy), label: 'AI助手'),
      ],
    );
  }

  int _getMobileIndex(String path) {
    if (path.startsWith('/courses')) return 1;
    if (path.startsWith('/todo')) return 2;
    if (path.startsWith('/notes')) return 3;
    return 0;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Nav item with optional badge count.
class _NavItemWithBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String current;
  final int? badge;

  const _NavItemWithBadge({
    required this.icon,
    required this.label,
    required this.path,
    required this.current,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == path;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String current;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == path;
    return Semantics(
      label: label,
      hint: '导航到 $label',
      selected: isActive,
      button: true,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: label,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

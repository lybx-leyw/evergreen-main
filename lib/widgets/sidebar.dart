import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'breakpoints.dart';
import '../core/registry/modules.dart';
import '../modules.dart';

/// Navigation sidebar — ports the sidebar from app/index.html.
///
/// Navigation items are generated from [ModuleRegistry], not hardcoded.
/// To add a new top-level page, create a [FeatureModule] subclass and
/// register it in `lib/modules.dart`.
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final navFlat = registry.navFlat;
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
              children: List.generate(navFlat.length, (i) {
                final entry = navFlat[i];
                final isActive = location == entry.routePath ||
                    (location.startsWith(entry.routePath) &&
                        entry.routePath != '/dashboard');
                return Tooltip(
                  message: entry.label,
                  waitDuration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Material(
                      color: isActive
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => context.go(entry.routePath),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          child: Icon(
                            entry.icon,
                            size: 20,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                foregroundColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends ConsumerWidget {
  final Widget child;
  const _MobileShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final registry = ref.watch(moduleRegistryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(_mobileTitle(registry, location)),
      ),
      drawer: _MobileDrawer(current: location, onTap: (path) {
        // Navigation happens in _DrawerItem.onTap via context.go()
      }),
      body: child,
      bottomNavigationBar: _MobileNavBar(),
    );
  }

  String _mobileTitle(ModuleRegistry registry, String path) {
    // 遍历所有模块，找匹配的路由
    for (final entry in registry.navFlat) {
      if (path.startsWith(entry.routePath) &&
          entry.routePath != '/dashboard') {
        return entry.label;
      }
    }
    // 处理子路由（模块可能有多个路由）
    for (final m in registry.modules) {
      for (final r in m.buildRoutes()) {
        if (r is GoRoute && path.startsWith(r.path) && r.path != '/dashboard') {
          return m.name;
        }
      }
    }
    return 'Evergreen';
  }
}

/// Full navigation drawer for mobile — mirrors the desktop sidebar.
class _MobileDrawer extends ConsumerWidget {
  final String current;
  final void Function(String)? onTap;
  const _MobileDrawer({required this.current, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _DrawerHeader(),
            const Divider(),
            // 按 section 生成
            for (final (section, entries) in registry.navGroups) ...[
              _SectionHeader(title: section.label),
              for (final entry in entries)
                _DrawerItem(
                  icon: entry.icon,
                  label: entry.label,
                  path: entry.routePath,
                  current: current,
                  onTap: onTap,
                ),
              const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.eco,
              color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(height: 8),
          Text('Evergreen 多工具集成版',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text('全部功能',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String path;
  final String current;
  final void Function(String)? onTap;
  const _DrawerItem(
      {required this.icon,
      required this.label,
      required this.path,
      required this.current,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = current == path ||
        (current.startsWith(path) && path != '/dashboard');
    return ListTile(
      leading: Icon(icon,
          color: isActive ? Theme.of(context).colorScheme.primary : null),
      title: Text(label,
          style: TextStyle(
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
      selected: isActive,
      onTap: () {
        onTap?.call(path);
        context.go(path);
      },
    );
  }
}

class _ExpandedSidebar extends ConsumerWidget {
  final VoidCallback onCollapse;

  const _ExpandedSidebar({required this.onCollapse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZJU live better\nand better',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Evergreen 多工具集成版',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 按 section 生成导航项
                for (final (section, entries) in registry.navGroups) ...[
                  _SectionHeader(title: section.label),
                  for (final entry in entries)
                    _buildNavItem(context, ref, entry, location),
                  const Divider(),
                ],
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
                foregroundColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context, WidgetRef ref, NavEntry entry, String location) {
    final badge = entry.badgeProvider != null
        ? ref.watch(entry.badgeProvider!)
        : null;

    if (badge != null && badge > 0) {
      return _NavItemWithBadge(
        icon: entry.icon,
        label: entry.label,
        path: entry.routePath,
        current: location,
        badge: badge,
      );
    }
    return _NavItem(
      icon: entry.icon,
      label: entry.label,
      path: entry.routePath,
      current: location,
    );
  }
}

class _MobileNavBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final location = GoRouterState.of(context).uri.path;
    // 取前 5 个导航项作为底部导航
    final topItems = registry.navFlat.take(5).toList();

    return NavigationBar(
      selectedIndex: _getMobileIndex(topItems, location),
      onDestinationSelected: (index) {
        if (index < topItems.length) {
          context.go(topItems[index].routePath);
        }
      },
      destinations: topItems
          .map((e) => NavigationDestination(
                icon: Icon(e.icon),
                label: e.label,
              ))
          .toList(),
    );
  }

  int _getMobileIndex(List<NavEntry> items, String path) {
    for (int i = 0; i < items.length; i++) {
      if (path.startsWith(items[i].routePath) &&
          items[i].routePath != '/dashboard') {
        return i;
      }
    }
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
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

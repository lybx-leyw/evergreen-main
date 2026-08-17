/// 应用侧边栏——模块导航 + 用户信息。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/theme/breakpoints.dart';
import 'package:evergreen_base/core/module/modules.dart';
import 'package:evergreen_base/generated/plugin_imports.g.dart';
import 'package:evergreen_base/renderer/app/service/providers/renderer_providers.dart';
import 'package:evergreen_base/core/feedback/feedback_bar.dart';
import '../../providers.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/nav_filter.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/plugin_state_provider.dart';
import 'app_mode.dart';
import 'mode_rail.dart';

/// 应用侧边栏——模块导航。
///
/// Navigation items are generated from [ModuleRegistry], not hardcoded.
/// To add a new top-level page, create a [FeatureModule] subclass and
/// register it in `lib/modules.dart`.

/// 处理侧边栏导航点击 — 统一走 GoRouter（HTML 模块内嵌 WebView 渲染）。
void _handleNavTap(WidgetRef ref, BuildContext context, NavEntry entry) {
  debugPrint('[AppShell] 导航: ${entry.label} → ${entry.routePath}');
  context.go(entry.routePath);
}

/// V2: 将 codePoint (int) 转为 Material [IconData]。
IconData _icon(int codePoint) => IconData(codePoint, fontFamily: 'MaterialIcons');

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= Breakpoints.mobile) {
          return _MobileShell(child: child, mode: mode);
        }
        return _DesktopShell(child: child, mode: mode);
      },
    );
  }
}

// ═══════ _DesktopShell ═══════

class _DesktopShell extends ConsumerStatefulWidget {
  final Widget child;
  final AppMode mode;
  const _DesktopShell({required this.child, required this.mode});

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
    // 模式 1/2（AI 视图 / 开发者模式）：窄轨壳层，无展开侧栏。
    if (widget.mode != AppMode.plugins) {
      return _RailShell(child: widget.child, mode: widget.mode);
    }
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
          body: Stack(
            children: [
              Row(
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
              const FeedbackFab(),
            ],
          ),
        );
      },
    );
  }
}

// ═══════ _RailShell（模式 1/2 窄轨壳层） ═══════

/// 模式 1/2（AI 视图 / 开发者模式）窄轨壳层：
/// ModeRail + 主内容 + 浮动返回按钮（推入页出现）+ FeedbackFab。
class _RailShell extends ConsumerWidget {
  final Widget child;
  final AppMode mode;

  const _RailShell({required this.child, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 路由变化时重建（GoRouter.of 注册继承依赖），使返回按钮随导航栈显隐。
    final canPop = GoRouter.of(context).canPop();
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              ModeRail(mode: mode),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
          // 推入页返回：全屏推入 显示设置/插件中心/数据中心 后出现，
          // 返回后 AI 会话在 provider 中后台继续。
          if (canPop)
            const Positioned(
              left: kModeRailWidth + 12,
              top: 12,
              child: _FloatingBackButton(),
            ),
          const FeedbackFab(),
        ],
      ),
    );
  }
}

/// 浮动返回按钮——主区左上角，颜色从 colorScheme 派生。
class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        color: scheme.onSurfaceVariant,
        onPressed: () => context.pop(),
      ),
    );
  }
}

// ═══════ _CollapsedSidebar ═══════

/// Collapsed sidebar — icons only with tooltips.
class _CollapsedSidebar extends ConsumerWidget {
  final VoidCallback onExpand;

  const _CollapsedSidebar({required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final states = ref.watch(pluginStateProvider);
    final navFlat = filterNavFlatByPluginState(
        filterNavFlatByAppMode(registry.navFlat), states);
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
          // 模块导航（图标）
          Expanded(
            child: ListView(
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
                        onTap: () => _handleNavTap(ref, context, entry),
                        hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          child: Icon(
                            _icon(entry.icon),
                            size: 20,
                            color: isActive
                                ? Theme.of(context).colorScheme.onPrimaryContainer
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

// ═══════ _MobileShell ═══════

class _MobileShell extends ConsumerWidget {
  final Widget child;
  final AppMode mode;
  const _MobileShell({required this.child, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 模式 1/2（AI 视图 / 开发者模式）：窄轨壳层（移动端复用同一窄轨）。
    if (mode != AppMode.plugins) {
      return _RailShell(child: child, mode: mode);
    }
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
      // modules 直接路由匹配
      if (m.route != null && path.startsWith(m.route!) && m.route != '/dashboard') {
        return m.name;
      }
    }
    return 'Evergreen';
  }
}

// ═══════ _MobileDrawer ═══════

/// Full navigation drawer for mobile — mirrors the desktop sidebar.
class _MobileDrawer extends ConsumerWidget {
  final String current;
  final void Function(String)? onTap;
  const _MobileDrawer({required this.current, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final states = ref.watch(pluginStateProvider);
    final groups = filterNavByPluginState(
        filterNavByAppMode(registry.navGroups), states);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _DrawerHeader(),
            const Divider(),
            // 按 section 生成（已按插件状态过滤）
            for (final (section, entries) in groups) ...[
              _SectionHeader(title: section.label),
              for (final entry in entries)
                _DrawerItem(
                  icon: _icon(entry.icon),
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

// ═══════ _DrawerHeader ═══════

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

// ═══════ _DrawerItem ═══════

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

// ═══════ _ExpandedSidebar ═══════

class _ExpandedSidebar extends ConsumerWidget {
  final VoidCallback onCollapse;

  const _ExpandedSidebar({required this.onCollapse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final states = ref.watch(pluginStateProvider);
    final location = GoRouterState.of(context).uri.path;
    // 按插件状态（启用/侧栏可见）+ 模式（排除 4 个特殊插件）过滤导航
    final groups = filterNavByPluginState(
        filterNavByAppMode(registry.navGroups), states);

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
                        'Evergreen',
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
                // 按 section 生成导航项（已按插件状态过滤）
                for (final (section, entries) in groups) ...[
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
    return _NavItem(
      icon: _icon(entry.icon),
      label: entry.label,
      path: entry.routePath,
      current: location,
      entry: entry,
    );
  }
}

// ═══════ _MobileNavBar ═══════

class _MobileNavBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(moduleRegistryProvider);
    final states = ref.watch(pluginStateProvider);
    final location = GoRouterState.of(context).uri.path;
    // 取前 5 个导航项作为底部导航（已按插件状态 + 模式过滤）
    final topItems = filterNavFlatByPluginState(
            filterNavFlatByAppMode(registry.navFlat), states)
        .take(5)
        .toList();

    return NavigationBar(
      selectedIndex: _getMobileIndex(topItems, location),
      onDestinationSelected: (index) {
        if (index < topItems.length) {
          context.go(topItems[index].routePath);
        }
      },
      destinations: topItems
          .map((e) => NavigationDestination(
                icon: Icon(_icon(e.icon)),
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

// ═══════ _SectionHeader ═══════

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

// ═══════ _NavItemWithBadge ═══════

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
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(path),
          hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
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
                          ? Theme.of(context).colorScheme.onPrimaryContainer
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

// ═══════ _NavItem ═══════

class _NavItem extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String path;
  final String current;
  final NavEntry entry;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.current,
    required this.entry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onTap: () => _handleNavTap(ref, context, entry),
            hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
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
                            ? Theme.of(context).colorScheme.onPrimaryContainer
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



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
              ref.watch(showFeedbackFabProvider) ? const FeedbackFab() : const SizedBox.shrink(),
            ],
          ),
        );
      },
    );
  }
}

// ═══════ _RailShell（模式 1/2 窄轨壳层） ═══════

/// AI 视图推入返回 AppBar 的路由白名单：仅当从 AI 视图推入这些系统面板时，
/// 壳层内容区顶部出现返回 AppBar（面板自身无 AppBar/返回按钮）。
const Set<String> _aiShellBackRoutes = {
  '/settings',
  '/data-dashboard',
  '/marketplace',
};

/// 白名单路由对应的面板显示名（返回 AppBar 标题，与 AI 助手抽屉/插件 Tab 语义一致）。
const Map<String, String> _aiShellBackTitles = {
  '/settings': '设置',
  '/data-dashboard': '数据中枢',
  '/marketplace': '插件中心',
};

/// 模式 1/2（AI 视图 / 开发者模式）窄轨壳层：
/// ModeRail + 主内容 + FeedbackFab。
/// AI 视图下窄轨隐藏，且推入设置/数据中心/插件中心面板时显示同款返回 AppBar。
class _RailShell extends ConsumerWidget {
  final Widget child;
  final AppMode mode;

  const _RailShell({required this.child, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AI 视图：窄轨（ModeRail）整体隐藏，内容区占满；
    // 原窄轨按钮（模式切换/系统按钮）已收进 AI 助手左侧抽屉（SystemDrawerSection）。
    // 开发者模式：仍保留窄轨（开发者入口逻辑在窄轨内）。
    if (mode == AppMode.ai) {
      // 从 AI 视图推入设置/数据中心/插件中心面板时，内容区顶部显示同款返回
      // AppBar（AI 助手样式，自带 SafeArea/状态栏处理，替代原左上角浮珠）。
      // 判据 = AI 视图 + 当前路径 ∈ 白名单（AI 视图下进入这三个面板的唯一途径
      // 就是 AI 视图本身，无需再依赖 canPop——push 期间壳层只在过渡早期重建，
      // 彼时 navigator 栈尚未更新，canPop 不可靠）。
      // GoRouterState.of 注册继承依赖，路由变化时本 build 重建，返回后按钮消失。
      final path = GoRouterState.of(context).uri.path;
      final showBack = _aiShellBackRoutes.contains(path);
      final body = showBack
          ? Column(
              children: [
                _AiPanelBackAppBar(title: _aiShellBackTitles[path]),
                Expanded(child: child),
              ],
            )
          : child;
      return Scaffold(
        body: Stack(
          children: [
            body,
            ref.watch(showFeedbackFabProvider)
                ? const FeedbackFab()
                : const SizedBox.shrink(),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              SizedBox(
                width: kModeRailWidth,
                child: ModeRail(mode: mode),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
          ref.watch(showFeedbackFabProvider) ? const FeedbackFab() : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// AI 面板返回 AppBar——AI 视图推入设置/数据中心/插件中心面板后，
/// 显示在面板内容顶部的同款返回条（样式对齐 AI 助手 AppBar：
/// 显式 backgroundColor: surfaceContainerLowest + surfaceTintColor 透明 +
/// scrolledUnderElevation: 0，面板内容可滚动时不会回退近黑）。
/// 点击优先 pop 回推入页；若栈不可 pop（如快捷键 go 直达），
/// 回退到 AI 视图默认页。
class _AiPanelBackAppBar extends ConsumerWidget {
  final String? title;

  const _AiPanelBackAppBar({this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '返回',
        color: scheme.onSurfaceVariant,
        onPressed: () {
          final router = GoRouter.of(context);
          if (router.canPop()) {
            router.pop();
            return;
          }
          // 栈不可 pop（go 直达，如全局快捷键 _SettingsIntent）：
          // 回 AI 视图默认页，避免用户被困在面板。
          final registry = ref.read(moduleRegistryProvider);
          final pluginStates = ref.read(pluginStateProvider).records;
          final target = defaultRouteForMode(
                mode: AppMode.ai,
                registry: registry,
                pluginStates: pluginStates,
              ) ??
              '/ai-assistant';
          router.go(target);
        },
      ),
      title: title == null ? null : Text(title!),
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
    final pstate = ref.watch(pluginStateProvider);
    final navFlat = applyUserNavLayoutFlat(
      filterNavByPluginState(filterNavByAppMode(registry.navGroups), pstate.records),
      pstate.config,
      pstate.records,
    );
    final location = GoRouterState.of(context).uri.path;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // 视图模式切换（AI / 开发者 / 插件）——插件视图切回的入口
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ModeSwitchButton(mode: AppMode.plugins),
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
    final pstate = ref.watch(pluginStateProvider);
    final config = pstate.config;
    final groups = applyUserNavLayout(
      filterNavByPluginState(
          filterNavByAppMode(registry.navGroups), pstate.records),
      config,
      pstate.records,
    );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _DrawerHeader(),
            const Divider(),
            // 按 section 生成（已按插件状态过滤 + 用户布局重排）
            for (final (section, entries) in groups) ...[
              // 组名可按用户配置隐藏（插件中心的分组「侧边栏显示组名」开关）。
              if (config.groups[section.label]?.showNameInSidebar ?? true)
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
          // 视图模式切换（AI / 开发者 / 插件）——插件视图切回的入口
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.eco,
                  color: Theme.of(context).colorScheme.primary, size: 28),
              const ModeSwitchButton(mode: AppMode.plugins),
            ],
          ),
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
    final pstate = ref.watch(pluginStateProvider);
    final config = pstate.config;
    final location = GoRouterState.of(context).uri.path;
    // 按插件状态（启用/侧栏可见）+ 模式（排除 4 个特殊插件）过滤导航，
    // 再按用户拖拽布局（分组顺序 + 组内顺序）重排。
    final groups = applyUserNavLayout(
      filterNavByPluginState(
          filterNavByAppMode(registry.navGroups), pstate.records),
      config,
      pstate.records,
    );

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
                      // 视图模式切换（AI / 开发者 / 插件）——插件视图切回的入口
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Evergreen',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                          ),
                          const ModeSwitchButton(mode: AppMode.plugins),
                        ],
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
                // 按 section 生成导航项（已按插件状态过滤 + 用户布局重排）
                for (final (section, entries) in groups) ...[
                  // 组名可按用户配置隐藏（插件中心的分组「侧边栏显示组名」开关）。
                  if (config.groups[section.label]?.showNameInSidebar ?? true)
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
    final pstate = ref.watch(pluginStateProvider);
    final location = GoRouterState.of(context).uri.path;
    // 取前 5 个导航项作为底部导航（已按插件状态 + 模式过滤 + 用户布局重排）
    final topItems = applyUserNavLayoutFlat(
            filterNavByPluginState(
                filterNavByAppMode(registry.navGroups), pstate.records),
            pstate.config,
            pstate.records)
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



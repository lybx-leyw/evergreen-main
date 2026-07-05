import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/log.dart';
import 'feature_module.dart';
import 'sidebar_section.dart';

/// 模块注册中心——所有 FeatureModule 在此注册，框架层从此读取。
///
/// 使用方式：
/// ```dart
/// final registry = ModuleRegistry();
/// registry.register(PalaceModule());
/// registry.register(CoursesModule());
/// // ...
/// registry.seal(); // 锁定，不得再注册
/// ```
///
/// 锁定后可通过 [routes]、[navGroups] 等 getter 获取生成的配置。
class ModuleRegistry {
  final List<FeatureModule> _modules = [];
  bool _sealed = false;

  /// 注册一个模块。必须在 [seal] 之前调用。
  void register(FeatureModule module) {
    if (_sealed) {
      throw StateError('ModuleRegistry 已锁定，不能再注册模块。'
          ' 请在 seal() 之前注册所有模块。');
    }
    // 检查重复 id
    final dup = _modules.any((m) => m.id == module.id);
    if (dup) {
      throw ArgumentError('模块 id "${module.id}" 重复，请检查。');
    }
    _modules.add(module);
  }

  /// 锁定注册中心，校验依赖完整性。之后不能再注册模块。
  void seal() {
    _sealed = true;
    _validateDependencies();
    Log().info('ModuleRegistry sealed: ${_modules.length} 个模块已注册',
        data: {'ids': _modules.map((m) => m.id).toList()});
  }

  /// 所有已注册的模块（只读）。
  List<FeatureModule> get modules => List.unmodifiable(_modules);

  /// 按 id 查找模块。
  FeatureModule? findById(String id) {
    try {
      return _modules.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 路由生成
  // ═══════════════════════════════════════════════════════════

  /// 构建所有模块的路由列表（用于 GoRouter 的 ShellRoute.routes）。
  List<RouteBase> buildRoutes() {
    _requireSealed();
    return _modules.expand((m) => m.buildRoutes()).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 侧边栏导航生成
  // ═══════════════════════════════════════════════════════════

  /// 按 section 分组的导航条目。
  /// 返回 [(section, [NavEntry])] ，用于构建侧边栏。
  List<(SidebarSection, List<NavEntry>)> get navGroups {
    _requireSealed();
    final grouped = <SidebarSection, List<NavEntry>>{};

    for (final m in _modules) {
      final sec = m.sidebarSection;
      final icon = m.icon;
      if (sec == null || icon == null) continue;

      final route = m.buildRoutes().isNotEmpty
          ? _firstRoutePath(m)
          : null;
      if (route == null) continue;

      grouped.putIfAbsent(sec, () => []);
      grouped[sec]!.add(NavEntry(
        icon: icon,
        label: m.name,
        routePath: route,
        order: m.sidebarOrder,
        badgeProvider: m.sidebarBadgeProvider,
      ));

      // 额外导航条目（如 zdbk 的"开课情况""培养方案"）
      for (final s in m.secondaryNavs) {
        grouped.putIfAbsent(s.section, () => []);
        grouped[s.section]!.add(NavEntry(
          icon: s.icon,
          label: s.label,
          routePath: s.routePath,
          order: s.order,
          badgeProvider: s.badgeProvider,
        ));
      }
    }

    // 每个 section 内按 order 排序
    for (final list in grouped.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    // Section 按定义顺序
    final sorted = grouped.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    return sorted.map((e) => (e.key, e.value)).toList();
  }

  /// 所有导航条目（扁平列表，忽略 section，用于 collapsed 侧边栏）。
  List<NavEntry> get navFlat {
    _requireSealed();
    return navGroups.expand((g) => g.$2).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 命令面板条目生成
  // ═══════════════════════════════════════════════════════════

  /// 所有命令面板可搜索条目。
  List<PaletteItemDecl> get paletteItems {
    _requireSealed();
    final items = <PaletteItemDecl>[];
    for (final m in _modules) {
      final custom = m.paletteItems;
      if (custom.isNotEmpty) {
        items.addAll(custom);
        continue;
      }

      // 主导航条目
      if (m.icon != null && m.sidebarSection != null) {
        final route = m.buildRoutes().isNotEmpty ? _firstRoutePath(m) : null;
        if (route != null) {
          items.add(PaletteItemDecl(
            title: m.name,
            subtitle: route,
            icon: m.icon!,
            route: route,
            category: m.sidebarSection!.label,
          ));
        }
      }

      // 额外导航条目（如 zdbk 的"开课情况""培养方案"）
      for (final s in m.secondaryNavs) {
        items.add(PaletteItemDecl(
          title: s.label,
          subtitle: s.routePath,
          icon: s.icon,
          route: s.routePath,
          category: s.section.label,
        ));
      }
    }
    return items;
  }

  // ═══════════════════════════════════════════════════════════
  // 连通性检查收集
  // ═══════════════════════════════════════════════════════════

  /// 收集所有模块声明的连通性检查。
  List<ConnectivityDecl> get connectivityChecks {
    _requireSealed();
    return _modules
        .where((m) => m.connectivityDecl != null)
        .map((m) => m.connectivityDecl!)
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 数据源收集
  // ═══════════════════════════════════════════════════════════

  /// 收集所有模块声明的数据源。
  List<DataSourceDecl> get allDataSources {
    _requireSealed();
    return _modules.expand((m) => m.dataSources).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // Agent 工具收集
  // ═══════════════════════════════════════════════════════════

  /// 收集所有模块声明的 Agent 工具。
  List<AgentToolDecl> get allAgentTools {
    _requireSealed();
    return _modules.expand((m) => m.agentTools).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 依赖校验
  // ═══════════════════════════════════════════════════════════

  void _validateDependencies() {
    final ids = _modules.map((m) => m.id).toSet();
    final errors = <String>[];
    for (final m in _modules) {
      for (final dep in m.dependsOn) {
        if (!ids.contains(dep)) {
          errors.add('模块 "${m.id}" 依赖 "${dep}"，但 "${dep}" 未注册');
        }
      }
    }
    if (errors.isNotEmpty) {
      throw StateError('模块依赖校验失败:\n${errors.join("\n")}');
    }
  }

  void _requireSealed() {
    if (!_sealed) {
      throw StateError('ModuleRegistry 尚未锁定。请在注册所有模块后调用 seal()。');
    }
  }

  /// 解析模块第一个路由的路径（用于侧边栏导航）。
  String? _firstRoutePath(FeatureModule module) {
    final routes = module.buildRoutes();
    if (routes.isEmpty) return null;
    final first = routes.first;
    if (first is GoRoute) return first.path;
    if (first is ShellRoute) {
      // 递归取第一个子路由
      final sub = first.routes;
      if (sub.isNotEmpty && sub.first is GoRoute) {
        return (sub.first as GoRoute).path;
      }
    }
    return null;
  }
}

/// 侧边栏导航条目（框架层从 [FeatureModule] 声明生成）。
class NavEntry {
  final IconData icon;
  final String label;
  final String routePath;
  final int order;

  /// 可选的角标 Provider（如待办数）。
  final ProviderListenable<int?>? badgeProvider;

  const NavEntry({
    required this.icon,
    required this.label,
    required this.routePath,
    this.order = 50,
    this.badgeProvider,
  });
}

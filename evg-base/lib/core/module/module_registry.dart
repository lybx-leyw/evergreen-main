/// 模块注册中心——收集 [ModuleDescriptor]，生成路由/导航/命令面板。
///
/// # API
///
/// | 方法 | 输入 | 输出 | 说明 |
/// |---|---|---|---|
/// | `register(d)` | `ModuleDescriptor` | `void` | 注册一个模块 |
/// | `registerAll(list)` | `List<ModuleDescriptor>` | `void` | 批量注册 |
/// | `registerFromJson(str)` | `String` | `void` | 从 JSON 字符串注册 |
/// | `seal()` | — | `void` | 锁定 + 依赖校验 |
/// | `modules` | — | `List<ModuleDescriptor>` | 只读模块列表 |
/// | `findById(id)` | `String` | `ModuleDescriptor?` | 按 id 查找 |
/// | `buildRoutePaths()` | — | `List<String>` | 所有路由路径 |
/// | `navGroups` | — | `List<(SidebarSection, List<NavEntry>)>` | 分组导航 |
/// | `navFlat` | — | `List<NavEntry>` | 扁平导航 |
/// | `paletteItems` | — | `List<({...})>` | 命令面板条目 |
import 'package:evergreen_base/core/log.dart';
import 'capability.dart';
import 'lattice.dart';
import 'module_descriptor.dart';
import 'plugin_manifest.dart';
import 'resolved_plugin.dart';
import 'sidebar_section.dart';

/// 模块注册中心——所有 [ModuleDescriptor] 在此注册，框架层从此读取。
///
/// 使用方式：
/// ```dart
/// final registry = ModuleRegistry();
/// registry.register(agentModule);
/// registry.registerAll(pluginModules);
/// registry.seal(); // 锁定，不得再注册
/// ```
class ModuleRegistry {
  final List<ModuleDescriptor> _modules = [];
  final Map<String, List<CapabilityDimension>> _capabilities = {};

  /// 解析后的插件单一事实源索引（M0 · 3.4）——registry/loader/权限执行器统一消费。
  final List<ResolvedPlugin> _resolved = [];

  bool _sealed = false;

  // ═══════ 注册 ═══════

  /// 注册一个模块。必须在 [seal] 之前调用。
  ///
  /// 内部自动包装为 [ResolvedPlugin]（M0 单一事实源）。
  void register(ModuleDescriptor module) {
    registerResolved(ResolvedPlugin.fromDescriptor(module));
  }

  /// 注册一个已解析的 [ResolvedPlugin]（M0 单一事实源入口）。
  ///
  /// installer/loader 若已持有 ResolvedPlugin，应直接调用此方法避免重复解析。
  void registerResolved(ResolvedPlugin resolved) {
    if (_sealed) {
      throw StateError('ModuleRegistry 已锁定，不能再注册模块。'
          ' 请在 seal() 之前注册所有模块。');
    }
    final module = resolved.descriptor;
    final dup = _modules.any((m) => m.id == module.id);
    if (dup) {
      throw ArgumentError('模块 id "${module.id}" 重复，请检查。');
    }
    _modules.add(module);
    _resolved.add(resolved);
  }

  /// 批量注册模块。
  void registerAll(List<ModuleDescriptor> modules) {
    for (final m in modules) {
      register(m);
    }
  }

  /// 从 JSON 字符串解析并注册一个模块。
  void registerFromJson(String jsonString) {
    register(ModuleDescriptor.fromJsonString(jsonString));
  }

  /// 锁定注册中心，校验依赖完整性。之后不能再注册模块。
  void seal() {
    _sealed = true;
    _validateDependencies();
    Log().info('ModuleRegistry sealed: ${_modules.length} 个模块已注册',
        data: {'ids': _modules.map((m) => m.id).toList()});
  }

  // ═══════ 查询 ═══════

  /// 所有已注册的模块（只读）。
  List<ModuleDescriptor> get modules {
    _requireSealed();
    return List.unmodifiable(_modules);
  }

  /// 按 id 查找模块。
  ModuleDescriptor? findById(String id) {
    _requireSealed();
    try {
      return _modules.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 按路由路径查找模块（I9 接口）。
  ///
  /// V2: 匹配 [ModuleDescriptor.route] 和各 [PageDescriptor.route]。
  /// 返回 `null` 表示无匹配模块。
  ModuleDescriptor? findByRoute(String path) {
    _requireSealed();
    for (final m in _modules) {
      if (m.route == path) return m;
      // V2: 页面路由
      for (final page in m.pages) {
        if (page.route == path) return m;
      }
      // V2: 子导航路由
      for (final nav in m.nav.secondary) {
        if (nav.routePath == path) return m;
      }
    }
    return null;
  }

  /// 按查询词、能力维度、分类搜索模块（I10 接口）。
  ///
  /// 返回 [PluginManifest] 列表（轻量搜索结果），供渲染层市场搜索使用。
  /// [query] 匹配 id/name/description（不区分大小写）。
  /// [dims] 按能力维度筛选；`null` 或空列表表示不限。
  /// [cat] 按分类标签筛选（对应 sidebar section）；`null` 或空字符串表示不限。
  List<PluginManifest> search(
    String query, {
    List<CapabilityDimension>? dims,
    String? cat,
  }) {
    _requireSealed();
    final q = query.toLowerCase();
    Iterable<ModuleDescriptor> results = _modules.where((m) {
      return m.id.toLowerCase().contains(q) ||
          m.name.toLowerCase().contains(q) ||
          m.description.toLowerCase().contains(q);
    });

    if (dims != null && dims.isNotEmpty) {
      results = results.where((m) {
        final caps = _capabilities[m.id] ?? [];
        return dims.any((d) => caps.contains(d));
      });
    }

    if (cat != null && cat.isNotEmpty) {
      results = results.where((m) {
        return m.nav.sidebar?.section == cat;
      });
    }

    return results.map((m) {
      return PluginManifest(
        id: m.id,
        name: m.name,
        description: m.description,
        icon: m.icon,
        dimensions: _capabilities[m.id] ?? [],
        category: m.nav.sidebar?.section ?? '',
        version: m.version,
      );
    }).toList();
  }

  /// 按能力维度列出所有具备该能力的模块。
  ///
  /// 能力维度需通过 [setCapabilities] 预先设置（通常在 ModuleLoader 扫描时）。
  /// 未设置维度的模块不会被任何维度查询返回。
  List<ModuleDescriptor> listByCapability(CapabilityDimension dim) {
    _requireSealed();
    return _modules
        .where((m) => (_capabilities[m.id] ?? []).contains(dim))
        .toList();
  }

  /// 为模块设置能力维度（注册时由 ModuleLoader 调用）。
  ///
  /// 必须在 [seal] 前调用。覆盖同 id 的已有维度。
  void setCapabilities(String moduleId, List<CapabilityDimension> dims) {
    if (_sealed) {
      throw StateError('ModuleRegistry 已锁定，不能再设置能力维度。');
    }
    _capabilities[moduleId] = List.unmodifiable(dims);
  }

  /// 按六格契约等级列出所有落在该格的插件（M0）。
  ///
  /// 消费 [ResolvedPlugin] 单一事实源，不重新解析 JSON。
  List<ResolvedPlugin> findByLattice(Lattice lattice) {
    _requireSealed();
    return _resolved.where((r) => r.lattice == lattice).toList();
  }

  /// 所有已解析插件（只读，M0 单一事实源）。
  List<ResolvedPlugin> get resolved => List.unmodifiable(_resolved);

  // ═══════ 路由 ═══════

  /// 构建所有模块的路由路径列表（框架层据此创建 GoRoute）。
  List<String> buildRoutePaths() {
    _requireSealed();
    return _modules.expand((m) => m.allRoutePaths).toList();
  }

  // ═══════ 侧边栏导航 ═══════

  /// 按 section 分组的导航条目。
  ///
  /// 分组身份只取决于 section 名（label）；sectionOrder 仅用于组间排序，
  /// 不参与分组相等性——否则同名分组因 sectionOrder 不同会被拆成多组
  /// （如「校园」分组的插件声明 sectionOrder:99 时与默认 50 的 zdbk 系分家）。
  List<(SidebarSection, List<NavEntry>)> get navGroups {
    _requireSealed();
    final grouped = <String, List<NavEntry>>{};
    final sectionOrders = <String, int>{};

    for (final m in _modules) {
      if (!m.hasSidebar) continue;

      final sidebar = m.nav.sidebar;
      if (sidebar == null) continue; // 双保险（hasSidebar 已保证）
      // 防御：有 sidebar 但无 route 的模块（旧版 manifest 残留/无导航入口）
      // 跳过——`m.route!` 会 Null check 崩溃（如 route=null pages=1 的自定义插件）。
      final route = m.route;
      if (route == null) continue;

      grouped.putIfAbsent(sidebar.section, () => []);
      grouped[sidebar.section]!.add(NavEntry(
        icon: m.icon ?? kDefaultIcon,
        label: m.name,
        routePath: route,
        order: sidebar.order,
        moduleId: m.id,
      ));

      // 组排序权重取该分组内最小 sectionOrder（未声明时默认 50）
      final cur = sectionOrders[sidebar.section];
      if (cur == null || sidebar.sectionOrder < cur) {
        sectionOrders[sidebar.section] = sidebar.sectionOrder;
      }

      // V2: secondary nav 是模块内部页面导航，不作为顶级侧边栏条目。
      // 侧边栏每模块只显示 1 个图标；页面切换由 CompositeView 内部 Tab 处理。
    }

    // 每个 section 内按 order 排序
    for (final list in grouped.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    // Section 按最小 sectionOrder 排序
    final sorted = grouped.entries.toList()
      ..sort((a, b) =>
          (sectionOrders[a.key] ?? 50).compareTo(sectionOrders[b.key] ?? 50));
    return sorted
        .map((e) => (
              SidebarSection(e.key, order: sectionOrders[e.key] ?? 50),
              e.value,
            ))
        .toList();
  }

  /// 所有导航条目（扁平列表，用于 collapsed 侧边栏）。
  List<NavEntry> get navFlat {
    _requireSealed();
    return navGroups.expand((g) => g.$2).toList();
  }

  // ═══════ 命令面板 ═══════

  /// 命令面板条目——从模块声明自动生成。
  /// V2: icon 使用 int (codePoint)。
  List<({
    String title,
    String subtitle,
    int icon,
    String route,
    String category
  })> get paletteItems {
    _requireSealed();
    final items = <({
      String title,
      String subtitle,
      int icon,
      String route,
      String category
    })>[];
    for (final m in _modules) {
      if (!m.hasSidebar) continue;
      // 防御：有 sidebar 但无 route 的模块不进命令面板（与 navGroups 一致）。
      final route = m.route;
      if (route == null) continue;
      items.add((
        title: m.name,
        subtitle: route,
        icon: m.icon ?? kDefaultIcon,
        route: m.route!,
        category: m.nav.sidebar!.section,
      ));
      for (final s in m.nav.secondary) {
        items.add((
          title: s.label,
          subtitle: s.routePath,
          icon: s.icon ?? 0xe873, // description
          route: s.routePath,
          category: s.section,
        ));
      }
    }
    return items;
  }

  // ═══════ 依赖校验 ═══════

  void _validateDependencies() {
    final ids = _modules.map((m) => m.id).toSet();
    final errors = <String>[];
    for (final m in _modules) {
      for (final dep in m.dependencies) {
        if (!ids.contains(dep)) {
          errors.add('模块 "${m.id}" 依赖 "$dep"，但 "$dep" 未注册');
        }
      }
    }
    if (errors.isNotEmpty) {
      throw StateError('模块依赖校验失败:\n${errors.join("\n")}');
    }
  }

  void _requireSealed() {
    if (!_sealed) {
      throw StateError(
          'ModuleRegistry 尚未锁定。请在注册所有模块后调用 seal()。');
    }
  }

  // ═══════ 运行时重载（A-P3：插件设计器热重载/安装） ═══════

  /// 运行时重载（[seal] 后仍可用）：反注册旧模块（若存在）并注册新描述符。
  ///
  /// 用于插件设计器"安装 / 热重载"——设计变更后无需重启即可让运行态模块
  /// 与最新 manifest 对齐。返回是否成功。
  ///
  /// 依赖缺失时返回 `false` 且**不修改任何状态**（保护现有运行态不被破坏）。
  bool reloadModule(ModuleDescriptor descriptor) {
    // 依赖校验（在修改状态前完成，避免部分写入导致不一致）
    final ids = <String>{..._modules.map((m) => m.id), descriptor.id};
    for (final dep in descriptor.dependencies) {
      if (!ids.contains(dep)) {
        Log().warn('reloadModule 依赖缺失，放弃重载',
            data: {'id': descriptor.id, 'missing': dep});
        return false;
      }
    }

    // 移除旧（同 id），再追加新描述符
    _modules.removeWhere((m) => m.id == descriptor.id);
    _resolved.removeWhere((r) => r.id == descriptor.id);
    _capabilities.remove(descriptor.id);
    _modules.add(descriptor);
    _resolved.add(ResolvedPlugin.fromDescriptor(descriptor));

    Log().info('ModuleRegistry reloaded: ${descriptor.id} '
        '（seal=$_sealed，当前模块数 ${_modules.length}）');
    return true;
  }

  /// 反注册模块（[seal] 后仍可用）。返回是否成功移除。
  ///
  /// 供插件卸载 / 重载前置清理使用。
  bool unregister(String id) {
    final before = _modules.length;
    _modules.removeWhere((m) => m.id == id);
    _resolved.removeWhere((r) => r.id == id);
    _capabilities.remove(id);
    final removed = _modules.length < before;
    if (removed) {
      Log().info('ModuleRegistry unregistered: $id');
    }
    return removed;
  }
}

// ═══════ NavEntry ═══════

/// 侧边栏导航条目（框架层从 [ModuleDescriptor] 生成）。
/// V2: icon 使用 int (codePoint)。
class NavEntry {
  final int icon;
  final String label;
  final String routePath;
  final int order;

  /// 所属模块 ID，用于反查模块的 renderMode 等元信息。
  final String moduleId;

  const NavEntry({
    required this.icon,
    required this.label,
    required this.routePath,
    this.order = 50,
    this.moduleId = '',
  });
}

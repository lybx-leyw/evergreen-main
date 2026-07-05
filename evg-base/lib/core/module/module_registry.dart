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
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/log.dart';
import 'capability.dart';
import 'module_descriptor.dart';
import 'plugin_manifest.dart';
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
  bool _sealed = false;

  // ═══════ 注册 ═══════

  /// 注册一个模块。必须在 [seal] 之前调用。
  void register(ModuleDescriptor module) {
    if (_sealed) {
      throw StateError('ModuleRegistry 已锁定，不能再注册模块。'
          ' 请在 seal() 之前注册所有模块。');
    }
    final dup = _modules.any((m) => m.id == module.id);
    if (dup) {
      throw ArgumentError('模块 id "${module.id}" 重复，请检查。');
    }
    _modules.add(module);
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
  /// 匹配 [ModuleDescriptor.route]、[LayoutDescriptor.panels] 路径、
  /// [NavDescriptor.routePath]、以及 composite 模式下 [PageDescriptor] 子路由。
  /// 返回 `null` 表示无匹配模块。
  ModuleDescriptor? findByRoute(String path) {
    _requireSealed();
    for (final m in _modules) {
      if (m.route == path) return m;
      for (final panel in m.layout.panels) {
        if (panel.path == path) return m;
      }
      for (final nav in m.secondaryNavs) {
        if (nav.routePath == path) return m;
      }
      // composite 模式：page 子路由
      if (m.ui == 'composite' && m.route != null) {
        for (final page in m.pages) {
          if ('${m.route}/${page.id}' == path) return m;
        }
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
        return m.sidebar?.section == cat;
      });
    }

    return results.map((m) {
      return PluginManifest(
        id: m.id,
        name: m.name,
        description: m.description,
        icon: m.icon,
        dimensions: _capabilities[m.id] ?? [],
        category: m.sidebar?.section ?? '',
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

  // ═══════ 路由 ═══════

  /// 构建所有模块的路由路径列表（框架层据此创建 GoRoute）。
  List<String> buildRoutePaths() {
    _requireSealed();
    return _modules.expand((m) => m.allRoutePaths).toList();
  }

  // ═══════ 侧边栏导航 ═══════

  /// 按 section 分组的导航条目。
  List<(SidebarSection, List<NavEntry>)> get navGroups {
    _requireSealed();
    final grouped = <SidebarSection, List<NavEntry>>{};

    for (final m in _modules) {
      if (!m.hasSidebar) continue;

      final sec = SidebarSection(
        m.sidebar!.section,
        order: m.sidebar!.sectionOrder,
      );
      final route = m.route!;

      grouped.putIfAbsent(sec, () => []);
      grouped[sec]!.add(NavEntry(
        icon: m.icon!,
        label: m.name,
        routePath: route,
        order: m.sidebar!.order,
      ));

      // 子导航条目
      for (final s in m.secondaryNavs) {
        final subSec = SidebarSection(s.section);
        grouped.putIfAbsent(subSec, () => []);
        grouped[subSec]!.add(NavEntry(
          icon: s.icon ?? Icons.article,
          label: s.label,
          routePath: s.routePath,
          order: 50,
        ));
      }
    }

    // 每个 section 内按 order 排序
    for (final list in grouped.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }

    // Section 按 order 排序
    final sorted = grouped.entries.toList()
      ..sort((a, b) => a.key.order.compareTo(b.key.order));
    return sorted.map((e) => (e.key, e.value)).toList();
  }

  /// 所有导航条目（扁平列表，用于 collapsed 侧边栏）。
  List<NavEntry> get navFlat {
    _requireSealed();
    return navGroups.expand((g) => g.$2).toList();
  }

  // ═══════ 命令面板 ═══════

  /// 命令面板条目——从模块声明自动生成。
  List<({
    String title,
    String subtitle,
    IconData icon,
    String route,
    String category
  })> get paletteItems {
    _requireSealed();
    final items = <({
      String title,
      String subtitle,
      IconData icon,
      String route,
      String category
    })>[];
    for (final m in _modules) {
      if (!m.hasSidebar) continue;
      items.add((
        title: m.name,
        subtitle: m.route!,
        icon: m.icon!,
        route: m.route!,
        category: m.sidebar!.section,
      ));
      for (final s in m.secondaryNavs) {
        items.add((
          title: s.label,
          subtitle: s.routePath,
          icon: s.icon ?? Icons.article,
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
}

// ═══════ NavEntry ═══════

/// 侧边栏导航条目（框架层从 [ModuleDescriptor] 生成）。
class NavEntry {
  final IconData icon;
  final String label;
  final String routePath;
  final int order;

  const NavEntry({
    required this.icon,
    required this.label,
    required this.routePath,
    this.order = 50,
  });
}

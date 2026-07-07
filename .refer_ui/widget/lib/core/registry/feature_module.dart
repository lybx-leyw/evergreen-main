import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'sidebar_section.dart';

/// 一个功能模块的完整声明。
///
/// 每个 feature 目录下放 `module.dart`，定义一个 [FeatureModule] 子类，
/// 然后在应用启动时注册到 [ModuleRegistry]。
///
/// 模块作者**只需**：
/// 1. 建目录 + 写代码
/// 2. 实现此接口
/// 3. 在注册点加一行 `reg.register(MyModule())`
///
/// 不需要改 sidebar、app.dart、command_palette、connection_manager 等文件。
abstract class FeatureModule {
  // ═══════════════════════════════════════════════════════════
  // 必填：模块身份
  // ═══════════════════════════════════════════════════════════

  /// 唯一标识，如 `'palace'`、`'courses'`。用于依赖声明和查找。
  String get id;

  /// 显示名称，如 `'宫殿'`、`'课程'`。
  String get name;

  // ═══════════════════════════════════════════════════════════
  // 可选：导航（不覆写 → 不出现在侧边栏）
  // ═══════════════════════════════════════════════════════════

  /// 侧边栏图标。
  IconData? get icon => null;

  /// 侧边栏所属分类。
  SidebarSection? get sidebarSection => null;

  /// 侧边栏排序权重（同 section 内越小越靠前）。
  int get sidebarOrder => 50;

  /// 侧边栏角标 Provider（如待办数、即将考试数）。
  /// 返回 null 表示不需要角标。
  ProviderListenable<int?>? get sidebarBadgeProvider => null;

  /// 模块额外声明的侧边栏条目（用于一个模块有多个页面时）。
  /// 如 zdbk 模块有"教务通知""开课情况""培养方案"三个独立导航。
  List<NavEntryDecl> get secondaryNavs => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：路由
  // ═══════════════════════════════════════════════════════════

  /// 模块的路由列表。
  /// 返回 [] 表示没有 UI 页面（纯服务模块）。
  List<RouteBase> buildRoutes() => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：依赖
  // ═══════════════════════════════════════════════════════════

  /// 依赖的其他模块 [id] 列表。
  /// 框架在注册时校验所有依赖存在，缺失则报错。
  List<String> get dependsOn => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：提供者导出（供其他模块通过 Registry 获取）
  // ═══════════════════════════════════════════════════════════

  /// 对外暴露的 Provider 列表。
  /// 其他模块不直接 import 本模块的实现文件，而是通过
  /// `ModuleRegistry.exports<PalaceModule>()` 获取。
  List<ProviderBase<Object?>> get exports => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：自动登录 / 连通性检查
  // ═══════════════════════════════════════════════════════════

  /// 如果需要自动登录检查，覆写此方法。
  /// 返回 null 表示不需要（默认）。
  ConnectivityDecl? get connectivityDecl => null;

  // ═══════════════════════════════════════════════════════════
  // 可选：数据源声明（DataStatus 面板）
  // ═══════════════════════════════════════════════════════════

  /// 数据源列表，用于 DataStatusManager 面板。
  List<DataSourceDecl> get dataSources => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：命令面板
  // ═══════════════════════════════════════════════════════════

  /// 命令面板搜索条目（不覆写则自动从 icon/name/routePath 生成一个条目）。
  List<PaletteItemDecl> get paletteItems => [];

  // ═══════════════════════════════════════════════════════════
  // 可选：Agent 工具
  // ═══════════════════════════════════════════════════════════

  /// 模块提供的 Agent 工具工厂列表。
  List<AgentToolDecl> get agentTools => [];
}

// ═══════════════════════════════════════════════════════════
// 附属声明类型
// ═══════════════════════════════════════════════════════════

/// 连通性检查声明（由 [FeatureModule.connectivityDecl] 返回）。
class ConnectivityDecl {
  final String serviceName;

  /// 检查函数。
  /// 返回 true 表示连接成功，返回 false 或 throw 表示失败。
  final Future<bool> Function() check;

  const ConnectivityDecl({
    required this.serviceName,
    required this.check,
  });
}

/// 数据源声明（用于 DataStatus 面板）。
class DataSourceDecl {
  final String name;
  final String category;

  /// 提供刷新能力（可选）。
  final Future<void> Function()? onRefresh;

  const DataSourceDecl({
    required this.name,
    required this.category,
    this.onRefresh,
  });
}

/// 额外的侧边栏导航条目（用于一个模块有多个独立页面时）。
class NavEntryDecl {
  final IconData icon;
  final String label;
  final String routePath;
  final SidebarSection section;
  final int order;
  final ProviderListenable<int?>? badgeProvider;

  const NavEntryDecl({
    required this.icon,
    required this.label,
    required this.routePath,
    required this.section,
    this.order = 50,
    this.badgeProvider,
  });
}

/// 命令面板条目（用于 Ctrl+K 搜索）。
class PaletteItemDecl {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final String category;

  const PaletteItemDecl({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.category,
  });
}

/// Agent 工具声明。
class AgentToolDecl {
  final String name;
  final dynamic Function() factory; // 返回 Tool 实例的工厂函数

  const AgentToolDecl({
    required this.name,
    required this.factory,
  });
}

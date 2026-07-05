import 'package:flutter/widgets.dart';

/// 侧边栏分类——与现有 section 结构一致。
enum SidebarSection {
  /// 学习
  learning('学习'),

  /// AI 工具
  aiTools('AI 工具'),

  /// 校园
  campus('校园'),

  /// 系统
  system('系统');

  const SidebarSection(this.label);
  final String label;
}

/// 模块声明的导航条目。
///
/// 用于 [FeatureModule.navDecl] ，框架层收集所有模块的声明后自动生成
/// 侧边栏（collapsed / expanded / mobile drawer / mobile bottom nav）。
class NavDecl {
  final IconData icon;
  final String label;
  final String routePath;

  /// 在所属 section 内的排序权重（越小越靠前）。
  final int order;

  const NavDecl({
    required this.icon,
    required this.label,
    required this.routePath,
    this.order = 50,
  });
}

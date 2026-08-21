/// 插件市场统一插件信息模型（不局限于 module，覆盖 config/agent/data/theme 等）。
library;

import 'package:flutter/material.dart';

/// 本地插件（manifest）的轻量展示/管理模型。
///
/// 与领域层 [ModuleDescriptor] 解耦：marketplace 需要展示所有类型的插件
/// （module / agent / data-source / config / theme ...），而 [ModuleDescriptor]
/// 仅描述 module 类型。这里统一承载 id/name/type/目录等管理所需字段，
/// 让市场不再「只显示 module」。
class PluginInfo {
  const PluginInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    this.version,
    this.iconCode,
    required this.dirPath,
    required this.isModule,
    required this.hasSidebar,
    required this.pageCount,
    this.isBuiltin = false,
    this.section = '未分组',
    this.sectionOrder = 50,
    this.order = 50,
  });

  /// 稳定标识：优先 manifest.id，缺失时回退文件夹名（保证 state/uninstall 有 key）。
  final String id;
  final String name;
  final String description;
  /// manifest 原始 type，如 'module' / 'data-source' / 'agent' / 'config' / 'theme'。
  final String type;
  final String? version;
  final int? iconCode;
  /// 插件在磁盘上的真实文件夹路径（卸载时精确删除用）。
  final String dirPath;
  /// 是否为 module 类型（决定是否能启用/隐藏侧栏）。
  final bool isModule;
  /// module 是否在侧边栏有入口（nav.sidebar != null）。
  final bool hasSidebar;
  /// module 的页面数（非 module 为 0）。
  final int pageCount;
  /// 是否为内置模块（随应用分发，非 plugins/ 目录插件）——不可卸载。
  /// 内置模块由启动期注册进 ModuleRegistry（如 zju 9 个校园模块），
  /// 市场合并展示时置 true，卡片隐藏「卸载」按钮。
  final bool isBuiltin;
  /// 所属侧边栏分组名（manifest `nav.sidebar.section`；无侧栏时回退「未分组」）。
  /// 插件中心「分组排序」与侧边栏组名开关共用此分组。
  final String section;
  /// 分组间的 manifest 排序权重（`nav.sidebar.sectionOrder`，默认 50）。
  /// 用户未拖拽分组时，分组按此值排序。
  final int sectionOrder;
  /// 组内的 manifest 排序权重（`nav.sidebar.order`，默认 50）。
  /// 用户未拖拽插件时，组内按此值排序。
  final int order;

  /// 根据插件类型返回展示图标（manifest 无 icon 时回退）。
  IconData get typeIcon {
    switch (type) {
      case 'module':
        return Icons.extension;
      case 'agent':
        return Icons.smart_toy;
      case 'data-source':
      case 'data':
        return Icons.storage;
      case 'config':
        return Icons.settings;
      case 'theme':
        return Icons.palette;
      default:
        return Icons.extension;
    }
  }

  /// 类型的中文标签（卡片展示用）。
  String get typeLabel {
    switch (type) {
      case 'module':
        return '模块';
      case 'agent':
        return 'Agent';
      case 'data-source':
      case 'data':
        return '数据源';
      case 'config':
        return '配置';
      case 'theme':
        return '主题';
      default:
        return type.isEmpty ? '未知' : type;
    }
  }
}

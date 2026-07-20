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
  });

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

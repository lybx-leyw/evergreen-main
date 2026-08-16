/// scraper-modle 模板入口（v5P · Phase 2 多画板化）。
///
/// 独立 modle：爬虫直接全屏渲染 BoardContainerView（多画板容器），
/// 不再走 v4_modle 的 slot 分派 + SCSV 约束链，彻底解决 SCSV 丢弃 bounded
/// 约束 → Expanded 塌缩为 0 → WebView 黑屏的问题。
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';
import 'board/board_container_view.dart';
import 'board/board_paths.dart';

/// 爬虫模板渲染器。
///
/// 爬虫只有一个组件且独占全屏，不需要 slot/layout/pages 分派。直接渲染
/// [BoardContainerView]，由 MaterialApp 的 ShellRoute 提供真实的 bounded
/// 约束（MediaQuery），WebView 自然填满全屏。
class ScraperTemplate extends ModleRenderer {
  const ScraperTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    return BoardContainerView(
      descriptor: descriptor,
      config: const ComponentDescriptor(
        type: 'scraper-generator',
        config: {},
      ),
      slotKey: 'scraper',
      projectRoot: findProjectRoot(),
      workspaceDir: scraperWorkspaceDir(descriptor.id),
    );
  }
}

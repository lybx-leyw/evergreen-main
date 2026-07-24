/// 论文阅读模板 — ModleRenderer 入口。
///
/// 将 "paper_reading" → ModleRenderer.build → PaperReadingView。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/renderer/templates/template.dart';
import 'paper_reading_view.dart';

/// 论文阅读模板渲染器。
///
/// 注册到 TemplateRegistry 后，manifest.template = 'paper_reading' 的模块
/// 将由此渲染器接管。整个模板自成体系，内部使用 Riverpod 状态管理 +
/// 自定义视图导航栈（不依赖 Navigator）。
class PaperReadingModleTemplate extends ModleRenderer {
  const PaperReadingModleTemplate();

  @override
  Widget build(
    BuildContext context, {
    required ModuleDescriptor descriptor,
    String? workingDirectory,
  }) {
    // debugPrint('[paper_reading] build template, workingDir=$workingDirectory');
    return ProviderScope(
      child: PaperReadingView(
        descriptor: descriptor,
        workingDirectory: workingDirectory,
      ),
    );
  }
}

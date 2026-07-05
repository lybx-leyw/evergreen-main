/// UI 范式调度器——根据 [ModuleDescriptor.ui] 返回对应视图。
///
/// 公开类：[ModuleDispatch]
///
/// | switch 值 | 视图 |
/// |----------|------|
/// | `default` | [DefaultView] |
/// | `chat` | [ChatControllerView] |
/// | `settings` | [SettingsView] |
/// | `spreadsheet` | [SpreadsheetView] |
/// | `document` | [DocumentView] |
/// | `presentation` | [PresentationView] |
/// | `dashboard` | [DashboardView] |
/// | `editor` | [EditorView] |
/// | `composite` | [CompositeView] |
/// | `multichat` | [MultiAgentView] |
/// | _unknown_ | 静默回退到 [DefaultView] |
import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'default_view.dart';
import 'chat_controller_view.dart';
import 'settings_view.dart';
import 'spreadsheet_view.dart';
import 'document_view.dart';
import 'presentation_view.dart';
import 'dashboard_view.dart';
import 'editor_view.dart';
import 'composite_view.dart';
import '../multi_agent/multi_agent_view.dart';

/// UI 范式调度器——纯 switch，不自行判断条件。
/// 未知 ui 值静默回退到 [DefaultView]。
///
/// [workingDirectory] 仅当 ui 为 `composite` 时透传给 [CompositeView]，
/// 用于进程生命周期管理。其余范式忽略此参数。
class ModuleDispatch extends StatelessWidget {
  final ModuleDescriptor descriptor;
  final String? workingDirectory;

  const ModuleDispatch({
    super.key,
    required this.descriptor,
    this.workingDirectory,
  });

  @override
  Widget build(BuildContext context) {
    return switch (descriptor.ui) {
      'chat' => ChatControllerView(descriptor: descriptor),
      'settings' => SettingsView(descriptor: descriptor),
      'spreadsheet' => SpreadsheetView(descriptor: descriptor),
      'document' => DocumentView(descriptor: descriptor),
      'presentation' => PresentationView(descriptor: descriptor),
      'dashboard' => DashboardView(descriptor: descriptor),
      'editor' => EditorView(descriptor: descriptor),
      'composite' => CompositeView(
          descriptor: descriptor,
          workingDirectory: workingDirectory,
        ),
      'multichat' => const MultiAgentView(),
      _ => DefaultView(descriptor: descriptor), // 'default' + 未知值
    };
  }
}

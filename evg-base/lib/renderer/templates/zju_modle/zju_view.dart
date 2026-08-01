/// zju 统一模板主视图——教室录播回看 + 教务数据双 UI 家族路由器。
///
/// 由 classroom_modle（录播回看）与 zdbk_modle（教务六页）合并而来，
/// 按模块 manifest 声明自动分派：
///
/// | manifest 声明 | → 视图 |
/// |---|---|
/// | `modleRoute: 'classroom'`，或未声明 modleRoute 但声明了模块级 `dataSource`（教室老形态） | [ClassroomView]（录播回看：视频 + PPT + 字幕） |
/// | `modleRoute: score/exams/timetable/course_offerings/training_plans/notifications` 或空 | [ZdbkView]（教务页，内部按 modleRoute 继续分派） |
library;

import 'package:flutter/widgets.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

import 'classroom/classroom_view.dart';
import 'zdbk/zdbk_view.dart';

/// zju 统一模板主视图（无 Scaffold：桌面端模块内容区无 per-module AppBar，
/// 两家族视图均自带页面标题，与合并前的 classroom_modle / zdbk_modle 一致）。
class ZjuModleView extends StatelessWidget {
  /// 模块描述符（含 modleRoute / dataSource / dataSources 声明）。
  final ModuleDescriptor descriptor;

  /// 模块 id（用于相对资源路径解析）。
  final String moduleId;

  /// 插件根目录（资源根）。
  final String? pluginsDir;

  const ZjuModleView({
    super.key,
    required this.descriptor,
    required this.moduleId,
    this.pluginsDir,
  });

  @override
  Widget build(BuildContext context) {
    final route = descriptor.modleRoute;
    // 教室形态：显式 modleRoute='classroom'，或兼容老插件（无 modleRoute 但声明了
    // 模块级单数据源 dataSource——原 classroom 插件只声明这一个字段）。
    final isClassroom = route == 'classroom' ||
        (route == null && descriptor.dataSource != null);
    if (isClassroom) {
      return ClassroomView(
        dataSource: descriptor.dataSource,
        moduleId: moduleId,
        pluginsDir: pluginsDir,
      );
    }
    // 教务形态：交给 ZdbkView 按 modleRoute（score/exams/.../空）继续分派。
    return ZdbkView(
      descriptor: descriptor,
      moduleId: moduleId,
      pluginsDir: pluginsDir,
    );
  }
}

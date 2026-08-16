/// zju 统一模板主视图——6 个校园 feature 分派路由器（B2 删旧后骨架）。
///
/// B2（2026-08-12）已删除旧实现：`classroom/`（录播回看）与 `zdbk/`（教务六页）
/// 整体移除，`plugins/data-zdbk/`（scraper.py + manifest + config）同步删除，
/// 凭证已迁移至 settings（ZJU_USERNAME / ZJU_PASSWORD，B1 完成）。
///
/// 按模块 manifest 声明自动分派：
///
/// | modleRoute | → 视图 |
/// |---|---|
/// | courses | [CoursesView]（我的课程 + 周课表） |
/// | scores | [ScoresView]（成绩 + GPA 仪表盘） |
/// | exams | [ExamsView]（考试安排） |
/// | zdbk | [ZdbkView]（教务中心：开课情况/培养方案/教务通知，TabBar 三页） |
/// | classroom | [ClassroomView]（智云课堂录播回看） |
/// | teachers | [TeachersView]（查老师评价） |
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';

import 'classroom/screens/classroom_screen.dart';
import 'courses/screens/courses_screen.dart';
import 'exams/screens/exams_screen.dart';
import 'scores/screens/scores_screen.dart';
import 'teachers/screens/teachers_screen.dart';
import 'zdbk/zdbk_view.dart';

/// zju 统一模板主视图（无 Scaffold：桌面端模块内容区无 per-module AppBar，
/// 各 feature 页面自带标题，符合 evg-base 桌面规范）。
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
    // 按 route 分派到对应视图；未知 route 走兜底（防御，不崩溃）。
    switch (route) {
      case 'courses':
        return const CoursesView();
      case 'scores':
        return const ScoresView();
      case 'exams':
        return const ExamsView();
      case 'zdbk':
        return const ZdbkView();
      case 'classroom':
        return const ClassroomView();
      case 'teachers':
        return const TeachersView();
      default:
        return _UnderConstruction(
          route: route ?? '(未声明 modleRoute)',
          moduleName: descriptor.name,
        );
    }
  }
}

/// 未知 modleRoute 兜底视图（防御：未来新增模块未注册分派时显示，不崩溃）。
class _UnderConstruction extends StatelessWidget {
  final String route;
  final String moduleName;

  const _UnderConstruction({required this.route, required this.moduleName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(moduleName, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            '模块未知（zju / $route）',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// 教务中心视图（zju / zdbk）——开课情况 / 培养方案 / 教务通知 三页容器。
///
/// B3-zdbk（2026-08-12）：zdbk 模块（modleRoute='zdbk'）内部用 TabBar 组织
/// 三个子页（成绩分布/主修/实践成绩由 scores 覆盖，不在此列）。
/// 无 Scaffold（evg-base 桌面规范：模块区无 per-module AppBar）。
library;

import 'package:flutter/material.dart';

import 'screens/course_offerings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/training_plans_screen.dart';

/// 教务中心：TabBar 切换三个数据源页面。
class ZdbkView extends StatelessWidget {
  const ZdbkView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('教务中心', style: Theme.of(context).textTheme.titleLarge),
          ),
          const TabBar(
            tabs: [
              Tab(text: '开课情况'),
              Tab(text: '培养方案'),
              Tab(text: '教务通知'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                CourseOfferingsView(),
                TrainingPlansView(),
                NotificationsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ZDBK 教务主视图——「成绩 / 课程 / 其他」三维路由。
///
/// 数据来源：8 类 `orch://zdbk_*` 经 [resolveDataSource]（数据中枢）拉取，
/// 不再内嵌或直连教务。各子页面（grades/courses/notifications）自行按需
/// 拉取对应类型，照搬 `.reference` 的 zdbk 页面 UI 逻辑。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/providers.dart';
import 'package:evergreen_base/renderer/atomic/data_source_resolver.dart';

import 'screens/grades_page.dart';
import 'screens/exams_page.dart';
import 'screens/timetable_page.dart';
import 'screens/course_offerings_page.dart';
import 'screens/training_plans_page.dart';
import 'screens/notifications_page.dart';

/// 按声明式多数据源（命名 source → DataSourceDescriptor）顺序解析，
/// 返回 源名 → 原始数据 的映射。
///
/// 顺序 + 间隔拉取以降低对教务 CAS 的并发登录压力（冷缓存时每个类型都触发一次
/// 真实 scraper 登录；并发会被 ZJU CAS 节流，ticket 被拒落在 login_slogin）。
/// 单类型异常由 [resolveDataSource] 内部降级为 null，此处兜底为 null。
Future<Map<String, dynamic>> zdbkResolve(
  WidgetRef ref,
  Map<String, DataSourceDescriptor> sources,
) async {
  debugPrint('[zdbkResolve] 开始，sources 键数: ${sources.length}');
  final out = <String, dynamic>{};
  for (final entry in sources.entries) {
    debugPrint('[zdbkResolve] 处理 source="${entry.key}", endpoint="${entry.value.endpoint}"');
    try {
      out[entry.key] = await resolveDataSource(
        ds: entry.value,
        orch: ref.read(dataOrchestratorProvider),
      );
      debugPrint('[zdbkResolve] source="${entry.key}" 完成: ${out[entry.key] != null ? "有数据" : "NULL"}');
    } catch (e) {
      debugPrint('[zdbkResolve] source="${entry.key}" 异常: $e');
      out[entry.key] = null;
    }
    // 轻微间隔，规避教务 CAS 对连续登录的软限流（与 scraper 重试退避互补）。
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return out;
}

/// ZDBK 教务模板主视图（无 Scaffold：桌面端模块内容区无 per-module AppBar，
/// 各子页自带页面标题头，与 classroom_modle 一致；内部仅按
/// [ModuleDescriptor.modleRoute] 分发到对应子视图）。
///
/// 子视图所需数据由各消费方模块在 manifest 的 `dataSources` 中声明（orch://<type>），
/// 经 [zdbkResolve] 拉取后按 source 名传入；模板内部不硬编码任何 zdbk 类型清单。
class ZdbkView extends ConsumerStatefulWidget {
  /// 模块描述符（含 modleRoute 与 dataSources 声明）。
  final ModuleDescriptor descriptor;
  final String moduleId;
  final String? pluginsDir;

  const ZdbkView({
    super.key,
    required this.descriptor,
    required this.moduleId,
    this.pluginsDir,
  });

  @override
  ConsumerState<ZdbkView> createState() => _ZdbkViewState();
}

class _ZdbkViewState extends ConsumerState<ZdbkView> {
  @override
  Widget build(BuildContext context) {
    final sources = widget.descriptor.dataSources ?? const {};
    switch (widget.descriptor.modleRoute) {
      case 'exams':
        return ExamsPage(ref: ref, sources: sources);
      case 'timetable':
        return TimetablePage(ref: ref, sources: sources);
      case 'course_offerings':
        return CourseOfferingsPage(ref: ref, sources: sources);
      case 'training_plans':
        return TrainingPlanPage(ref: ref, sources: sources);
      case 'notifications':
        return NotificationsPage(ref: ref, sources: sources);
      case 'score':
      default:
        return GradesPage(ref: ref, sources: sources);
    }
  }
}

/// 统一空态。
Widget zdbkEmpty(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48,
                color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );

/// 统一错误态（含重试）。
Widget zdbkError(String msg, VoidCallback onRetry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(msg, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                onPressed: onRetry),
          ],
        ),
      ),
    );

/// 统一的页面标题头。
///
/// 桌面端模块内容区无 per-module AppBar，各 zdbk 子页需自带标题，
/// 对齐参考各屏的 `AppBar(title)`，保证每个 module 自身 UI 有清晰标题、左右对齐。
Widget zdbkPageHeader(BuildContext context, String title) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title,
        style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
  );
}

/// 统一的小节标题（带数据计数），所有子页共用以保证对齐。
Widget zdbkSectionTitle(BuildContext context, String title, int count) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text('$title ($count)',
        style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
  );
}

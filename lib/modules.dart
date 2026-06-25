import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/registry/modules.dart';
import 'core/log.dart';

// ═══════════════════════════════════════════════════════
// 模块声明 —— 每人一行
// ═══════════════════════════════════════════════════════

// 基础模块（无依赖）
import 'features/auth/module.dart';
import 'features/agent/module.dart';

// 学习模块
import 'features/courses/module.dart';
import 'features/todo/module.dart';
import 'features/plan/module.dart';
import 'features/scores/module.dart';
import 'features/exams/module.dart';
import 'features/downloads/module.dart';

// AI 工具模块
import 'features/tutor/module.dart';
import 'features/translate/module.dart';
import 'features/classroom/module.dart';
import 'features/wordpecker/module.dart';
import 'features/quiz/module.dart';

// 校园模块
import 'features/zdbk/module.dart';
import 'features/pintia/module.dart';
import 'features/teachers/module.dart';
import 'features/schedule/module.dart';
import 'features/library/module.dart';
import 'features/ecard/module.dart';
import 'features/autosign/module.dart';
import 'features/rvpn/module.dart';

// 系统模块
import 'features/palace/module.dart';
import 'features/connectivity/module.dart';
import 'features/scheduler/module.dart';
import 'features/settings/module.dart';

/// 全局模块注册中心 Provider。
///
/// 所有模块在此注册（每人一行），框架自动从中生成：
/// - GoRouter 路由表
/// - 侧边栏导航（4 种形态）
/// - 命令面板搜索条目
/// - 连通性检查列表
/// - Agent 工具列表
final moduleRegistryProvider = Provider<ModuleRegistry>((ref) {
  final registry = ModuleRegistry();

  // ═══════════════════════════════════════════════════
  // 基础模块（被其他模块依赖，先注册）
  // ═══════════════════════════════════════════════════
  registry.register(AuthModule());
  registry.register(AgentModule());

  // ═══════════════════════════════════════════════════
  // 学习
  // ═══════════════════════════════════════════════════
  registry.register(CoursesModule());
  registry.register(TodoModule());
  registry.register(PlanModule());
  registry.register(ScoresModule());
  registry.register(ExamsModule());
  registry.register(DownloadsModule());

  // ═══════════════════════════════════════════════════
  // AI 工具
  // ═══════════════════════════════════════════════════
  registry.register(TutorModule());
  registry.register(TranslateModule());
  registry.register(ClassroomModule());
  registry.register(WordpeckerModule());
  registry.register(QuizModule());

  // ═══════════════════════════════════════════════════
  // 校园
  // ═══════════════════════════════════════════════════
  registry.register(ZdbkModule());
  registry.register(PintiaModule());
  registry.register(TeachersModule());
  registry.register(ScheduleModule());
  registry.register(LibraryModule());
  registry.register(EcardModule());
  registry.register(AutosignModule());
  registry.register(RvpnModule());

  // ═══════════════════════════════════════════════════
  // 系统
  // ═══════════════════════════════════════════════════
  registry.register(PalaceModule());
  registry.register(ConnectivityModule());
  registry.register(SchedulerModule());
  registry.register(SettingsModule());

  registry.seal();
  Log().info('ModuleRegistry: ${registry.modules.length} modules registered');
  return registry;
});

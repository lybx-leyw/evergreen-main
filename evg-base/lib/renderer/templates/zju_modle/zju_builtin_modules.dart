/// zju 内置模块注册（B4）——6 个校园 feature 的 [ModuleDescriptor] 工厂。
///
/// 规划决策 3（激活方式）：内置模块注册，不再扫描 plugins/*.json。
/// 由 [AppBootstrap._stepModules]（app_bootstrap.dart）在扫描外部插件后、
/// `registry.seal()` 前调用 [registerZjuBuiltinModules]，6 个模块进入
/// [ModuleRegistry] → 侧边栏/路由/命令面板由现有注册中心自动生成
/// （不改 app_shell / app / go_router）。
///
/// 渲染链路：`template: 'zju'` → TemplateRegistry → ZjuModleTemplate →
/// ZjuModleView 按 `modleRoute` 分派到各 feature 视图（zju_view.dart）。
///
/// 侧边栏分组：
/// - 浙大·学习（sectionOrder 30）：courses / scores / exams
/// - 浙大·校园（sectionOrder 40）：zdbk / classroom / teachers
library;

import 'package:evergreen_base/core/module/module_descriptor.dart';
import 'package:evergreen_base/core/module/module_registry.dart';

/// 6 个内置模块列表（顺序即注册顺序）。
///
/// icon 为 Material Icons codePoint（与 core/module_descriptor.dart 的
/// `_iconMap` 保持一致，避免依赖 Flutter material 保证 core 纯 Dart 边界）。
List<ModuleDescriptor> zjuBuiltinModules() => const [
  // ── 浙大·学习 ──
  ModuleDescriptor(
    id: 'zju-courses',
    name: '我的课程',
    description: '本学期课程列表 + 周课表（SSO 直连教务，数据中枢缓存）',
    icon: 0xe80c, // Icons.school
    version: '2.0.0',
    route: '/zju-courses',
    template: 'zju',
    modleRoute: 'courses',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·学习', sectionOrder: 30, order: 10),
    ),
  ),
  ModuleDescriptor(
    id: 'zju-scores',
    name: '我的成绩',
    description: '成绩查询 + GPA 仪表盘（数据中枢 zju_scores）',
    icon: 0xf0a5, // Icons.assessment
    version: '2.0.0',
    route: '/zju-scores',
    template: 'zju',
    modleRoute: 'scores',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·学习', sectionOrder: 30, order: 20),
    ),
  ),
  ModuleDescriptor(
    id: 'zju-exams',
    name: '考试安排',
    description: '考试日程安排（数据中枢 zju_exams）',
    icon: 0xe878, // Icons.event
    version: '2.0.0',
    route: '/zju-exams',
    template: 'zju',
    modleRoute: 'exams',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·学习', sectionOrder: 30, order: 30),
    ),
  ),
  // ── 浙大·校园 ──
  ModuleDescriptor(
    id: 'zju-zdbk',
    name: '教务中心',
    description: '开课情况 / 培养方案 / 教务通知（数据中枢 zju_zdbk_*）',
    icon: 0xe871, // Icons.dashboard
    version: '2.0.0',
    route: '/zju-zdbk',
    template: 'zju',
    modleRoute: 'zdbk',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·校园', sectionOrder: 40, order: 10),
    ),
  ),
  ModuleDescriptor(
    id: 'zju-classroom',
    name: '智云课堂',
    description: '智云课堂录播回看 + PPT / 字幕（视频直连，元数据走中枢）',
    icon: 0xea19, // Icons.menu_book
    version: '2.0.0',
    route: '/zju-classroom',
    template: 'zju',
    modleRoute: 'classroom',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·校园', sectionOrder: 40, order: 20),
    ),
  ),
  ModuleDescriptor(
    id: 'zju-teachers',
    name: '查老师',
    description: '教师评价查询（内置数据集，数据中枢 zju_teachers）',
    icon: 0xe7ef, // Icons.group
    version: '2.0.0',
    route: '/zju-teachers',
    template: 'zju',
    modleRoute: 'teachers',
    nav: NavObjectDescriptor(
      sidebar: SidebarDescriptor(
          section: '浙大·校园', sectionOrder: 40, order: 30),
    ),
  ),
];

/// 把 6 个 zju 内置模块注册进 [registry]。
///
/// 必须在 [ModuleRegistry.seal] 之前调用（启动期 _stepModules）。
/// 幂等：已存在同 id（如外部插件撞名）则跳过该模块，不抛异常。
void registerZjuBuiltinModules(ModuleRegistry registry) {
  final registered = <String>{};
  for (final m in zjuBuiltinModules()) {
    if (registered.contains(m.id)) {
      continue; // 同 id 重复定义，跳过（防御，理论上不发生）
    }
    try {
      registry.register(m);
      registered.add(m.id);
    } catch (e) {
      // id 重复（与外部插件 manifest 撞名）→ 跳过该模块，其余继续注册
      // ignore: avoid_print
      print('[ZJU-BUILTIN] 注册 ${m.id} 失败（可能 id 冲突，已跳过）: $e');
    }
  }
}

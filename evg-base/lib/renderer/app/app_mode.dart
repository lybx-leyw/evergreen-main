/// 三模式视图（AI 视图 / 开发者模式 / 插件视图）——模式枚举、持久化 Provider 与导航过滤。
///
/// 设计依据：《三模式视图重构_实施计划.md》（根目录）。
///
/// - 模式切换：左栏顶部视图图标 → 扇形菜单（mode_rail.dart），点击即切换；
/// - 持久化：SharedPreferences（key: app_mode），默认 AI 视图；
/// - 导航过滤：插件视图（AppMode.plugins）侧栏排除 4 个特殊插件
///   （ai-assistant / theme-creator / html-creator / scraper），
///   与现有 [filterNavByPluginState]（启用/侧栏可见）链式组合；
/// - 路由隔离：**不硬阻断**——深层链接（市场卡片/命令面板/URL）照常可用，
///   模式只管导航外观；仅 '/' 按模式重定向（见 [defaultRouteForMode]）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:evergreen_base/core/module/module_registry.dart';
import 'package:evergreen_base/core/module/sidebar_section.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/plugin_state_service.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/marketplace/nav_filter.dart';

/// 三种视图模式。
enum AppMode { ai, developer, plugins }

/// 模式持久化 key（SharedPreferences）。
const String kAppModePrefsKey = 'app_mode';

/// 模式标签（扇形菜单 / UI 展示）。
String appModeLabel(AppMode mode) => switch (mode) {
      AppMode.ai => 'AI 视图',
      AppMode.developer => '开发者模式',
      AppMode.plugins => '插件视图',
    };

/// 模式描述（扇形菜单副标题 / 无障碍）。
String appModeDescription(AppMode mode) => switch (mode) {
      AppMode.ai => 'AI 助手为主视图',
      AppMode.developer => '主题创作 · 插件制作 · 数据爬取 · Skill 创作',
      AppMode.plugins => '全部插件',
    };

/// 字符串 → 模式（持久化解码）。未知/损坏值返回 null（调用方保持旧值或默认）。
AppMode? appModeFromString(String? s) => switch (s) {
      'ai' => AppMode.ai,
      'developer' => AppMode.developer,
      'plugins' => AppMode.plugins,
      _ => null,
    };

/// 模式 → 字符串（持久化编码，直接用 enum name）。
String appModeToString(AppMode mode) => mode.name;

/// 当前视图模式。默认 AI 视图；启动后由 AppShell 从 SharedPreferences 载入覆盖
/// （与旧 sidebar_collapsed 同一载入模式，避免闪动）。
final appModeProvider = StateProvider<AppMode>((ref) => AppMode.ai);

/// 开发者模式主区当前选中的插件索引
/// （0=主题创作 / 1=插件制作 / 2=数据爬取；会话内记忆，切走再回保持）。
final devHubIndexProvider = StateProvider<int>((ref) => 0);

/// 6 个特殊插件 id——只出现在 AI 视图 / 开发者模式，不进入插件视图侧栏。
const Set<String> kSpecialPluginIds = {
  'ai-assistant',
  'theme-creator',
  'html-creator',
  'scraper',
  'dsh',
  'skill-creator',
};

/// 开发者模式五插件 id（顺序即索引：0=主题创作 / 1=插件制作 / 2=数据爬取 / 3=DSH / 4=Skill 创作）。
const List<String> kDevPluginIds = [
  'theme-creator',
  'html-creator',
  'scraper',
  'dsh',
  'skill-creator',
];

/// 切换模式并持久化。持久化失败静默降级（不影响本次切换）。
/// 启动时载入由 app_bootstrap 在 ProviderScope 注入时完成（避免默认模式闪动）。
Future<void> setAppMode(WidgetRef ref, AppMode mode) async {
  ref.read(appModeProvider.notifier).state = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAppModePrefsKey, appModeToString(mode));
  } catch (_) {
    // 测试/无存储环境：切换照常生效，仅不持久化。
  }
}

// ═══════ 导航过滤（模式维度） ═══════

/// 按模式过滤导航分组：移除 4 个特殊插件，空 section 整体移除
/// （与 [filterNavByPluginState] 同一语义，可链式组合）。
List<(SidebarSection, List<NavEntry>)> filterNavByAppMode(
  List<(SidebarSection, List<NavEntry>)> groups,
) {
  final out = <(SidebarSection, List<NavEntry>)>[];
  for (final (section, entries) in groups) {
    final kept =
        entries.where((e) => !kSpecialPluginIds.contains(e.moduleId)).toList();
    if (kept.isNotEmpty) {
      out.add((section, kept));
    }
  }
  return out;
}

/// 按模式过滤扁平导航（collapsed 侧栏 / 移动端底部导航 / 重定向计算）。
List<NavEntry> filterNavFlatByAppMode(List<NavEntry> flat) =>
    flat.where((e) => !kSpecialPluginIds.contains(e.moduleId)).toList();

/// '/' 在各模式下的默认目标路由（GoRouter redirect 使用）。
///
/// - ai：/ai-assistant（模块存在时；未安装则 null → 欢迎占位页）；
/// - developer：/dev-hub；
/// - plugins：侧栏第一个可见插件（模式过滤 + 插件状态过滤；无则 null）。
String? defaultRouteForMode({
  required AppMode mode,
  required ModuleRegistry registry,
  Map<String, PluginStateRecord>? pluginStates,
}) {
  switch (mode) {
    case AppMode.ai:
      return registry.findById('ai-assistant') != null
          ? '/ai-assistant'
          : null;
    case AppMode.developer:
      return '/dev-hub';
    case AppMode.plugins:
      final byMode = filterNavFlatByAppMode(registry.navFlat);
      final visible = pluginStates == null
          ? byMode
          : filterNavFlatByPluginState(byMode, pluginStates);
      return visible.isEmpty ? null : visible.first.routePath;
  }
}

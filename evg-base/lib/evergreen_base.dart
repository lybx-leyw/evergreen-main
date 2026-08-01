/// Evergreen Base 2.0 — 平台对外 API。
///
/// 双轨架构：`core/`（上游声明层）+ `renderer/`（下游渲染层）。
/// 消费者通过本 barrel 获得全部公共 API。
library;

// ═══════ 上游 — Agent 运行时 ═══════
// hide: PluginManifest（保留 core/module/plugin_manifest.dart 来源）、
// ChatMessage（保留 renderer/components/shared/widgets/models.dart 来源）——
// 消除 barrel 同名导出歧义（ambiguous_export）。
export 'core/agent/agent.dart' hide ChatMessage, PermissionLevel, PluginManifest;
// ═══════ 上游 — 设置与配置 ═══════
export 'core/config/config.dart';
// ═══════ 上游 — 数据谱仪器 ═══════
export 'core/data/data.dart';
export 'core/errors.dart';
// ═══════ 上游 — 基础设施 ═══════
export 'core/log.dart';
// ═══════ 上游 — 模块声明系统 ═══════
export 'core/module/modules.dart';
export 'core/result.dart';
// ═══════ 上游 — 通用服务 ═══════
export 'core/services/services.dart';
// ═══════ 上游 — 主题声明系统 ═══════
export 'core/theme/theme.dart';
export 'core/utils/file_utils.dart';
export 'core/utils/greenix_path.dart';
export 'core/utils/python_env.dart';
// ═══════ 上游 — 工具函数 ═══════
export 'core/utils/safe_parse.dart';
export 'core/utils/token_estimator.dart';
export 'generated/plugin_imports.g.dart';
// ═══════ 应用级 — 全局 Riverpod 提供者（canonical） ═══════
export 'providers.dart';
// ═══════ 下游 — 渲染层六层架构 ═══════
export 'renderer/components/shared/widgets/widgets.dart';
export 'renderer/renderer.dart';
// ═══════ 应用级 — 兼容性 stub（renderer 通过旧路径引用） ═══════
export 'theme/breakpoints.dart';

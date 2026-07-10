/// Evergreen Base 2.0 — 平台对外 API。
///
/// 双轨架构：`core/`（上游声明层）+ `renderer/`（下游渲染层）。
/// 消费者通过本 barrel 获得全部公共 API。
library evergreen_base;

// ═══════ 上游 — Agent 运行时 ═══════
export 'core/agent/agent.dart';

// ═══════ 上游 — 设置与配置 ═══════
export 'core/config/config.dart';

// ═══════ 上游 — 数据谱仪器 ═══════
export 'core/data/data.dart';

// ═══════ 上游 — 模块声明系统 ═══════
export 'core/module/modules.dart';

// ═══════ 上游 — 主题声明系统 ═══════
export 'core/theme/theme.dart';

// ═══════ 上游 — 通用服务 ═══════
export 'core/services/services.dart';

// ═══════ 上游 — 基础设施 ═══════
export 'core/log.dart';
export 'core/errors.dart';
export 'core/result.dart';

// ═══════ 上游 — 工具函数 ═══════
export 'core/utils/safe_parse.dart';
export 'core/utils/token_estimator.dart';
export 'core/utils/greenix_path.dart';
export 'core/utils/python_env.dart';
export 'core/utils/file_utils.dart';

// ═══════ 下游 — 渲染层六层架构 ═══════
export 'renderer/components/shared/widgets/widgets.dart';
export 'renderer/renderer.dart';

// ═══════ 应用级 — 全局 Riverpod 提供者（canonical） ═══════
export 'providers.dart';

// ═══════ 应用级 — 兼容性 stub（renderer 通过旧路径引用） ═══════
export 'theme/breakpoints.dart';
export 'generated/plugin_imports.g.dart';

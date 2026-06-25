/// 模块注册框架——插件式架构基础设施。
///
/// 每个 feature 模块通过 [FeatureModule] 声明：
/// - 导航信息（图标、名称、路由）
/// - 依赖关系（dependsOn）
/// - 对外暴露的 Provider（exports）
/// - 可选：连通性检查、数据源、Agent 工具
///
/// [ModuleRegistry] 收集所有模块声明，自动生成：
/// - GoRouter 路由表
/// - 侧边栏导航（4 种展示形态）
/// - 命令面板条目
library;

export 'feature_module.dart';
export 'module_registry.dart';
export 'sidebar_section.dart';

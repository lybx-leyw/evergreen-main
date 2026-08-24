/// 能力维度风险定级桥接（M5-3/M5-4 · 纯逻辑，core 子包内可单测）。
///
/// 安装前权限弹窗（M5-3）和核心能力维度可视化（M5-4）需要一套不依赖 Flutter
/// 的风险定级与「核心维度 ↔ 渲染层标签」的映射。其中：
/// - 风险定级（[riskOf]/[maxRisk]）是纯逻辑，留在 core 子包（本文件）。
/// - 与渲染层 `AbilityDim` 的双向映射（依赖 Flutter 枚举）放在 renderer 侧
///   （`lib/renderer/components/shared/widgets/ability_tag.dart` 的工厂），
///   避免 core 子包反向依赖渲染层。
library;

import 'capability.dart';

/// 权限风险级别（M5-3 安装前弹窗用）。
///
/// 复用渲染层 [PermissionLevel] 的语义（safe/warning/danger），
/// 但这里用纯枚举避免 core 子包依赖 Flutter 的渲染模型。
enum RiskLevel {
  /// 安全（主题/纯展示，无副作用）。
  safe,

  /// 中危（读写数据 / 网络 / 配置）。
  warning,

  /// 高危（启动后端进程 / 执行代码）。
  danger,
}

/// 单个能力维度的默认风险定级（fail-closed：未知维度归 danger）。
///
/// 依据：
/// - `process`：启动后端 .exe，最高风险 → danger。
/// - `agent`：AI 工具可调外部/文件 → warning。
/// - `data`：读写数据源 → warning。
/// - `config`：改设置项 → warning。
/// - `module`：UI 模块，无独立副作用 → safe。
/// - `theme`：仅配色 → safe。
RiskLevel riskOf(CapabilityDimension dim) {
  switch (dim) {
    case CapabilityDimension.process:
      return RiskLevel.danger;
    case CapabilityDimension.agent:
    case CapabilityDimension.data:
    case CapabilityDimension.config:
      return RiskLevel.warning;
    case CapabilityDimension.module:
    case CapabilityDimension.theme:
      return RiskLevel.safe;
  }
}

/// 渲染层 `PermissionLevel` 的轻量名（避免 core 依赖 Flutter 模型）。
///
/// 与 `renderer/components/shared/widgets/models.dart` 的 [PermissionLevel] 一一对应。
enum PermissionLevelName { safe, warning, danger }

/// `RiskLevel` → 渲染层 `PermissionLevel` 等价名（供弹窗消费文案/配色）。
PermissionLevelName riskToPermissionLevel(RiskLevel risk) {
  switch (risk) {
    case RiskLevel.safe:
      return PermissionLevelName.safe;
    case RiskLevel.warning:
      return PermissionLevelName.warning;
    case RiskLevel.danger:
      return PermissionLevelName.danger;
  }
}

/// 一组能力维度里的最高风险（用于弹窗顶部总览）。
RiskLevel maxRisk(List<CapabilityDimension> dims) {
  var max = RiskLevel.safe;
  for (final d in dims) {
    final r = riskOf(d);
    if (r.index > max.index) max = r;
  }
  return max;
}

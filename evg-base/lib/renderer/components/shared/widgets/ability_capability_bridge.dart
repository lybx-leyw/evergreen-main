/// 渲染层能力维度桥接（M5-4 · renderer 侧）。
///
/// 渲染层 [AbilityDim]（agent/ui/data/theme/settings/skill）与核心层
/// [CapabilityDimension]（agent/module/theme/data/config/process）是两套平行枚举。
/// 本文件在 renderer 侧提供双向映射（renderer 可同时 import 两者），
/// 供权限弹窗（M5-3）与市场卡片（M5-4）统一吃核心层真实能力维度。
library;

import 'package:evergreen_base/core/module/capability.dart';
import 'package:evergreen_base/renderer/components/shared/widgets/models.dart';

/// 渲染层 [AbilityDim] → 核心层 [CapabilityDimension]。
///
/// `skill` 在核心层无对应维度 → 返回 `null`。
CapabilityDimension? toCoreDim(AbilityDim dim) {
  switch (dim) {
    case AbilityDim.agent:
      return CapabilityDimension.agent;
    case AbilityDim.ui:
      return CapabilityDimension.module;
    case AbilityDim.theme:
      return CapabilityDimension.theme;
    case AbilityDim.data:
      return CapabilityDimension.data;
    case AbilityDim.settings:
      return CapabilityDimension.config;
    case AbilityDim.skill:
      return null;
  }
}

/// 核心层 [CapabilityDimension] → 渲染层 [AbilityDim]。
///
/// `process` 无独立 UI 色标（归高危提示而非色标）→ 返回 `null`。
AbilityDim? toAbilityDim(CapabilityDimension dim) {
  switch (dim) {
    case CapabilityDimension.agent:
      return AbilityDim.agent;
    case CapabilityDimension.module:
      return AbilityDim.ui;
    case CapabilityDimension.theme:
      return AbilityDim.theme;
    case CapabilityDimension.data:
      return AbilityDim.data;
    case CapabilityDimension.config:
      return AbilityDim.settings;
    case CapabilityDimension.process:
      return null;
  }
}

/// 一组渲染层维度 → 核心层维度（过滤 null）。
List<CapabilityDimension> toCoreDims(List<AbilityDim> dims) =>
    dims.map(toCoreDim).whereType<CapabilityDimension>().toList();

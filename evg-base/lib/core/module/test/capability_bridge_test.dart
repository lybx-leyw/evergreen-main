/// CapabilityBridge 风险定级测试（M5-3/M5-4 · 纯逻辑，core 子包内）。
///
/// 注：`AbilityDim` 双向映射在 renderer 侧测试（依赖 Flutter 枚举），
/// 本文件仅覆盖 core 子包可编译的纯逻辑。
import 'package:test/test.dart';

import '../capability.dart';
import '../capability_bridge.dart';

void main() {
  group('riskOf', () {
    test('process → danger', () {
      expect(riskOf(CapabilityDimension.process), RiskLevel.danger);
    });
    test('agent/data/config → warning', () {
      expect(riskOf(CapabilityDimension.agent), RiskLevel.warning);
      expect(riskOf(CapabilityDimension.data), RiskLevel.warning);
      expect(riskOf(CapabilityDimension.config), RiskLevel.warning);
    });
    test('module/theme → safe', () {
      expect(riskOf(CapabilityDimension.module), RiskLevel.safe);
      expect(riskOf(CapabilityDimension.theme), RiskLevel.safe);
    });
  });

  group('maxRisk', () {
    test('空列表 → safe', () {
      expect(maxRisk([]), RiskLevel.safe);
    });
    test('混合取最高（含 process → danger）', () {
      expect(
        maxRisk([
          CapabilityDimension.theme,
          CapabilityDimension.data,
          CapabilityDimension.process,
        ]),
        RiskLevel.danger,
      );
    });
    test('仅 safe 维度 → safe', () {
      expect(
        maxRisk([CapabilityDimension.theme, CapabilityDimension.module]),
        RiskLevel.safe,
      );
    });
  });

  group('riskToPermissionLevel', () {
    test('映射一致', () {
      expect(riskToPermissionLevel(RiskLevel.safe), PermissionLevelName.safe);
      expect(riskToPermissionLevel(RiskLevel.warning), PermissionLevelName.warning);
      expect(riskToPermissionLevel(RiskLevel.danger), PermissionLevelName.danger);
    });
  });
}

/// MarketplaceSlot 启用前权限闸的纯逻辑验证（M5-3 接入 MarketplaceSlot）。
///
/// 验证 [_resolveCapabilities] 的等价行为：本地磁盘插件含能力维度（如 agent/）
/// 时会被拦截弹窗，无能力维度或内置（无目录）则不拦。
import 'dart:io';

import 'package:evergreen_base/core/module/capability.dart';
import 'package:flutter_test/flutter_test.dart';

/// 等价于 [MarketplaceSlot._resolveCapabilities]：内置（dirPath 空）返回空，
/// 否则 discoverCapabilities。
List<CapabilityDimension> resolveCapabilities(String dirPath) {
  if (dirPath.isEmpty) return const [];
  return discoverCapabilities(dirPath);
}

/// 等价于 [_toggleEnabled] 的拦截判定：要启用 且 维度非空 → 需权限闸。
bool needsGate({required bool enabling, required List<CapabilityDimension> dims}) =>
    enabling && dims.isNotEmpty;

void main() {
  test('含 agent/ 目录的本地插件 → 触发权限闸（fail-closed 前置）', () {
    final dir = Directory.systemTemp.createTempSync('mkt_gate_');
    try {
      Directory('${dir.path}/agent').createSync(recursive: true);
      final dims = resolveCapabilities(dir.path);
      expect(dims, contains(CapabilityDimension.agent));
      expect(needsGate(enabling: true, dims: dims), isTrue);
      // 停用（enabling=false）不拦。
      expect(needsGate(enabling: false, dims: dims), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('无能力子目录的本地插件 → 不触发权限闸', () {
    final dir = Directory.systemTemp.createTempSync('mkt_flat_');
    try {
      final dims = resolveCapabilities(dir.path);
      expect(dims, isEmpty);
      expect(needsGate(enabling: true, dims: dims), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('内置模块（无磁盘目录）→ 不触发权限闸', () {
    final dims = resolveCapabilities('');
    expect(dims, isEmpty);
    expect(needsGate(enabling: true, dims: dims), isFalse);
  });
}

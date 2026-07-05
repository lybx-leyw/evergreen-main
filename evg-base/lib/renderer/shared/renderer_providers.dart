/// 渲染层全局 Riverpod 提供者——主题、当前模块、断点、数据。
///
/// 公开类：无（本文件仅导出顶层 provider）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/modules.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';

// ═══════ 当前模块 ═══════

/// 当前渲染的模块描述符。
final currentModuleProvider = StateProvider<ModuleDescriptor?>((ref) => null);

// ═══════ 断点 ═══════

/// 移动端断点（≤600px 视为移动端）。
const double kMobileBreakpoint = 600;

/// 中等断点（≤1280px 视为中等宽度）。
const double kMediumBreakpoint = 1280;

/// 当前窗口宽度（px）。
final windowWidthProvider = StateProvider<double>((ref) => 1280);

/// 是否为移动端布局。
final isMobileProvider = Provider<bool>((ref) {
  return ref.watch(windowWidthProvider) <= kMobileBreakpoint;
});

// ═══════ 数据谱仪器 ═══════

/// 数据谱仪器提供者。
final dataOrchestratorProvider = Provider<DataOrchestrator>((ref) {
  throw UnimplementedError('由应用层注入 DataOrchestrator 实例');
});

// ═══════ 主题提供者（委托） ═══════

/// 已解析的主题描述符。
final themeDescriptorProvider = StateProvider<ThemeDescriptor?>((ref) => null);

/// 渲染层全局 Riverpod 提供者——主题、当前模块、断点、数据。
///
/// 公开类：无（本文件仅导出顶层 provider）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:evergreen_base/core/module/modules.dart';
import 'package:evergreen_base/core/theme/theme_descriptor.dart';
import 'package:evergreen_base/providers.dart' show themeStoreProvider;
import '../theme/render_tokens.dart';

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

  // dataOrchestratorProvider 已迁移至 lib/providers.dart

// ═══════ 主题提供者 ═══════

/// 已解析的主题描述符——从 [themeStoreProvider] 派生，主题切换时自动更新。
///
/// 当 [ThemeStore.activeTheme] 变更（HTTP POST /theme/active 或直接设置）时，
/// [themeStoreProvider] 通知 → 本 provider 重建 → 所有 watch 本 provider 的 UI 重建。
final themeDescriptorProvider = Provider<ThemeDescriptor?>((ref) {
  final store = ref.watch(themeStoreProvider);
  return store.activeTheme;
});

/// 从 [themeDescriptorProvider] 派生的渲染令牌。
///
/// 主题切换时自动更新。未设置主题时使用内置 dark 默认值。
/// 同时更新 [RenderTokens.applyTheme] 以保持静态访问兼容。
final renderTokensProvider = Provider<RenderTokensColors>((ref) {
  final theme = ref.watch(themeDescriptorProvider);
  final tokens = RenderTokensColors.fromTheme(theme);
  RenderTokens.applyTheme(theme);
  return tokens;
});

// ═══════ V2 Manifest ═══════

/// V2 原始 manifest JSON 映射：moduleId → raw JSON Map。
///
/// V2 清单含 `schemaVersion: "2.0"` 和 `renderMode: "html"`，
/// HTML 渲染器 (HtmlRenderView) 通过此 provider 获取完整 JSON。
final v2ManifestProvider =
    StateProvider<Map<String, Map<String, dynamic>>>((ref) => {});

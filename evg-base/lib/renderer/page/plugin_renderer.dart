/// PluginRenderer — 插件渲染一键函数。
///
/// 统一入口，接受 V2 manifest JSON + 渲染模式，输出 Widget 或 HTML 字符串。
/// 内部调用现有 `ModuleDescriptor.fromJson` + `ModuleDispatch` 或 `HtmlRenderer.render`。
///
/// # 使用方式
///
/// ```dart
/// // Dart Widget 渲染
/// final widget = PluginRenderer.renderAsWidget(v2ManifestJson,
///   workingDirectory: 'plugins/my-module/');
///
/// // HTML 字符串渲染
/// final html = PluginRenderer.renderAsHtml(v2ManifestJson);
/// ```
///
/// # 渲染模式
/// - `"dart"` (默认): Flutter Widget 树 — 调用 `ModuleDispatch`
/// - `"html"`: 自包含 HTML5 页面 — 调用 `HtmlRenderer.render`
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/core/module/module_descriptor.dart';
import '../module/module_dispatch.dart';
import 'html_renderer.dart';
import 'render_tokens.dart';

/// 渲染模式枚举。
enum RenderMode {
  /// Flutter Widget 渲染（默认）
  dart,

  /// HTML5 字符串渲染
  html,
}

/// 插件渲染器——根据 V2 manifest JSON 一键生成 UI。
///
/// 支持两种渲染模式：
/// - [RenderMode.dart]: 返回 Flutter Widget
/// - [RenderMode.html]: 返回完整 HTML5 文档字符串
class PluginRenderer {
  PluginRenderer._();

  /// 从 V2 manifest JSON 生成 Flutter Widget。
  ///
  /// [manifest] 是 V2 格式的 manifest（`schemaVersion: "2.0"`）。
  /// [workingDirectory] 仅用于 `ui: "composite"` 模式时的进程管理。
  /// 未识别的 `ui` 值静默回退到 [DefaultView]。
  ///
  /// 返回可嵌入到任意 Flutter Widget 树中的 Widget。
  static Widget renderAsWidget(
    Map<String, dynamic> manifest, {
    String? workingDirectory,
  }) {
    final descriptor = ModuleDescriptor.fromJson(manifest);
    return ModuleDispatch(
      descriptor: descriptor,
      workingDirectory: workingDirectory,
    );
  }

  /// 从 V2 manifest JSON 生成完整 HTML5 页面字符串。
  ///
  /// [manifest] 是 V2 格式的 manifest（`schemaVersion: "2.0"`）。
  /// 返回自包含的 HTML5 文档，可直接写入文件或在 WebView 中显示。
  ///
  /// 页面包含暗色主题 CSS、53 种组件样式、V2 事件系统 JS 桥接。
  static String renderAsHtml(Map<String, dynamic> manifest) {
    return HtmlRenderer.render(manifest);
  }

  /// 根据 [RenderMode] 自动选择渲染方式。
  ///
  /// - [RenderMode.dart] → `renderAsWidget(manifest)`
  /// - [RenderMode.html] → `renderAsHtml(manifest)`
  static dynamic render(
    Map<String, dynamic> manifest, {
    RenderMode mode = RenderMode.dart,
    String? workingDirectory,
  }) {
    switch (mode) {
      case RenderMode.dart:
        return renderAsWidget(manifest, workingDirectory: workingDirectory);
      case RenderMode.html:
        return renderAsHtml(manifest);
    }
  }
}

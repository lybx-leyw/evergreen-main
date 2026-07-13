/// V2 Manifest HTML 渲染器 — 主入口。
///
/// 接收 V2 manifest JSON，返回完整的 HTML5 页面字符串。
/// 渲染管线：JSON → Module/Page/Layout/Slot/Component → HTML 模板。
library;

import 'package:flutter/foundation.dart';
import '../../core/data/data.dart';
import 'html_template.dart';

/// V2 Manifest HTML 渲染器。
class HtmlRenderer {
  /// 从 V2 manifest JSON 生成完整 HTML 页面（静态配置渲染，无数据源注入）。
  ///
  /// [manifest] 必须是 V2 格式的 manifest（`schemaVersion: "2.0"`）。
  /// 返回自包含的 HTML5 文档字符串，可直接在浏览器/WebView 中显示。
  /// [embedded] 为 true 时仅渲染页面内容，不含侧边栏和 Tab（Flutter 内嵌用）。
  static Future<String> render(Map<String, dynamic> manifest, {bool embedded = false}) {
    return buildHtmlPage(manifest, embedded: embedded);
  }

  /// M2 P3-2（R7 双端一致）：带数据源注入的渲染。
  ///
  /// 与 [render] 相同，但传入 [orch] 后，各组件若声明 `dataSource`，
  /// 会在 Dart 侧经 [resolveDataSource] 拉取真实数据并注入 HTML 模板，
  /// 行为与 Dart 端 `DataSourceSlot` 一致。
  static Future<String> renderWithData(
    Map<String, dynamic> manifest,
    DataOrchestrator orch, {
    bool embedded = false,
  }) {
    return buildHtmlPage(manifest, embedded: embedded, orch: orch);
  }
}

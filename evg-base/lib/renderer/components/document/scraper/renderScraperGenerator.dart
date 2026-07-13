/// HTML 静态预览渲染器（M4 `scraper-generator`）。
///
/// Dart 端 `ScraperGeneratorView` 是重交互组件（WebView 抓包 + 终端 + 隔离 AI 工作区）。
/// 按 M4 决策，HTML 端允许「注册对应组件后占位降级」：此处渲染静态预览卡片，
/// 展示目标地址与阶段说明（R9 优雅降级）。
library;

import '../../shared/html_helpers.dart';

String renderScraperGenerator(Map<String, dynamic> comp) {
  final rawCfg = comp['config'];
  final cfg = rawCfg is Map ? rawCfg.cast<String, dynamic>() : <String, dynamic>{};
  final url = esc(cfg['initialUrl'] as String? ?? 'https://www.baidu.com');
  return '''
<div class="evg-comp evg-comp-scraper">
  <div class="evg-scraper-title">🕷️ 爬虫脚本生成器</div>
  <div class="evg-scraper-url">目标：$url</div>
  <div class="evg-scraper-note">WebView 抓包 + 终端 + AI 工作区的重交互组件，HTML 端以静态预览呈现</div>
</div>''';
}

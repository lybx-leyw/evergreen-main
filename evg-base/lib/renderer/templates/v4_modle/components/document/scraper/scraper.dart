/// 爬虫脚本生成器 #64 — 特制组件。
///
/// 所见即所得爬虫脚本生成器（WYSIWYG Web Scraper Script Generator）
///
/// 公开 API：
/// - [ScraperGeneratorView] — 主视图（在 CompositeView 中注册为 'scraper-generator'）
/// - [ScraperWorkflow] — 工作流状态机
/// - [HttpRequestLog] — HTTP 请求日志模型
/// - [ScraperPhase] — 工作流阶段枚举
library scraper;

export 'scraper_generator_view.dart';
export 'scraper_workflow.dart';
export 'scraper_tools.dart';
export 'scraper_exporter.dart';

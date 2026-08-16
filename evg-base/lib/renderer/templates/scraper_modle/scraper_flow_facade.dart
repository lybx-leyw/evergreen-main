/// 爬虫全流程门面 —— 包住工作流 + Agent + 导出器，提供高阶统一接口。
///
/// 将分散在 ScraperAI / ScraperWorkflow / scraper_exporter 中的流程抽取为
/// 统一入口，供 UI 层和测试直接调用。
///
/// 用法：
/// ```dart
/// final facade = ScraperFlowFacade(workflow: workflow);
/// await facade.startCapture('https://example.com');
/// final schema = await facade.analyzeSelection(workflow.logs);
/// final result = await facade.generateAsDataPlugin(
///   schema: schema,
///   pluginName: 'my-scraper',
///   outputDir: 'plugins/my-scraper/',
/// );
/// ```
library scraper_flow_facade;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';
import 'scraper_exporter.dart';
import 'workflow/scraper_workflow.dart';

/// AI 字段推断回调。
///
/// 接收用户选中的 HTTP 请求日志，返回推断出的字段列表。
/// 若 [ScraperFlowFacade.aiFieldInferrer] 被设置，
/// [analyzeSelection] 将优先使用 AI 推断，失败时回退到 URL 推断。
typedef AiFieldInferrer = Future<List<InferredField>> Function(List<HttpRequestLog> selected);

/// 爬虫全流程门面。
///
/// 职责：
/// - 统一起始接口（不再让 UI 层直接操作 ScraperWorkflow 状态机）
/// - 复用现有 ScraperWorkflow、scraper_exporter、DataPluginer
/// - 纯 Dart，无 Flutter 依赖，可在测试中独立构造
class ScraperFlowFacade {
  final ScraperWorkflow workflow;

  /// 可选：AI 字段推断器。
  ///
  /// 提供后 [analyzeSelection] 将优先使用 AI 智能推断字段名、类型及描述，
  /// 失败时自动回退到 URL 路径推断。
  ///
  /// 示例（DeepSeek）：
  /// ```dart
  /// facade.aiFieldInferrer = (logs) => _inferWithDeepSeek(logs);
  /// ```
  AiFieldInferrer? aiFieldInferrer;

  ScraperFlowFacade({required this.workflow});

  // ── 阶段一：启动抓包 ──

  /// 启动 CDP 抓包。
  ///
  /// 将 [workflow] 推进到 [ScraperPhase.capturing] 阶段。
  /// 后续用户操作触发的 HTTP 请求由 WebView JS 注入写入 workflow.logs。
  Future<void> startCapture(String url) async {
    debugPrint('[ScraperFlowFacade] 📡 startCapture: $url');
    if (workflow.phase != ScraperPhase.idle) {
      debugPrint('[ScraperFlowFacade] ⚠ 非 idle 状态，重置后再启动');
      workflow.reset();
    }
    workflow.startCapturing();
    debugPrint('[ScraperFlowFacade] ✅ phase → ${workflow.phase.name}');
  }

  // ── 阶段二：分析日志 → 推断 Schema ──

  /// 分析用户选中的 HTTP 请求日志，推断数据结构。
  ///
  /// [selected] 通常为 [workflow.logs] 的子集（用户在 UI 中勾选）。
  /// 返回 [InferredSchema] 含 sourceUrl + fields[]（name/type/description）。
  ///
  /// 推断策略（按优先级）：
  /// 1. AI 推断 —— 若 [aiFieldInferrer] 已设置，调用 AI 做智能字段推断
  /// 2. URL 推断 —— AI 不可用或失败时回退到 URL 路径提取
  Future<InferredSchema> analyzeSelection(List<HttpRequestLog> selected) async {
    debugPrint('[ScraperFlowFacade] 🔍 analyzeSelection: ${selected.length} 条日志');

    if (selected.isEmpty) {
      debugPrint('[ScraperFlowFacade] ⚠ 空日志列表，返回空 schema');
      return const InferredSchema(
        sourceUrl: '',
        fields: [],
      );
    }

    // 从选中日志推断 sourceUrl（取第一条非空 URL）
    String sourceUrl = '';
    for (final log in selected) {
      if (log.url.isNotEmpty) {
        sourceUrl = log.url;
        break;
      }
    }

    final title = _guessTitle(sourceUrl);

    // ── 策略1：AI 推断 ──
    if (aiFieldInferrer != null) {
      try {
        debugPrint('[ScraperFlowFacade] 🤖 调用 AI 推断字段...');
        final aiFields = await aiFieldInferrer!(selected);
        if (aiFields.isNotEmpty) {
          debugPrint('[ScraperFlowFacade] ✅ AI 推断 ${aiFields.length} 个字段');
          return InferredSchema(
            sourceUrl: sourceUrl,
            title: title,
            fields: aiFields,
          );
        }
        debugPrint('[ScraperFlowFacade] ⚠ AI 返回空字段，回退到 URL 推断');
      } catch (e) {
        debugPrint('[ScraperFlowFacade] ⚠ AI 推断失败，回退到 URL 推断: $e');
      }
    }

    // ── 策略2：URL 推断（回退）──
    // 基础推断：从 URL 路径提取可能的字段名
    final fields = <InferredField>[];
    try {
      final uri = Uri.tryParse(sourceUrl);
      if (uri != null) {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        for (final seg in segments) {
          // 跳过明显的数字 ID 段
          if (int.tryParse(seg) != null) continue;
          // 跳过常见路径段
          if (['api', 'v1', 'v2', 'v3', 'data', 'json'].contains(seg.toLowerCase())) continue;
          fields.add(InferredField(
            name: seg,
            type: 'string',
            description: '从 URL 路径推断: $seg',
          ));
        }
      }
    } catch (e) {
      debugPrint('[ScraperFlowFacade] ⚠ URL 解析失败: $e');
    }

    // 如果 URL 推断无字段，生成一个占位字段
    if (fields.isEmpty) {
      final lastSegment = sourceUrl.split('/').lastOrNull ?? 'data';
      fields.add(InferredField(
        name: lastSegment,
        type: 'string',
        description: '自动推断字段（请手动调整）',
      ));
    }

    final schema = InferredSchema(
      sourceUrl: sourceUrl,
      title: title,
      fields: fields,
    );

    debugPrint('[ScraperFlowFacade] ✅ 推断 schema: source=$sourceUrl, fields=${fields.length}');
    return schema;
  }

  // ── 阶段三：生成 data 插件 ──

  /// 将爬虫输出 + 推断 schema 导出为完整的 data 插件。
  ///
  /// 依次调用：
  /// 1. [exportAsPython] — 写入 scraper.py（含配置模板）
  /// 2. 复制 scraper.py → data/（对齐 register_data_source.dart 的 script 解析）
  /// 3. [exportDataManifest] — 写入 data/manifest.json（script: scraper.py + runtime: python）
  ///
  /// [pluginName]: 插件英文标识
  /// [outputDir]: 插件根目录（如 plugins/my-scraper/）
  /// [pythonCode]: AI 生成的 Python 爬虫代码（如果为空则跳过 .py 写入）
  Future<ExportResult> generateAsDataPlugin({
    required InferredSchema schema,
    required String pluginName,
    required String outputDir,
    String pythonCode = '',
    /// 显式指定的数据类型名称（如用户命名）。null 时回退到 [schema.title]。
    String? dataTypeName,
    /// Phase 4：探索模式显式归类（manifest category）。
    String? category,
    /// Phase 4：探索模式显式展示名（manifest displayName）。
    String? displayName,
  }) async {
    debugPrint('[ScraperFlowFacade] 🚀 generateAsDataPlugin: $pluginName → $outputDir');

    // 1) 写入 Python 爬虫（如果有代码）
    if (pythonCode.isNotEmpty) {
      final pyResult = await exportAsPython(pythonCode, outputDir);
      if (!pyResult.success) {
        return pyResult; // .py 写入失败即失败
      }
      debugPrint('[ScraperFlowFacade] ✅ scraper.py 已写入');
    }

    // 1.5) 复制 scraper.py → data/（register_data_source.dart 按 data/ 相对路径解析 script）
    final dataDir = p.join(outputDir, 'data');
    final srcPy = File(p.join(outputDir, 'scraper.py'));
    if (srcPy.existsSync()) {
      Directory(dataDir).createSync(recursive: true);
      srcPy.copySync(p.join(dataDir, 'scraper.py'));
      debugPrint('[ScraperFlowFacade] ✅ scraper.py → data/scraper.py');
    }

    // 2) 生成 data/manifest.json —— 统一 .py 契约（runtime: python，不再 .exe）
    const fetcherScript = 'scraper.py';

    final manifestResult = await exportDataManifest(
      name: pluginName,
      fetcherScript: fetcherScript,
      schema: schema,
      outputDir: outputDir,
      dataTypeName: dataTypeName,
      category: category,
      displayName: displayName,
    );

    if (!manifestResult.success) {
      debugPrint('[ScraperFlowFacade] ⚠ manifest 生成失败: ${manifestResult.message}');
      return manifestResult;
    }

    debugPrint('[ScraperFlowFacade] ✅ data 插件生成完毕: $outputDir');
    return const ExportResult(success: true, message: 'data 插件生成完毕');
  }

  // ── 辅助 ──

  /// 从 URL 猜测数据标题。
  String _guessTitle(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return '';
      // 取 host + 最后一个有意义的 path segment
      final host = uri.host.replaceAll('www.', '').split('.').first;
      final lastSeg = uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty && int.tryParse(s) == null,
        orElse: () => '',
      );
      if (lastSeg.isNotEmpty) return '$host/$lastSeg';
      return host;
    } catch (_) {
      return '';
    }
  }

  /// 释放资源。
  void dispose() {
    workflow.dispose();
    debugPrint('[ScraperFlowFacade] dispose');
  }
}

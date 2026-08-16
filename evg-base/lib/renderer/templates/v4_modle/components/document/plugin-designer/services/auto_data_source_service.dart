/// 自动数据源服务 —— 把"浏览器内嵌捕获的 HTTP 日志"经 [ScraperFlowFacade]
/// 转为 data 插件，并写回设计文档对应 Slot 的 `dataSource.endpoint = orch://<type>`。
///
/// 纯 Dart、依赖可注入（[ScraperFlowFacade] / 回调），便于单元/非 widget 测试，
/// 不驱动 [ScraperWebView]（规避 FAIL #13 的 `flutter_test` 泵陷阱）。
///
/// 设计要点：
/// 1. 复用 A-P1 的 [ScraperFlowFacade.generateAsDataPlugin]（输出对齐
///    `_scanAndRegisterDataSources` 契约的 data manifest），不另起炉灶。
/// 2. 生成的 `dataTypes[].name` 必须等于声明的 `<type>`，否则 `orch://<type>`
///    解析不到（与 A-P2/A-P4 `DataSourceDescriptor` 契约对齐）。
/// 3. 运行期注册（[onGenerated] 回调）由调用方负责（Batch 2 → `DataOrchestrator`），
///    本服务只负责"生成 + 回写"，职责单一、可独立测试。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/data_pluginer.dart';

/// 自动数据源生成失败异常。
class AutoDataSourceException implements Exception {
  final String reason;
  final String message;

  const AutoDataSourceException({required this.reason, required this.message});

  @override
  String toString() => 'AutoDataSourceException($reason): $message';
}

/// 是否已注册某数据源类型（解耦 [DataOrchestrator]，便于测试注入）。
typedef IsRegistered = bool Function(String type);

/// 自动数据源服务。
class AutoDataSourceService {
  /// 从 `orch://<type>` endpoint 提取 `<type>`；非 orch:// 返回 null。
  static String? extractOrchType(String? endpoint) {
    if (endpoint == null) return null;
    if (endpoint.startsWith('orch://')) {
      return endpoint.substring('orch://'.length);
    }
    return null;
  }

  /// 列出文档中"声明了未注册 `orch://` 数据源"的类型集合（去重）。
  static List<String> unregisteredOrchTypes(
    DesignDocument doc,
    IsRegistered isRegistered,
  ) {
    final types = <String>{};
    for (final page in doc.pages) {
      for (final slot in page.slots) {
        final ds = slot.component?.config['dataSource'];
        if (ds is Map && ds['endpoint'] is String) {
          final t = extractOrchType(ds['endpoint'] as String);
          if (t != null && t.isNotEmpty && !isRegistered(t)) {
            types.add(t);
          }
        }
      }
    }
    return types.toList();
  }

  /// 从捕获日志推导一个数据源类型名（取首个有效 URL 的 host 首段）。
  static String _deriveTypeName(List<HttpRequestLog> logs) {
    for (final log in logs) {
      final uri = Uri.tryParse(log.url);
      if (uri != null && uri.host.isNotEmpty) {
        return uri.host.replaceAll('www.', '').split('.').first;
      }
    }
    return '';
  }

  /// 从捕获日志自动生成 data 插件并写回设计文档对应 Slot 的 `dataSource`。
  ///
  /// [doc] 当前设计文档（原地更新对应 Slot 的 config.dataSource，随后返回同一实例）。
  /// [slotId] 目标 Slot 的 id（其组件 config 应含 `orch://<type>` 或将被推导命名）。
  /// [capturedLogs] 用户在 WebView 中操作捕获到的 HTTP 请求日志。
  /// [facade] 爬虫全流程门面（注入式：测试用 fake，UI 用真实 [ScraperFlowFacade]）。
  /// [pluginsDir] 插件根目录（如 `plugins/`）；生成物写入 `pluginsDir/<type>/data/`。
  /// [onGenerated] 可选：生成成功后回调（Batch 2 用于运行期注册进 [DataOrchestrator]）。
  ///
  /// 返回更新后的 [DesignDocument]（同一实例，已写回 endpoint）。
  Future<DesignDocument> autoGenerateFromCapture({
    required DesignDocument doc,
    required String slotId,
    required List<HttpRequestLog> capturedLogs,
    required ScraperFlowFacade facade,
    String? pluginsDir,
    void Function(String type, String outputDir)? onGenerated,
  }) async {
    // 1. 定位目标 Slot
    DesignSlot? target;
    for (final page in doc.pages) {
      for (final slot in page.slots) {
        if (slot.id == slotId) target = slot;
      }
    }
    if (target == null) {
      throw AutoDataSourceException(
        reason: 'slot_not_found',
        message: '未找到指定的 Slot（id=$slotId）',
      );
    }

    // 2. 提取/推导数据源类型名 <type>
    final dsRaw = target.component?.config['dataSource'];
    final declaredType = dsRaw is Map ? extractOrchType(dsRaw['endpoint'] as String?) : null;
    var type = (declaredType ?? '').isNotEmpty ? declaredType! : _deriveTypeName(capturedLogs);
    if (type.isEmpty) {
      throw const AutoDataSourceException(
        reason: 'no_type',
        message: '无法确定数据源类型名（Slot 未声明 orch:// 且无有效捕获 URL）',
      );
    }

    // 3. AI 分析日志 → 推断 schema（title 必须 == type，保证 manifest 名对齐 orch://type）
    var schema = await facade.analyzeSelection(capturedLogs);
    if ((schema.title ?? '').isEmpty) {
      schema = InferredSchema(
        sourceUrl: schema.sourceUrl,
        title: type,
        fields: schema.fields,
      );
    }

    // 4. 生成 data 插件（输出对齐 _scanAndRegisterDataSources 契约）
    final outputDir = pluginsDir != null ? p.join(pluginsDir, type) : 'plugins/$type';
    final result = await facade.generateAsDataPlugin(
      schema: schema,
      pluginName: type,
      outputDir: outputDir,
    );
    if (!result.success) {
      throw AutoDataSourceException(
        reason: 'generate_failed',
        message: result.message,
      );
    }

    // 5. 写回 endpoint（原地更新 live 文档）
    final comp = target.component;
    if (comp != null) {
      comp.config['dataSource'] = {'endpoint': 'orch://$type'};
    }

    // 6. 可选回调（Batch 2 → DataOrchestrator 热注册）
    onGenerated?.call(type, outputDir);

    debugPrint('[AutoDataSourceService] ✅ 已生成并回写数据源: orch://$type → $outputDir');
    return doc;
  }
}

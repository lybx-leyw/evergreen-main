/// 自动数据源捕获对话框 —— 设计器内"一键内嵌浏览器自动爬取 → 生成 data 插件"。
///
/// 复用既有的 [ScraperWebView]（内嵌 WebView2）+ [RequestLogPanel]（捕获日志）
/// + [ScraperFlowFacade]（分析/生成），通过 [AutoDataSourceService] 把捕获日志
/// 转成 data 插件并回写对应 Slot 的 `dataSource.endpoint = orch://<type>`。
///
/// 本对话框只负责"设计态生成 + 回写"，运行期注册（[onGenerated] → [DataOrchestrator]）
/// 由调用方负责（A-P5 第二批）。
library;

import 'package:flutter/material.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/web/scraper_webview.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/view/request_log_panel.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/workflow/scraper_workflow.dart';
import 'package:evergreen_base/renderer/templates/scraper_modle/scraper_flow_facade.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_document.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/models/design_slot.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/plugin-designer/services/auto_data_source_service.dart';

/// 自动数据源捕获对话框。
///
/// [doc] 当前设计文档（与调用方共享同一实例，生成后原地写回 endpoint）。
/// [slotId] 目标 Slot 的 id。
/// [pluginsDir] 插件根目录；生成物写入 `pluginsDir/<type>/data/`。
/// [onGenerated] 生成成功后回调（运行期注册用，Batch 2 接线）。
/// [onEndpointWritten] 无论"生成"还是"复用已有"都会回调，供调用方写回 slot + 同步预览。
/// [existingDataTypes] 已注册/可复用的数据源类型列表（A3 下拉）。
/// [aiFieldInferrer] 可选：AI 字段推断器；不传则走 URL 回退推断。
class DataSourceCaptureDialog extends StatefulWidget {
  final DesignDocument doc;
  final String slotId;
  final String? pluginsDir;
  final void Function(String type, String outputDir)? onGenerated;
  final void Function(String endpoint)? onEndpointWritten;
  final List<String> existingDataTypes;
  final AiFieldInferrer? aiFieldInferrer;

  const DataSourceCaptureDialog({
    super.key,
    required this.doc,
    required this.slotId,
    this.pluginsDir,
    this.onGenerated,
    this.onEndpointWritten,
    this.existingDataTypes = const [],
    this.aiFieldInferrer,
  });

  @override
  State<DataSourceCaptureDialog> createState() => _DataSourceCaptureDialogState();
}

class _DataSourceCaptureDialogState extends State<DataSourceCaptureDialog> {
  final AutoDataSourceService _service = AutoDataSourceService();
  late final ScraperWorkflow _workflow;
  late final ScraperFlowFacade _facade;

  bool _analyzing = false;
  bool _analyzed = false;
  int _inferredFieldCount = 0;
  bool _generating = false;
  String? _error;
  String? _selectedExisting;

  @override
  void initState() {
    super.initState();
    _workflow = ScraperWorkflow();
    _workflow.onChanged = () {
      if (mounted) setState(() {});
    };
    _workflow.startCapturing();
    _facade = ScraperFlowFacade(workflow: _workflow);
    if (widget.aiFieldInferrer != null) {
      _facade.aiFieldInferrer = widget.aiFieldInferrer;
    }
  }

  @override
  void dispose() {
    _workflow.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_workflow.logs.isEmpty || _analyzing) return;
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final schema = await _facade.analyzeSelection(_workflow.logs);
      _inferredFieldCount = schema.fields.length;
      _analyzed = true;
      debugPrint('[DataSourceCaptureDialog] 分析完成，推断 ${schema.fields.length} 个字段');
    } catch (e) {
      _error = '分析失败: $e';
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _generate() async {
    if (_workflow.logs.isEmpty || _generating) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      await _service.autoGenerateFromCapture(
        doc: widget.doc,
        slotId: widget.slotId,
        capturedLogs: _workflow.logs,
        facade: _facade,
        pluginsDir: widget.pluginsDir,
        onGenerated: widget.onGenerated,
      );
      final ep = _readEndpoint(widget.doc, widget.slotId);
      if (ep == null) {
        throw const AutoDataSourceException(
          reason: 'writeback_failed',
          message: '生成成功但未能回写 endpoint',
        );
      }
      widget.onEndpointWritten?.call(ep);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = '生成失败: $e';
        });
      }
    }
  }

  void _useExisting(String type) {
    final ep = 'orch://$type';
    widget.onEndpointWritten?.call(ep);
    debugPrint('[DataSourceCaptureDialog] 复用已有数据源: $ep');
    Navigator.of(context).pop(true);
  }

  String? _readEndpoint(DesignDocument doc, String slotId) {
    for (final page in doc.pages) {
      for (final slot in page.slots) {
        if (slot.id == slotId) {
          final ds = slot.component?.config['dataSource'];
          if (ds is Map && ds['endpoint'] is String) {
            return ds['endpoint'] as String;
          }
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('自动爬取生成数据源', style: TextStyle(fontSize: 15)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 880,
        height: 560,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 左侧：内嵌浏览器 ──
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: ScraperWebView(
                  initialUrl: 'https://www.baidu.com',
                  onRequestCaptured: (log) => _workflow.addLog(log),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ── 右侧：日志 + 操作 ──
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A3：复用已有数据源
                  if (widget.existingDataTypes.isNotEmpty) ...[
                    const Text('或复用已有数据源：', style: TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('选择已有数据源', style: TextStyle(fontSize: 12)),
                      value: _selectedExisting,
                      items: widget.existingDataTypes.map((t) {
                        return DropdownMenuItem(value: t, child: Text(t));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedExisting = v);
                          _useExisting(v);
                        }
                      },
                    ),
                    const Divider(height: 16),
                  ],
                  // 捕获日志面板
                  Expanded(
                    child: RequestLogPanel(
                      workflow: _workflow,
                      onAnalyze: _analyze,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 分析状态
                  if (_analyzed)
                    Text(
                      '已推断 $_inferredFieldCount 个字段，可生成数据源',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 8),
                  // 操作按钮
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_analyzing || _workflow.logs.isEmpty)
                              ? null
                              : _analyze,
                          icon: _analyzing
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.analytics_rounded, size: 14),
                          label: const Text('分析日志', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_generating ||
                                  _workflow.logs.isEmpty ||
                                  !_analyzed)
                              ? null
                              : _generate,
                          icon: _generating
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 14),
                          label: const Text('生成数据源', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

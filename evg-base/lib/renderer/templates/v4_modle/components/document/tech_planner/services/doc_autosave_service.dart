/// 文档自动保存服务。
///
/// 三种保存策略：
/// - **防抖保存**：最后一次编辑后 2 秒自动触发
/// - **定期保存**：每 30 秒兜底检查（防止防抖遗漏）
/// - **手动保存**：通过 [saveNow()] 立即触发
///
/// JSON 格式保存至 `.greenix/workspaces/<moduleId>/tech-plans/<docId>.json`，
/// 方便 AI 和其他工具直接读取和解析。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/document/tech_planner/models/tech_document.dart';

/// 自动保存状态。
enum AutoSaveStatus { idle, saving, saved, error }

/// 自动保存结果。
class AutoSaveResult {
  final AutoSaveStatus status;
  final DateTime? lastSaved;
  final String? errorMessage;
  final String? filePath;
  final int? byteSize;

  const AutoSaveResult({
    this.status = AutoSaveStatus.idle,
    this.lastSaved,
    this.errorMessage,
    this.filePath,
    this.byteSize,
  });

  bool get isOk => status == AutoSaveStatus.saved;

  factory AutoSaveResult.idle() =>
      const AutoSaveResult(status: AutoSaveStatus.idle);
}

/// 文档自动保存服务。
///
/// 维护 [TechDocument] 的磁盘持久化。存储格式为结构化 JSON，
/// 含文档正文、版本信息、追溯记录，方便 AI 读取和解析。
///
/// 用法：
/// ```dart
/// final svc = DocAutoSaveService(moduleId: 'ai-planner', documentId: doc.id);
/// svc.start();
/// svc.onContentChanged(updatedContent);
/// svc.stop();
/// final saved = await svc.loadSaved();
/// ```
class DocAutoSaveService {
  final String moduleId;
  final String documentId;

  Timer? _debounceTimer;
  Timer? _periodicTimer;

  String _latestContent = '';
  final Map<String, dynamic> _traceExport = {};
  DateTime? _lastSaved;
  String? _lastError;

  // 策略配置
  static const _debounceMs = 2000;
  static const _periodicSec = 30;

  DocAutoSaveService({
    required this.moduleId,
    required this.documentId,
  });

  // ═══════ 生命周期 ═══════

  /// 启动自动保存（开始监听）。
  void start() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(seconds: _periodicSec),
      (_) => _doSave(),
    );
  }

  /// 停止自动保存（取消所有定时器）。
  void stop() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    // 停止前做一次最终保存
    if (_latestContent.isNotEmpty) {
      _doSave();
    }
  }

  /// 释放资源（同 [stop]）。
  void dispose() => stop();

  // ═══════ 内容变更 ═══════

  /// 通知内容已变更，触发防抖保存。
  /// [traceExport] 为可选的追溯记录导出 JSON（由 [DocTraceService.exportJson] 提供）。
  void onContentChanged(String newContent, {Map<String, dynamic>? traceExport}) {
    _latestContent = newContent;
    if (traceExport != null) {
      _traceExport
        ..clear()
        ..addAll(traceExport);
    }

    // 重置防抖
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
      _doSave();
    });
  }

  // ═══════ 保存 / 加载 ═══════

  /// 立即执行一次保存（忽略防抖/周期）。
  Future<AutoSaveResult> saveNow() async {
    _debounceTimer?.cancel();
    return _doSave();
  }

  /// 从磁盘加载已保存的数据。
  ///
  /// 返回 null 表示无已保存文件，返回 [TechDocument] 表示解析成功。
  Future<TechDocument?> loadSaved() async {
    final file = _saveFile;
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;

      return TechDocument.fromJson(json['document'] as Map<String, dynamic>? ?? {});
    } catch (e) {
      _lastError = '加载保存文件失败: $e';
      debugPrint('[DocAutoSaveService] $_lastError');
      return null;
    }
  }

  /// 从磁盘加载已保存的追溯记录。
  ///
  /// 返回 null 表示无已保存文件。
  Future<Map<String, dynamic>?> loadTraceExport() async {
    final file = _saveFile;
    if (!file.existsSync()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final traces = json['traces'] as Map<String, dynamic>?;
      return traces;
    } catch (e) {
      return null;
    }
  }

  // ═══════ 状态查询 ═══════

  /// 最后一次保存时间。
  DateTime? get lastSaved => _lastSaved;

  /// 最近一次错误信息。
  String? get lastError => _lastError;

  /// 当前状态。
  AutoSaveResult get status {
    if (_lastError != null) {
      return AutoSaveResult(
        status: AutoSaveStatus.error,
        errorMessage: _lastError,
        lastSaved: _lastSaved,
      );
    }
    if (_lastSaved != null) {
      return AutoSaveResult(
        status: AutoSaveStatus.saved,
        lastSaved: _lastSaved,
        filePath: _saveFile.path,
      );
    }
    if (_debounceTimer != null && _debounceTimer!.isActive) {
      return AutoSaveResult(status: AutoSaveStatus.saving);
    }
    return AutoSaveResult.idle();
  }

  // ═══════ 内部 ═══════

  File get _saveFile {
    final dir = p.join(greenixWorkspaceDir(moduleId), 'tech-plans');
    return File(p.join(dir, '$documentId.json'));
  }

  Future<AutoSaveResult> _doSave() async {
    if (_latestContent.isEmpty) {
      return AutoSaveResult.idle();
    }

    final file = _saveFile;

    try {
      // 确保目录存在
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // 构建 JSON payload —— 面向 AI 可读性优化
      final now = DateTime.now();
      final payload = <String, dynamic>{
        'schemaVersion': '1.0',
        'savedAt': now.toIso8601String(),
        'moduleId': moduleId,
        'document': {
          'id': documentId,
          'content': _latestContent,
          'updatedAt': now.toIso8601String(),
        },
        // 追溯记录（若提供）
        if (_traceExport.isNotEmpty) 'traces': _traceExport,
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
      await file.writeAsString(jsonStr, flush: true);

      _lastSaved = now;
      _lastError = null;

      debugPrint('[DocAutoSaveService] ✓ 已保存 ${jsonStr.length} bytes → ${file.path}');

      return AutoSaveResult(
        status: AutoSaveStatus.saved,
        lastSaved: _lastSaved,
        filePath: file.path,
        byteSize: jsonStr.length,
      );
    } catch (e) {
      _lastError = e.toString();
      _lastSaved = null;

      debugPrint('[DocAutoSaveService] ✗ 保存失败: $e');

      return AutoSaveResult(
        status: AutoSaveStatus.error,
        errorMessage: _lastError,
      );
    }
  }

  /// 调试断点标志——关键路径上可在此设断点。
  static const bool _debug = false;
  static void debugPrint(String msg) {
    if (_debug) print(msg);
  }
}

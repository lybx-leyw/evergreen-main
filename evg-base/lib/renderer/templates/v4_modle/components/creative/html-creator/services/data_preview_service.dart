/// 数据预览服务 —— 从 DataOrchestrator 加载数据源列表和缓存内容。
/// 增强（B3）：刷新 / 连通性测试走 DataHttpServer（复用 A1 端口发现），
/// 端口文件缺失或 HTTP 失败时降级为直连 DataOrchestrator。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:evergreen_base/core/data/data.dart';
import 'package:evergreen_base/renderer/templates/html_modle/core_api_discovery.dart';
import 'package:evergreen_base/renderer/templates/v4_modle/components/creative/html-creator/models/html_project.dart';

class DataPreviewService {
  final DataOrchestrator orch;

  DataPreviewService(this.orch);

  /// 获取所有已注册数据源的预览列表（不含缓存数据）。
  List<DataSourcePreview> listSources() {
    return orch.allStatuses
        .map((s) => DataSourcePreview(
              name: s.name,
              displayName: s.displayName ?? s.name,
              freshnessLabel: s.freshnessLabel,
              connected: s.connected,
            ))
        .toList();
  }

  /// 获取指定数据源的缓存内容。
  /// 返回 null 表示未注册或无缓存。
  Future<dynamic> fetchPreview(String name) async {
    final dt = orch.typeByName(name);
    if (dt == null) return null;
    try {
      return await orch.fastRead(dt) ?? await orch.get(dt);
    } catch (_) {
      return null;
    }
  }

  /// 强制刷新数据源（B3）。
  ///
  /// 优先走 DataHttpServer `POST /data/types/:name/refresh`（核心真实拉取），
  /// 端口文件缺失 / HTTP 失败时降级为直连 [DataOrchestrator.refresh]。
  /// 返回刷新后的数据；失败返回 null。
  Future<dynamic> refresh(String name) async {
    final port = coreApiDiscovery.portOf(CoreService.data);
    if (port != null) {
      try {
        return await _httpPost(port, '/data/types/$name/refresh');
      } catch (e) {
        debugPrint('[DataPreview] HTTP 刷新 $name 失败，降级直连: $e');
      }
    }
    final dt = orch.typeByName(name);
    if (dt == null) return null;
    try {
      return await orch.refresh(dt);
    } catch (e) {
      debugPrint('[DataPreview] 直连刷新 $name 失败: $e');
      return null;
    }
  }

  /// 测试全部数据源连通性（B3）。
  ///
  /// 走 DataHttpServer `POST /data/connectivity/test`；返回 `{results: [...]}`
  /// 或 `{error: ...}`；DataHttpServer 不可用时返回 null。
  Future<Map<String, dynamic>?> testConnectivity() async {
    final port = coreApiDiscovery.portOf(CoreService.data);
    if (port == null) return null;
    try {
      final res = await _httpPost(port, '/data/connectivity/test');
      return (res as Map<String, dynamic>?) ?? const {};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// 向 DataHttpServer 发 POST JSON 请求，返回解码后的 body。
  Future<dynamic> _httpPost(int port, String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .postUrl(Uri.parse('http://127.0.0.1:$port$path'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      final res = await req.close().timeout(const Duration(seconds: 10));
      final raw = await res.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}: $raw');
      }
      if (raw.isEmpty) return null;
      return jsonDecode(raw);
    } finally {
      client.close(force: true);
    }
  }
}

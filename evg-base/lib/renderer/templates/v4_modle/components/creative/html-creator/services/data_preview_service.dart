/// 数据预览服务 —— 从 DataOrchestrator 加载数据源列表和缓存内容。
/// 契约③：刷新入口语义降级为缓存优先读（不再手动强制拉取）；连通性测试
/// 仍走 DataHttpServer（复用 A1 端口发现）。
library;

import 'dart:convert';
import 'dart:io';

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

  /// 读取指定数据源的缓存内容（契约③ 语义降级）。
  ///
  /// 历史（B3）语义：手动强制刷新——优先走 DataHttpServer `POST /data/types/:name/refresh`
  /// （核心真实拉取），端口缺失 / HTTP 失败时降级直连 [DataOrchestrator.refresh]。
  /// 契约③（数据中枢不再让用户手动控制拉取/重试）下语义降级：不再强制重抓，
  /// 等价于 [fetchPreview] 的缓存优先读（fastRead 内存未命中内部 fallback get()）；
  /// 真实刷新由中枢后台调度（startAutoRefresh/refreshAllStale）维护，UI 经
  /// data:changed 订阅感知变化。方法名与签名保留（向后兼容，不删公开 API）。
  /// 返回缓存数据；失败返回 null。
  Future<dynamic> refresh(String name) async {
    return fetchPreview(name);
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
      final raw = await res
          .transform(utf8.decoder)
          .join()
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

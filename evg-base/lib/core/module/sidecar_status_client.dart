/// sidecar 状态客户端（M5 最小市场 UI 起步 · 纯 Dart 可测层）。
///
/// 封装对 [ModuleHttpServer] `/module/sidecars` 端点的查询，供 marketplace
/// 等 UI 读取「当前运行中 sidecar」列表。不含 Flutter 依赖，可在 core 子包验证。
library;

import 'dart:convert';
import 'dart:io';

import 'runtime.dart';
import 'sidecar/sidecar_controller.dart';

/// 单个 sidecar 的运行时状态（端点响应的扁平视图）。
class SidecarStatus {
  final String id;
  final String name;
  final RuntimeKind kind;
  final String entry;
  final int? port;
  final bool healthy;
  final Map<String, dynamic> capabilities;

  const SidecarStatus({
    required this.id,
    required this.name,
    required this.kind,
    required this.entry,
    required this.port,
    required this.healthy,
    required this.capabilities,
  });

  factory SidecarStatus.fromJson(Map<String, dynamic> json) {
    final sidecar = json['sidecar'] as Map<String, dynamic>?;
    final kindRaw = sidecar?['kind'] as String? ?? 'node';
    return SidecarStatus(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      kind: _parseKind(kindRaw),
      entry: sidecar?['entry'] as String? ?? '',
      port: sidecar?['port'] as int?,
      healthy: sidecar?['healthy'] as bool? ?? false,
      capabilities:
          (sidecar?['capabilities'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  static RuntimeKind _parseKind(String v) {
    for (final k in RuntimeKind.values) {
      if (k.name == v) return k;
    }
    return RuntimeKind.node;
  }
}

/// 解析 `/module/sidecars` 的响应体为状态列表（纯函数，可单测）。
List<SidecarStatus> parseSidecarsResponse(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final list = (decoded['sidecars'] as List?) ?? [];
  return [
    for (final item in list)
      SidecarStatus.fromJson(item as Map<String, dynamic>),
  ];
}

/// sidecar 状态客户端——调用 [ModuleHttpServer] 的 `/module/sidecars`。
class SidecarStatusClient {
  final String host;
  final int port;

  SidecarStatusClient({this.host = 'localhost', required this.port});

  /// 查询当前运行的 sidecar 列表（真实 HTTP GET）。
  Future<List<SidecarStatus>> fetch() async {
    final client = HttpClient();
    try {
      final req = await client.get(host, port, '/module/sidecars');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close();
        return [];
      }
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      return parseSidecarsResponse(body);
    } catch (_) {
      client.close();
      return [];
    }
  }
}

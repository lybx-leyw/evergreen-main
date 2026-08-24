/// 权限执行器（M2-1/M2-2/M2-5）。
///
/// 把「发现能力」变成「强制能力」：manifest 声明的能力 + 六格契约 →
/// 生成不可变 [PermissionTicket]，桥拦截器/sidecar RPC 拦截器据此放行或拒绝。
///
/// 纯 Dart，core 层，无 Flutter / dart:io 依赖，可单测。
library;

import 'capability.dart';
import 'lattice.dart';
import 'resolved_plugin.dart';
import 'runtime.dart';

/// 一次权限裁决请求（桥或 sidecar 拦截器发起）。
///
/// [dimension] 为被请求的能力维度（如 `agent`/`data`）。
/// [operation] 可选，细化到具体动作（如 `platform.api.call`），用于审计。
class PermissionRequest {
  final CapabilityDimension dimension;
  final String? operation;

  const PermissionRequest(this.dimension, {this.operation});

  @override
  String toString() =>
      'PermissionRequest(${dimension.name}${operation != null ? ':$operation' : ''})';
}

/// 不可变权限票据（M2-2）。
///
/// 由 [PermissionResolver] 生成，桥拦截器据此放行或返回标准错误。
/// 含审计字段（时间戳、请求方），便于 [PermissionAudit] 落盘。
class PermissionTicket {
  /// 请求维度。
  final CapabilityDimension dimension;

  /// 细粒度操作（可为 null）。
  final String? operation;

  /// 是否放行。
  final bool granted;

  /// 裁决时间戳（毫秒）。
  final int decidedAtMs;

  /// 拒绝原因（[granted] 为 false 时非空）。
  final String? reason;

  const PermissionTicket({
    required this.dimension,
    required this.granted,
    required this.decidedAtMs,
    this.operation,
    this.reason,
  });

  /// 拒绝票据工厂。
  factory PermissionTicket.denied(
    PermissionRequest req, {
    required String reason,
    int? decidedAtMs,
  }) =>
      PermissionTicket(
        dimension: req.dimension,
        operation: req.operation,
        granted: false,
        decidedAtMs: decidedAtMs ?? _nowMs(),
        reason: reason,
      );

  /// 放行票据工厂。
  factory PermissionTicket.granted(
    PermissionRequest req, {
    int? decidedAtMs,
  }) =>
      PermissionTicket(
        dimension: req.dimension,
        operation: req.operation,
        granted: true,
        decidedAtMs: decidedAtMs ?? _nowMs(),
      );

  /// 标准错误响应体（桥拦截器直接返回给插件）。
  Map<String, dynamic> toErrorJson() => {
        'error': 'permission_denied',
        'dimension': dimension.name,
        if (operation != null) 'operation': operation,
        if (reason != null) 'reason': reason,
      };

  @override
  String toString() =>
      'PermissionTicket(${dimension.name}:${granted ? 'allow' : 'deny'})';
}

/// 权限解析器（M2-1）——单一事实源驱动的强制裁决。
///
/// 输入 [ResolvedPlugin]（已含 lattice + runtime capabilities）。
/// 产出：该插件被允许的能力维度集合 + 对任意请求的 [PermissionTicket]。
class PermissionResolver {
  final ResolvedPlugin plugin;

  /// 该插件被允许的能力维度（不可变，由契约推导）。
  final Set<CapabilityDimension> grantedDimensions;

  PermissionResolver._(this.plugin, this.grantedDimensions);

  /// 从 [ResolvedPlugin] 推导允许维度（M0·3.4 单一事实源衔接）。
  ///
  /// 推导规则（能力只窄不宽）：
  /// 1. 六格 → 默认维度（[latticeToCapability]）。
  /// 2. sidecar 额外按 [RuntimeCapabilities] 收窄：
  ///    - `spawn` 非空 → 追加 [CapabilityDimension.process]（可启子进程）。
  ///    - `net.allow` 非空 → 追加 [CapabilityDimension.data]（可联网取数）。
  ///    - 否则即便 sidecar，net/spawn 为空也不额外授权。
  factory PermissionResolver.fromResolved(ResolvedPlugin plugin) {
    final granted = <CapabilityDimension>{};
    final base = latticeToCapability(plugin.lattice);
    if (base != null) granted.add(base);

    final caps = plugin.capabilities;
    if (caps.spawnAllow.isNotEmpty) granted.add(CapabilityDimension.process);
    if (caps.netAllow.isNotEmpty) granted.add(CapabilityDimension.data);

    return PermissionResolver._(plugin, granted);
  }

  /// 裁决一次请求 → [PermissionTicket]（纯函数，可单测）。
  PermissionTicket resolve(PermissionRequest req) {
    if (grantedDimensions.contains(req.dimension)) {
      return PermissionTicket.granted(req);
    }
    return PermissionTicket.denied(
      req,
      reason: '插件 "${plugin.id}" 未声明 ${req.dimension.name} 能力'
          '（lattice=${plugin.lattice.name}）',
    );
  }

  /// 便捷判断：是否允许某维度。
  bool allows(CapabilityDimension dim) => grantedDimensions.contains(dim);
}

/// 桥版本握手（M2-5，纯逻辑）。
///
/// 插件启动 → `platform.hello({bridge, wants})` → 宿主返回 `{bridge, granted}`。
/// [granted] 必须是 [wants] 的子集（能力只窄不宽）。
class BridgeHandshake {
  /// 宿主支持的 bridge 协议版本。
  final int bridgeVersion;

  /// 宿主实际支持的维度全集（来自 [PermissionResolver.grantedDimensions]）。
  final Set<CapabilityDimension> supported;

  const BridgeHandshake({
    required this.bridgeVersion,
    required this.supported,
  });

  /// 处理插件 hello，返回协商结果（纯函数）。
  ///
  /// [wants] 为插件想要的维度；返回授予的子集（≤ wants）。
  BridgeHandshakeResult hello({
    required int bridge,
    required List<CapabilityDimension> wants,
  }) {
    final granted = wants.where((d) => supported.contains(d)).toList();
    return BridgeHandshakeResult(
      bridge: bridgeVersion,
      granted: granted,
      requestedBridge: bridge,
    );
  }
}

/// 握手协商结果（纯数据）。
class BridgeHandshakeResult {
  /// 宿主选定的 bridge 版本（取 min(宿主版本, 请求版本) 策略由调用方定，此处回显宿主版本）。
  final int bridge;

  /// 实际授予的维度（≤ wants）。
  final List<CapabilityDimension> granted;

  /// 插件请求的 bridge 版本（回显，便于插件判断是否降级）。
  final int requestedBridge;

  const BridgeHandshakeResult({
    required this.bridge,
    required this.granted,
    required this.requestedBridge,
  });

  Map<String, dynamic> toJson() => {
        'bridge': bridge,
        'granted': granted.map((d) => d.name).toList(),
      };
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 审计条目（M2-4，纯数据）。
class PermissionAuditEntry {
  final PermissionTicket ticket;
  /// 调用方标识（插件 id 或桥 session id）。
  final String subject;
  /// 来源（'bridge' / 'sidecar'）。
  final String source;

  PermissionAuditEntry(this.ticket, this.subject, this.source);

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'source': source,
        'dimension': ticket.dimension.name,
        if (ticket.operation != null) 'operation': ticket.operation,
        'granted': ticket.granted,
        'decidedAtMs': ticket.decidedAtMs,
        if (ticket.reason != null) 'reason': ticket.reason,
      };
}

/// 审计收集器（M2-4）。
///
/// 纯内存收集，可单测；真实落盘由宿主注入 [sink]（如写文件）。
/// 不依赖 dart:io，便于在 core 子包内验证。
class PermissionAudit {
  final List<PermissionAuditEntry> _entries = [];

  /// 可选外部 sink（每条审计落盘）。为 null 时仅内存保留。
  final void Function(PermissionAuditEntry entry)? sink;

  PermissionAudit({this.sink});

  /// 记录一次裁决。
  void record(PermissionTicket ticket, String subject, String source) {
    final e = PermissionAuditEntry(ticket, subject, source);
    _entries.add(e);
    sink?.call(e);
  }

  /// 已记录条目（不可变视图）。
  List<PermissionAuditEntry> get entries =>
      List.unmodifiable(_entries);

  /// 被拒绝的条目（便于告警/统计）。
  List<PermissionAuditEntry> get denied =>
      _entries.where((e) => !e.ticket.granted).toList();
}

/// 桥拦截器（M2-3，纯逻辑）。
///
/// 在 `platform.*` 调用进入 core 服务前裁决：授权 → 返回 null（放行）；
/// 越权 → 返回 [PermissionTicket.toErrorJson()]（标准错误体）。同时写审计。
class BridgeInterceptor {
  final PermissionResolver resolver;
  final PermissionAudit? audit;
  final String subject;

  BridgeInterceptor(this.resolver, {this.audit, required this.subject});

  /// 裁决一次桥调用。
  ///
  /// 返回 null 表示放行；返回 Map 表示拒绝（标准错误体）。
  Map<String, dynamic>? intercept(CapabilityDimension dimension,
      {String? operation, String source = 'bridge'}) {
    final req = PermissionRequest(dimension, operation: operation);
    final ticket = resolver.resolve(req);
    audit?.record(ticket, subject, source);
    if (ticket.granted) return null;
    return ticket.toErrorJson();
  }
}

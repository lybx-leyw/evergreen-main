/// 外部数据源清单模型——统一解析 `data/manifest.json`，覆盖模型 A（CLI 一次性脚本）
/// 与模型 B（HTTP 长驻 .exe）两种形态，声明数据类型与可选能力。
///
/// # 公开 API
///
/// | 成员 | 说明 |
/// |------|------|
/// | `DataSourceManifest.fromJson(json)` | 从 JSON 解析；校验 `type == "data-source"`，`script`/`process` 互斥二选一 |
/// | `DataSourceManifest.fromJsonString(str)` | 从 JSON 字符串解析 |
/// | `DataSourceTypeDecl.fromJson(json)` | 从 JSON 解析 |
/// | `.toJson()` | 序列化回 JSON（可选段仅非默认值写出） |
/// | `DataSourceManifest` | 顶层清单字段（含 `script`/`process`/`auth`） |
/// | `DataSourceProcess` | 进程声明（吸收 ProcessDescriptor 语义，String 兼容） |
/// | `DataSourceTypeDecl` | 类型字段（含 `typeArg`/`stream`/`file`） |
/// | `.toDataType()` | 转换为 [DataType] |
/// | `.buildUrl(port)` | 将 `{port}` 占位符替换为实际端口 |
/// | `parseDataSourceTtl(raw)` | 共享 TTL 解析器（s/m/h/ms/纯秒数） |
/// | `parseDataSourceAndroidSupport(raw)` | 严格 bool 解析（非 bool 不再视为 true） |
///
/// 向后兼容：旧 manifest（模型 A 缺 `id`/`name`、模型 B `process` 为字符串、`endpoint`
/// 仅模型 B 必填）全部仍可解析；未知字段静默忽略；新增可选段（`auth`/`stream`/`file`）
/// 缺省零行为变化。
library;

import 'dart:convert';

import '../type.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 共享解析器
// ═══════════════════════════════════════════════════════════════════════════

/// 共享 TTL 解析器——单一实现，供模型 A/B 复用。
///
/// 支持：
/// - 纯整数/字符串数字 → 秒数（如 `"90"` / `90`）
/// - 带单位 `h`/`m`/`s`/`ms`（如 `"1h"`、`"30m"`、`"60s"`、`"500ms"`，大小写小写）
/// - 无法识别 → `null`（调用方回落默认值，不抛）
Duration? parseDataSourceTtl(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return Duration(seconds: raw);
  final s = raw.toString().trim();
  final m = RegExp(r'^(\d+)\s*(h|m|s|ms)$').firstMatch(s);
  if (m == null) {
    final secs = int.tryParse(s);
    return secs != null ? Duration(seconds: secs) : null;
  }
  final v = int.parse(m.group(1)!);
  return switch (m.group(2)) {
    'h' => Duration(hours: v),
    'm' => Duration(minutes: v),
    's' => Duration(seconds: v),
    'ms' => Duration(milliseconds: v),
    _ => null,
  };
}

/// 严格 bool 解析 `androidSupport`——仅接受真实 [bool]。
///
/// - 缺失 / `null` → `true`（默认加载）
/// - `true` / `false` → 原值
/// - 其它类型（字符串/数字/数组/对象）→ `false`（fail-closed：非 bool 不再视为 true，
///   避免把 `"false"` 这类笔误误判为「支持安卓」而触发 C 扩展崩溃）
bool parseDataSourceAndroidSupport(dynamic raw) {
  if (raw == null) return true;
  return raw is bool ? raw : false;
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceAuth（可选声明：凭据/会话引用）
// ═══════════════════════════════════════════════════════════════════════════

/// 数据源认证声明（可选，缺省零行为变化）。
///
/// 仅**引用** `.greenix/config.json` 中已声明的凭据 key（复用 config 的 `isSecure`），
/// 不在此重复声明凭据值，避免双真相源。
class DataSourceAuth {
  /// 会话提供者标识（如 `"zju"`，供上层 SessionProvider 路由；本模型仅声明不消费）。
  final String? sessionProvider;

  /// 数据来源网站域（如 `"jwxt.zju.edu.cn"`）——**登录锁分组键**：
  /// 声明后，从同一域拉取的数据源共享同一把登录锁（单点重登去重），比按
  /// sessionProvider 分组更细；缺省（null）时回退到 sessionProvider 分组（零行为变化）。
  /// 同一 [sessionDomain] 应声明同一 [sessionProvider]（域决定登录实现归属）。
  final String? sessionDomain;

  /// 引用的凭据 key 列表（对应 config.json 已声明 key）。
  final List<String> credentialKeys;

  const DataSourceAuth(
      {this.sessionProvider, this.sessionDomain, this.credentialKeys = const []});

  /// 解析 [json]；`null` 或空对象 → `null`（未声明）。
  static DataSourceAuth? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final keys = json['credentialKeys'];
    return DataSourceAuth(
      sessionProvider: json['sessionProvider'] as String?,
      sessionDomain: json['sessionDomain'] as String?,
      credentialKeys:
          keys is List ? keys.map((e) => e.toString()).toList() : const [],
    );
  }

  /// 是否无任何声明内容（用于 `toJson` 省略）。
  bool get isEmpty =>
      sessionProvider == null &&
      sessionDomain == null &&
      credentialKeys.isEmpty;

  Map<String, dynamic> toJson() => {
        if (sessionProvider != null) 'sessionProvider': sessionProvider,
        if (sessionDomain != null) 'sessionDomain': sessionDomain,
        if (credentialKeys.isNotEmpty) 'credentialKeys': credentialKeys,
      };

  @override
  bool operator ==(Object other) =>
      other is DataSourceAuth &&
      other.sessionProvider == sessionProvider &&
      other.sessionDomain == sessionDomain &&
      _listEquals(other.credentialKeys, credentialKeys);

  @override
  int get hashCode => Object.hash(
      sessionProvider, sessionDomain, Object.hashAll(credentialKeys));

  @override
  String toString() =>
      'DataSourceAuth(sessionProvider: $sessionProvider, sessionDomain: $sessionDomain, keys: $credentialKeys)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceProcess（顶层 process 增强：吸收 ProcessDescriptor 语义）
// ═══════════════════════════════════════════════════════════════════════════

/// 进程声明——吸收 module [ProcessDescriptor] 语义，同时兼容旧的字符串形态。
///
/// 顶层 `process` 可为：
/// - 字符串 `"server.py"`（向后兼容）：等价 `DataSourceProcess(exe: "server.py")`；
/// - 对象 `{ "exe": "server.py", "scope": "long", "autoStart": true, ... }`。
class DataSourceProcess {
  /// 可执行文件/脚本入口名（对象形态的 `exe`，兼容 `entry`）。
  final String exe;

  /// 进程作用域：`"long"`（常驻）| `"short"`（一次性）。默认 `long`。
  final String scope;

  /// 是否自动启动。默认 `true`。
  final bool autoStart;

  /// 崩溃后是否自动重启（仅 `long` 作用域）。默认 `false`。
  final bool autoRestart;

  /// 通信协议：`"http"` | `"stdio"`。默认 `"http"`。
  final String protocol;

  /// 优先端口（`http` 协议），0 = 自动分配。默认 0。
  final int preferredPort;

  const DataSourceProcess({
    required this.exe,
    this.scope = 'long',
    this.autoStart = true,
    this.autoRestart = false,
    this.protocol = 'http',
    this.preferredPort = 0,
  });

  /// 是否携带增强字段（决定 `toJson` 走字符串还是对象形态）。
  bool get hasEnhancedFields =>
      scope != 'long' ||
      !autoStart ||
      autoRestart ||
      protocol != 'http' ||
      preferredPort != 0;

  /// 解析：字符串 → 仅 exe；对象 → 完整字段；其它 → 抛 [FormatException]。
  factory DataSourceProcess.fromJson(dynamic raw) {
    if (raw is String) return DataSourceProcess(exe: raw);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      return DataSourceProcess(
        exe: map['exe'] as String? ?? map['entry'] as String? ?? '',
        scope: map['scope'] as String? ?? 'long',
        autoStart: map['autoStart'] as bool? ?? true,
        autoRestart: map['autoRestart'] as bool? ?? false,
        protocol: map['protocol'] as String? ?? 'http',
        preferredPort: map['preferredPort'] as int? ?? 0,
      );
    }
    throw FormatException('process 必须为字符串或对象，实际为: ${raw.runtimeType}');
  }

  /// 序列化：无增强字段时回退为字符串（向后兼容），否则输出对象（仅非默认字段）。
  dynamic toJson() {
    if (!hasEnhancedFields) return exe;
    return <String, dynamic>{
      'exe': exe,
      if (scope != 'long') 'scope': scope,
      if (!autoStart) 'autoStart': false,
      if (autoRestart) 'autoRestart': true,
      if (protocol != 'http') 'protocol': protocol,
      if (preferredPort != 0) 'preferredPort': preferredPort,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DataSourceProcess &&
      other.exe == exe &&
      other.scope == scope &&
      other.autoStart == autoStart &&
      other.autoRestart == autoRestart &&
      other.protocol == protocol &&
      other.preferredPort == preferredPort;

  @override
  int get hashCode =>
      Object.hash(exe, scope, autoStart, autoRestart, protocol, preferredPort);

  @override
  String toString() =>
      'DataSourceProcess($exe, scope:$scope, protocol:$protocol)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceStreamDecl / DataSourceFileDecl（dataTypes[] 可选能力）
// ═══════════════════════════════════════════════════════════════════════════

/// 流式声明（可选，缺省零行为变化）。
class DataSourceStreamDecl {
  /// 是否启用流式。默认 `false`。
  final bool enabled;

  /// 流协议：`hls` | `mp4` | `http-flv` | `sse` | `stdio-jsonl`。
  final String? protocol;

  /// 媒体 MIME（如 `video/mp4`）。
  final String? mime;

  /// 拉流是否需要携带凭据头。默认 `false`。
  final bool credentialed;

  const DataSourceStreamDecl({
    this.enabled = false,
    this.protocol,
    this.mime,
    this.credentialed = false,
  });

  /// 解析 [json]；`null` → `null`（未声明）。
  static DataSourceStreamDecl? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return DataSourceStreamDecl(
      enabled: json['enabled'] as bool? ?? false,
      protocol: json['protocol'] as String?,
      mime: json['mime'] as String?,
      credentialed: json['credentialed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (protocol != null) 'protocol': protocol,
        if (mime != null) 'mime': mime,
        if (credentialed) 'credentialed': true,
      };

  @override
  bool operator ==(Object other) =>
      other is DataSourceStreamDecl &&
      other.enabled == enabled &&
      other.protocol == protocol &&
      other.mime == mime &&
      other.credentialed == credentialed;

  @override
  int get hashCode => Object.hash(enabled, protocol, mime, credentialed);

  @override
  String toString() =>
      'DataSourceStreamDecl(enabled: $enabled, protocol: $protocol)';
}

/// 文件下载声明（可选，缺省零行为变化）。
class DataSourceFileDecl {
  /// 是否启用文件下载。默认 `false`。
  final bool enabled;

  /// 下载端点（`{port}` 由平台替换）。
  final String? downloadEndpoint;

  const DataSourceFileDecl({this.enabled = false, this.downloadEndpoint});

  /// 解析 [json]；`null` → `null`（未声明）。
  static DataSourceFileDecl? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return DataSourceFileDecl(
      enabled: json['enabled'] as bool? ?? false,
      downloadEndpoint: json['downloadEndpoint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (downloadEndpoint != null) 'downloadEndpoint': downloadEndpoint,
      };

  @override
  bool operator ==(Object other) =>
      other is DataSourceFileDecl &&
      other.enabled == enabled &&
      other.downloadEndpoint == downloadEndpoint;

  @override
  int get hashCode => Object.hash(enabled, downloadEndpoint);

  @override
  String toString() =>
      'DataSourceFileDecl(enabled: $enabled, endpoint: $downloadEndpoint)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceManifest
// ═══════════════════════════════════════════════════════════════════════════

/// 外部数据源插件清单（模型 A + 模型 B 统一）。
class DataSourceManifest {
  /// 全局唯一标识。模型 A 允许缺省（由目录 basename 派生），模型 B 建议填写。
  final String id;

  /// 展示名。缺省为空（消费方回落）。
  final String name;

  /// 模型 A：CLI 脚本文件名（相对 `data/` 目录）。与 [process] 互斥二选一。
  final String? script;

  /// 模型 B：进程声明（字符串或对象形态）。与 [script] 互斥二选一。
  final DataSourceProcess? process;

  /// 脚本运行时：`native`（默认）/ `python`。
  final String runtime;

  /// 有效优先端口（对象形态 `process.preferredPort` 优先，其次顶层字段），0 = 自动分配。
  final int preferredPort;

  /// 数据类型声明（非空）。
  final List<DataSourceTypeDecl> dataTypes;

  /// 安卓支持开关（严格 bool 解析）。默认 true。
  final bool androidSupport;

  /// 可选认证声明（缺省 null，零行为变化）。
  final DataSourceAuth? auth;

  const DataSourceManifest({
    this.id = '',
    this.name = '',
    this.script,
    this.process,
    this.runtime = 'native',
    this.preferredPort = 0,
    required this.dataTypes,
    this.androidSupport = true,
    this.auth,
  });

  factory DataSourceManifest.fromJson(Map<String, dynamic> json) {
    _requireField(json, 'type', 'data-source');

    final rawScript = json['script'] as String?;
    final script =
        (rawScript != null && rawScript.isNotEmpty) ? rawScript : null;
    final processRaw = json['process'];
    final DataSourceProcess? process =
        processRaw == null ? null : DataSourceProcess.fromJson(processRaw);

    if (script == null && process == null) {
      throw const FormatException('缺少必填字段: script 或 process（二选一）');
    }
    if (script != null && process != null) {
      throw const FormatException('script 与 process 互斥，只能二选一');
    }

    final topPort = json['preferredPort'] as int? ?? 0;
    final preferredPort = (process != null && process.preferredPort != 0)
        ? process.preferredPort
        : topPort;

    return DataSourceManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      script: script,
      process: process,
      runtime: json['runtime'] as String? ?? 'native',
      preferredPort: preferredPort,
      dataTypes: _requireList(json, 'dataTypes')
          .map((d) => DataSourceTypeDecl.fromJson(d as Map<String, dynamic>))
          .toList(),
      androidSupport: parseDataSourceAndroidSupport(json['androidSupport']),
      auth: DataSourceAuth.fromJson(json['auth'] as Map<String, dynamic>?),
    );
  }

  /// 模型 B 进程入口名（`process?.exe`）。模型 A（script）时为空字符串。
  String get processExe => process?.exe ?? '';

  /// 安卓是否应加载该数据源。`isAndroid=true` 且 `androidSupport=false` 时返回 false。
  static bool isSupportedOn(DataSourceManifest m, {required bool isAndroid}) =>
      !(isAndroid && !m.androidSupport);

  factory DataSourceManifest.fromJsonString(String jsonString) =>
      DataSourceManifest.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'type': 'data-source',
        if (id.isNotEmpty) 'id': id,
        if (name.isNotEmpty) 'name': name,
        if (script != null) 'script': script,
        if (process != null) 'process': process!.toJson(),
        if (runtime != 'native') 'runtime': runtime,
        if (!androidSupport) 'androidSupport': false,
        if (preferredPort != 0 &&
            (process == null || process!.preferredPort == 0))
          'preferredPort': preferredPort,
        'dataTypes': dataTypes.map((d) => d.toJson()).toList(),
        if (auth != null && !auth!.isEmpty) 'auth': auth!.toJson(),
      };

  @override
  String toString() => 'DataSourceManifest($id, ${dataTypes.length} types)';
}

// ═══════════════════════════════════════════════════════════════════════════
// DataSourceTypeDecl
// ═══════════════════════════════════════════════════════════════════════════

/// 单个数据类型声明。
class DataSourceTypeDecl {
  final String name;

  /// 传给 CLI 脚本的 `--type` 参数（模型 A）。缺省同 [name]。
  final String? typeArg;

  /// 分类标签，默认 `"未分类"`（模型 A/B 统一语义）。
  final String category;

  final String? displayName;

  /// 缓存有效期，默认 5 分钟（支持 s/m/h/ms/纯秒数）。
  final Duration ttl;

  final String? persistentKey;

  /// HTTP 接口路径（仅模型 B 必填，模型 A 可缺省）。`{port}` 由 Loader 替换。
  final String? endpoint;

  /// 可选流式声明（缺省 null）。
  final DataSourceStreamDecl? stream;

  /// 可选文件下载声明（缺省 null）。
  final DataSourceFileDecl? file;

  /// 可选静态兜底（缺省 null，零行为变化）：拉取失败且无旧缓存时由
  /// [DataOrchestrator] 返回该 JSON（顶层 Map），并标记 lastError「使用静态兜底」。
  final Map<String, dynamic>? fallbackJson;

  const DataSourceTypeDecl({
    required this.name,
    this.typeArg,
    this.category = '未分类',
    this.displayName,
    this.ttl = const Duration(minutes: 5),
    this.persistentKey,
    this.endpoint,
    this.stream,
    this.file,
    this.fallbackJson,
  });

  factory DataSourceTypeDecl.fromJson(Map<String, dynamic> json) {
    return DataSourceTypeDecl(
      name: _require(json, 'name'),
      typeArg: json['typeArg'] as String?,
      category: json['category'] as String? ?? '未分类',
      displayName: json['displayName'] as String?,
      ttl: parseDataSourceTtl(json['ttl']) ?? const Duration(minutes: 5),
      persistentKey: json['persistentKey'] as String?,
      endpoint: json['endpoint'] as String?,
      stream: DataSourceStreamDecl.fromJson(
          json['stream'] as Map<String, dynamic>?),
      file: DataSourceFileDecl.fromJson(json['file'] as Map<String, dynamic>?),
      fallbackJson: json['fallbackJson'] is Map
          ? Map<String, dynamic>.from(json['fallbackJson'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (typeArg != null && typeArg != name) 'typeArg': typeArg,
        'category': category,
        if (displayName != null) 'displayName': displayName,
        'ttl': _fmtDuration(ttl),
        if (persistentKey != null) 'persistentKey': persistentKey,
        if (endpoint != null) 'endpoint': endpoint,
        if (stream != null && stream!.enabled) 'stream': stream!.toJson(),
        if (file != null && file!.enabled) 'file': file!.toJson(),
        if (fallbackJson != null) 'fallbackJson': fallbackJson,
      };

  /// 转换为 DataOrchestrator 可用的 [DataType]。
  DataType<dynamic> toDataType() => DataType<dynamic>(
        name: name,
        category: category,
        displayName: displayName,
        ttl: ttl,
        persistentKey: persistentKey,
        fallback: fallbackJson,
      );

  /// 用实际端口替换 `{port}` 占位符（模型 B）。缺 [endpoint] 时抛 [StateError]。
  String buildUrl(int port) {
    final ep = endpoint;
    if (ep == null || ep.isEmpty) {
      throw StateError('数据源类型 $name 缺少 endpoint（模型 B 必填）');
    }
    return ep.replaceAll('{port}', '$port');
  }

  @override
  String toString() =>
      'DataSourceTypeDecl($name${endpoint != null ? ' → $endpoint' : ''}, '
      'ttl: ${_fmtDuration(ttl)})';
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部
// ═══════════════════════════════════════════════════════════════════════════

String _require(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || (value is String && value.isEmpty)) {
    throw FormatException('缺少必填字段: $key');
  }
  return value as String;
}

void _requireField(Map<String, dynamic> json, String key, String expected) {
  final value = json[key] as String?;
  if (value != expected) {
    throw FormatException('$key 必须为 "$expected"，实际为: $value');
  }
}

List<dynamic> _requireList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.isEmpty) {
    throw FormatException('缺少必填字段: $key (需要非空数组)');
  }
  return value;
}

String _fmtDuration(Duration d) {
  final sec = d.inMicroseconds ~/ Duration.microsecondsPerSecond;
  if (sec >= 3600 && sec % 3600 == 0) return '${sec ~/ 3600}h';
  if (sec >= 60 && sec % 60 == 0) return '${sec ~/ 60}m';
  if (sec > 0) return '${sec}s';
  return '${d.inMilliseconds}ms';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

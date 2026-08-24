/// sidecar 运行时描述符——语言运行时侧车的契约声明（仅 `sidecar` 格非空）。
///
/// 设计上游：`evg-base/docs/m0-lattice-contract-design.md` §2.2 / §2.3。
///
/// # 红线
/// - fail-closed：非法 `kind`/`protocol`/`fs.scope`/`net.allow` 条目一律
///   [FormatException]，绝不静默放宽。
/// - deny-all 默认：`RuntimeCapabilities` 三字段缺省 = 零权限。
/// - 未知 capability 键（如 `net.wildcard`）→ 静默忽略（沿用「未知字段静默忽略」约定）。
library;

/// 文件作用域（[RuntimeCapabilities.fsScope]）。
enum FileScope {
  /// 无文件系统访问。
  none,

  /// 仅插件自身目录。
  pluginDir,

  /// 应用数据目录（v1 上限，无 `home`、无绝对路径）。
  appData,
}

/// sidecar 语言运行时种类（[RuntimeDescriptor.kind]）。
enum RuntimeKind {
  /// Node.js。
  node,

  /// Python。
  python,

  /// Deno。
  deno,
}

/// sidecar 通信协议（[RuntimeDescriptor.protocol]）。
enum RuntimeProtocol {
  /// HTTP（端口 + JSON RPC）。
  http,

  /// stdio（行协议）。
  stdio,
}

const Map<RuntimeKind, String> _runtimeKindWire = {
  RuntimeKind.node: 'node',
  RuntimeKind.python: 'python',
  RuntimeKind.deno: 'deno',
};

const Map<RuntimeProtocol, String> _runtimeProtocolWire = {
  RuntimeProtocol.http: 'http',
  RuntimeProtocol.stdio: 'stdio',
};

const Map<FileScope, String> _fileScopeWire = {
  FileScope.none: 'none',
  FileScope.pluginDir: 'plugin-dir',
  FileScope.appData: 'app-data',
};

RuntimeKind parseRuntimeKind(String value) {
  final v = value.trim().toLowerCase();
  for (final e in _runtimeKindWire.entries) {
    if (e.value == v) return e.key;
  }
  throw FormatException(
      '非法的 runtime.kind "$value"：必须是 ${_runtimeKindWire.values.join(' / ')} 之一');
}

RuntimeProtocol parseRuntimeProtocol(String value) {
  final v = value.trim().toLowerCase();
  for (final e in _runtimeProtocolWire.entries) {
    if (e.value == v) return e.key;
  }
  throw FormatException(
      '非法的 runtime.protocol "$value"：必须是 ${_runtimeProtocolWire.values.join(' / ')} 之一');
}

FileScope parseFileScope(String value) {
  final v = value.trim().toLowerCase();
  for (final e in _fileScopeWire.entries) {
    if (e.value == v) return e.key;
  }
  throw FormatException(
      '非法的 fs.scope "$value"：必须是 ${_fileScopeWire.values.join(' / ')} 之一'
      '（v1 禁止 home / 绝对路径）');
}

String formatRuntimeKind(RuntimeKind k) => _runtimeKindWire[k]!;
String formatRuntimeProtocol(RuntimeProtocol p) => _runtimeProtocolWire[p]!;
String formatFileScope(FileScope s) => _fileScopeWire[s]!;

/// sidecar 运行时的能力申请（flat 键）。
///
/// 三字段全缺省 = 零权限（deny-all）。能力只窄不宽。
class RuntimeCapabilities {
  /// 文件系统作用域。默认 [FileScope.none]。
  final FileScope fsScope;

  /// 网络白名单（`host` 或 `host:port`）。默认 `[]`。
  final List<String> netAllow;

  /// 子进程可执行名白名单。默认 `[]`（空 = 禁子进程）。
  final List<String> spawnAllow;

  const RuntimeCapabilities({
    this.fsScope = FileScope.none,
    this.netAllow = const [],
    this.spawnAllow = const [],
  });

  /// 是否为 deny-all（零权限）。
  bool get isDenyAll =>
      fsScope == FileScope.none && netAllow.isEmpty && spawnAllow.isEmpty;

  factory RuntimeCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RuntimeCapabilities();

    // 未知 capability 键静默忽略；只处理已知三键。
    FileScope fsScope = FileScope.none;
    if (json['fs.scope'] != null) {
      final raw = json['fs.scope'];
      if (raw is! String) {
        throw FormatException('capabilities.fs.scope 必须是字符串');
      }
      fsScope = parseFileScope(raw);
    }

    final netAllow = _parseNetAllow(json['net.allow']);
    final spawnAllow = _parseSpawnAllow(json['spawn']);

    return RuntimeCapabilities(
      fsScope: fsScope,
      netAllow: netAllow,
      spawnAllow: spawnAllow,
    );
  }

  Map<String, dynamic> toJson() {
    // deny-all 时调用方负责省略整个 capabilities 键（见 §3 序列化约定）。
    final m = <String, dynamic>{};
    if (fsScope != FileScope.none) m['fs.scope'] = formatFileScope(fsScope);
    if (netAllow.isNotEmpty) m['net.allow'] = netAllow;
    if (spawnAllow.isNotEmpty) m['spawn'] = spawnAllow;
    return m;
  }
}

/// 校验 `net.allow` 条目：白名单制，v1 禁止 `*`、空串、`file://` 类。
List<String> _parseNetAllow(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('capabilities.net.allow 必须是字符串数组');
  }
  final out = <String>[];
  for (final item in raw) {
    if (item is! String || item.isEmpty) {
      throw FormatException('capabilities.net.allow 条目必须是非空字符串');
    }
    if (item == '*') {
      throw FormatException('capabilities.net.allow 禁止通配符 "*"（白名单制）');
    }
    if (item.startsWith('file://')) {
      throw FormatException('capabilities.net.allow 禁止 file:// 条目');
    }
    out.add(item);
  }
  return List.unmodifiable(out);
}

/// 校验 `spawn`：可执行名白名单字符串数组。
List<String> _parseSpawnAllow(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('capabilities.spawn 必须是字符串数组');
  }
  final out = <String>[];
  for (final item in raw) {
    if (item is! String || item.isEmpty) {
      throw FormatException('capabilities.spawn 条目必须是非空字符串');
    }
    out.add(item);
  }
  return List.unmodifiable(out);
}

/// sidecar 运行时描述符（仅 `sidecar` 格非空）。
class RuntimeDescriptor {
  /// 语言运行时种类（必填）。
  final RuntimeKind kind;

  /// 相对插件根的入口路径（必填）。
  final String entry;

  /// 通信协议。默认 [RuntimeProtocol.http]。
  final RuntimeProtocol protocol;

  /// 监听端口。`0` = 宿主自动分配。默认 `0`。
  final int port;

  /// 优雅停机超时（毫秒）。默认 `8000`。
  final int gracefulTimeoutMs;

  /// 能力申请。默认 deny-all。
  final RuntimeCapabilities capabilities;

  const RuntimeDescriptor({
    required this.kind,
    required this.entry,
    this.protocol = RuntimeProtocol.http,
    this.port = 0,
    this.gracefulTimeoutMs = 8000,
    this.capabilities = const RuntimeCapabilities(),
  });

  factory RuntimeDescriptor.fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'];
    if (kindRaw is! String) {
      throw FormatException('runtime.kind 必填（node / python / deno）');
    }
    final entry = json['entry'];
    if (entry is! String || entry.isEmpty) {
      throw FormatException('runtime.entry 必填且不能为空串');
    }

    final protocolRaw = json['protocol'] as String? ?? 'http';
    final port = json['port'] as int? ?? 0;
    final gracefulTimeoutMs = json['gracefulTimeoutMs'] as int? ?? 8000;

    return RuntimeDescriptor(
      kind: parseRuntimeKind(kindRaw),
      entry: entry,
      protocol: parseRuntimeProtocol(protocolRaw),
      port: port,
      gracefulTimeoutMs: gracefulTimeoutMs,
      capabilities: RuntimeCapabilities.fromJson(
        json['capabilities'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'kind': formatRuntimeKind(kind),
      'entry': entry,
    };
    if (protocol != RuntimeProtocol.http) {
      m['protocol'] = formatRuntimeProtocol(protocol);
    }
    if (port != 0) m['port'] = port;
    if (gracefulTimeoutMs != 8000) m['gracefulTimeoutMs'] = gracefulTimeoutMs;
    if (!capabilities.isDenyAll) {
      m['capabilities'] = capabilities.toJson();
    }
    return m;
  }
}

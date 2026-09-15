/// 文件型插件清单模型——解析 `plugins/<id>/files/manifest.json`
/// （`type: "file-source"`）。
///
/// 方案：`docs/plugin-registry/file-source-plugin-plan-v1.md` §2。
///
/// 与 `data-source` 是**并列的独立类型**（而非同一清单里的字段开关）：
/// 数据主体是「文件」的插件与数据主体是「业务 JSON」的插件，其契约、校验、
/// 消费方（UI）与演进路径都不同，显式分开更清晰。
///
/// # 复用（零重复）
/// 本模型**不重复实现**任何既有解析器，全部复用 `data_source_manifest.dart`：
/// | 能力 | 复用符号 |
/// | --- | --- |
/// | TTL（`s`/`m`/`h`/`ms`） | `parseDataSourceTtl` |
/// | `androidSupport` fail-closed | `parseDataSourceAndroidSupport` |
/// | per-type 超时（1..3600s） | `parseDataSourceTimeoutSeconds` |
/// | 进程声明 | `DataSourceProcess`（含 `preferredPort` 等） |
/// | 会话/凭据引用 | `DataSourceAuth` |
///
/// # 公开 API
/// | 成员 | 说明 |
/// | --- | --- |
/// | `FileSourceManifest.fromJson(json)` | 解析；校验 `type == "file-source"`、`script`/`process` 互斥二选一、`files` 非空 |
/// | `FileSourceManifest.fromJsonString(str)` | 字符串入口 |
/// | `.toJson()` | 序列化（可选段仅非默认值写出） |
/// | `.processExe` | 模型二进程入口名（模型一时为空串） |
/// | `FileSourceDecl.fromJson(json)` | 单个文件声明 |
/// | `.toJson()` | 序列化 |
library;

import 'dart:convert';

import 'data_source_manifest.dart';

/// 文件型插件清单（模型一 CLI / 模型二 常驻，与 data-source 同构）。
class FileSourceManifest {
  /// 全局唯一标识（缺省由目录名兜底）。
  final String id;

  /// 展示名。
  final String name;

  /// 模型一：CLI 脚本文件名（相对 `files/`）。与 [process] 互斥二选一。
  final String? script;

  /// 模型二：进程声明（字符串或对象形态）。与 [script] 互斥二选一。
  final DataSourceProcess? process;

  /// 脚本运行时：`native`（默认）/ `python`。
  final String runtime;

  /// 安卓支持开关（严格 bool 解析）。默认 true。
  final bool androidSupport;

  /// 可选认证声明（会话/凭据引用），语义与 data-source 完全一致。
  final DataSourceAuth? auth;

  /// 文件声明（非空）。
  final List<FileSourceDecl> files;

  const FileSourceManifest({
    this.id = '',
    this.name = '',
    this.script,
    this.process,
    this.runtime = 'native',
    this.androidSupport = true,
    this.auth,
    required this.files,
  });

  factory FileSourceManifest.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != 'file-source') {
      throw FormatException('type 必须为 "file-source"，实际为: $type');
    }

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

    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const FormatException('缺少必填字段: files (需要非空数组)');
    }

    return FileSourceManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      script: script,
      process: process,
      runtime: json['runtime'] as String? ?? 'native',
      androidSupport: parseDataSourceAndroidSupport(json['androidSupport']),
      auth: DataSourceAuth.fromJson(json['auth'] as Map<String, dynamic>?),
      files: rawFiles
          .map((e) => FileSourceDecl.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  factory FileSourceManifest.fromJsonString(String jsonString) =>
      FileSourceManifest.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>);

  /// 模型二进程入口名（`process?.exe`）；模型一时为空串。
  String get processExe => process?.exe ?? '';

  /// 安卓是否应加载（`isAndroid && !androidSupport` → 隐藏）。
  static bool isSupportedOn(FileSourceManifest m, {required bool isAndroid}) =>
      !(isAndroid && !m.androidSupport);

  Map<String, dynamic> toJson() => {
        'type': 'file-source',
        if (id.isNotEmpty) 'id': id,
        if (name.isNotEmpty) 'name': name,
        if (script != null) 'script': script,
        if (process != null) 'process': process!.toJson(),
        if (runtime != 'native') 'runtime': runtime,
        if (!androidSupport) 'androidSupport': false,
        'files': files.map((f) => f.toJson()).toList(),
        if (auth != null && !auth!.isEmpty) 'auth': auth!.toJson(),
      };

  @override
  String toString() => 'FileSourceManifest($id, ${files.length} files)';
}

/// 单个文件声明——一个可 `orch://<name>` 引用的文件型数据源。
class FileSourceDecl {
  /// 唯一标识（必填）：`orch://<name>` 的键。
  final String name;

  /// 传给脚本的 `--type`（缺省同 [name]）。
  final String? typeArg;

  /// 展示名（缺省回退 [name]）。
  final String? title;

  /// 分类标签（UI 分组）。
  final String category;

  /// 缓存有效期（影响后台自动刷新的重拉频率，见父协议 §8.4）。
  final Duration ttl;

  /// 本类型 CLI 拉取超时（缺省 null → 全局 60s）。大文件必需。
  final Duration? timeout;

  /// 持久化键（不设则不落盘缓存）。
  final String? persistentKey;

  /// 静态兜底（拉取失败且无旧缓存时返回）。
  final Map<String, dynamic>? fallbackJson;

  /// 允许的文件扩展名白名单（可选，小写含点，如 `[".mp4", ".pdf"]`）。
  ///
  /// 声明后平台会校验脚本返回的 `path` / `files[].path` 扩展名；
  /// 不在白名单内 → 拒绝并落 `lastError`。未声明则不校验扩展名。
  final List<String> accept;

  const FileSourceDecl({
    required this.name,
    this.typeArg,
    this.title,
    this.category = '文件',
    this.ttl = const Duration(hours: 24),
    this.timeout,
    this.persistentKey,
    this.fallbackJson,
    this.accept = const [],
  });

  factory FileSourceDecl.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('缺少必填字段: name');
    }
    return FileSourceDecl(
      name: name,
      typeArg: json['typeArg'] as String?,
      title: json['title'] as String?,
      category: json['category'] as String? ?? '文件',
      // 文件型默认 TTL 比 data-source 长（24h）：文件内容基本不变，
      // 且过短会让「发现」动作被 5 分钟 tick 反复触发（父协议 §8.4）。
      ttl: parseDataSourceTtl(json['ttl']) ?? const Duration(hours: 24),
      timeout: parseDataSourceTimeoutSeconds(json['timeoutSeconds']),
      persistentKey: json['persistentKey'] as String?,
      fallbackJson: json['fallbackJson'] is Map
          ? Map<String, dynamic>.from(json['fallbackJson'] as Map)
          : null,
      accept: _parseAccept(json['accept']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (typeArg != null && typeArg != name) 'typeArg': typeArg,
        if (title != null) 'title': title,
        'category': category,
        'ttl': _fmtDuration(ttl),
        if (timeout != null) 'timeoutSeconds': timeout!.inSeconds,
        if (persistentKey != null) 'persistentKey': persistentKey,
        if (fallbackJson != null) 'fallbackJson': fallbackJson,
        if (accept.isNotEmpty) 'accept': accept,
      };

  /// 判断 [path] 是否满足扩展名白名单（未声明白名单 → 恒 true）。
  bool acceptsPath(String path) {
    if (accept.isEmpty) return true;
    final lower = path.toLowerCase();
    return accept.any(lower.endsWith);
  }

  @override
  String toString() =>
      'FileSourceDecl($name, category: $category, ttl: ${_fmtDuration(ttl)})';
}

// ═══════════════════════════════════════════════════════════════════════════
// 内部
// ═══════════════════════════════════════════════════════════════════════════

/// 解析扩展名白名单：统一小写、补前导点、去空。
List<String> _parseAccept(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    if (e is! String) continue;
    var ext = e.trim().toLowerCase();
    if (ext.isEmpty) continue;
    if (!ext.startsWith('.')) ext = '.$ext';
    if (!out.contains(ext)) out.add(ext);
  }
  return out;
}

String _fmtDuration(Duration d) {
  final sec = d.inMicroseconds ~/ Duration.microsecondsPerSecond;
  if (sec >= 3600 && sec % 3600 == 0) return '${sec ~/ 3600}h';
  if (sec >= 60 && sec % 60 == 0) return '${sec ~/ 60}m';
  if (sec > 0) return '${sec}s';
  return '${d.inMilliseconds}ms';
}

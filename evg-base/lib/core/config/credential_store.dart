/// 平台级凭据存储——统一 SP / `.greenix/config.json` 镜像 / `env.json` 的读写抽象。
///
/// 主题 A（登录不挤占）的凭据读写统一入口：把分散在
/// SharedPreferences（主） / `.greenix/config.json`（镜像） / `.greenix/env.json`
/// （AI 环境变量）三处存储的凭据读写收敛为单一 [CredentialStore]。
///
/// # 设计要点
/// - **主存储**：SharedPreferences（全部字符串，`setSetting` 底层同一份 SP）。
/// - **镜像**：`.greenix/config.json`（扁平 JSON，写路径读改写保留其它 key）。
/// - **环境变量**：`.greenix/env.json`（可选，仅当 [envPath] 配置且写时 `mirrorEnv=true`）。
/// - **写路径互斥**：参考 data 层 Cache 的锁模式（单 isolate Future 链式串行），
///   非原子「读改写」不再并发竞争。
/// - **isSecure 标记**：跟踪安全 key（[secureKeys]/[isSecure]），供导出端默认跳过明文。
///
/// 兼容性：不改动 `save_credential`/`set_env_var`/`_ensureZjuCredentialsInGreenixConfig`
/// 的既有底层存储——本类仅提供统一入口 + 内部协调；既有调用方仍按原路径工作。
library credential_store;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 平台级凭据存储（纯 Dart + dart:io，无 Flutter 依赖，可独立单测）。
class CredentialStore {
  /// SharedPreferences 主存储。
  final SharedPreferences prefs;

  /// `.greenix/config.json` 镜像路径（可为 null：不镜像）。
  final String? configPath;

  /// `.greenix/env.json` 路径（可为 null：不写环境变量存储）。
  final String? envPath;

  /// 已标记 `isSecure` 的 key（实例级，供导出端跳过明文）。
  final Set<String> _secureKeys = <String>{};

  CredentialStore({required this.prefs, this.configPath, this.envPath});

  // ═══════════════════════════════════════════════════════════════════════════
  // 写路径互斥（参考 Cache 锁模式）
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _mutex = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _mutex.then((_) => action());
    _mutex = result.then((_) {}, onError: (_) {});
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 公开 API
  // ═══════════════════════════════════════════════════════════════════════════

  /// 读凭据：SP → config.json → env.json，返回第一个非空值；均无 → null。
  String? get(String key) {
    final v = prefs.getString(key);
    if (v != null && v.isNotEmpty) return v;
    final c = _readDict(configPath)?[key];
    if (c != null && c.isNotEmpty) return c;
    final e = _readDict(envPath)?[key];
    if (e != null && e.isNotEmpty) return e;
    return null;
  }

  /// 是否存在该 key（含空值，任意存储命中即 true）。
  bool has(String key) {
    if (prefs.containsKey(key)) return true;
    final c = _readDict(configPath);
    if (c != null && c.containsKey(key)) return true;
    final e = _readDict(envPath);
    if (e != null && e.containsKey(key)) return true;
    return false;
  }

  /// 写凭据：SP + config.json 镜像（+ 可选 env.json）。写路径经互斥队列串行。
  ///
  /// [isSecure] 标记该 key 为安全凭据（[secureKeys]/[isSecure]）；导出端据此默认跳过明文。
  /// [mirrorEnv] 为 true 时同步写 `.greenix/env.json`（对应 `set_env_var` 语义）。
  /// 空值等价于删除。
  Future<void> set(
    String key,
    String value, {
    bool isSecure = false,
    bool mirrorEnv = false,
  }) =>
      _serialized(() =>
          _doSet(key, value, isSecure: isSecure, mirrorEnv: mirrorEnv));

  /// 删除凭据：三处存储均移除。
  Future<void> delete(String key) => _serialized(() => _doDelete(key));

  /// 该 key 是否已标记 `isSecure`。
  bool isSecure(String key) => _secureKeys.contains(key);

  /// 已标记 `isSecure` 的 key 集合（只读），供导出端过滤明文。
  Set<String> get secureKeys => Set<String>.unmodifiable(_secureKeys);

  // ═══════════════════════════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _doSet(
    String key,
    String value, {
    required bool isSecure,
    required bool mirrorEnv,
  }) async {
    if (isSecure) {
      _secureKeys.add(key);
    } else {
      _secureKeys.remove(key);
    }
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
    _writeMirror(configPath, key, value.isEmpty ? null : value);
    if (mirrorEnv) _writeMirror(envPath, key, value.isEmpty ? null : value);
  }

  Future<void> _doDelete(String key) async {
    _secureKeys.remove(key);
    await prefs.remove(key);
    _writeMirror(configPath, key, null);
    _writeMirror(envPath, key, null);
  }

  /// 读取扁平 JSON 字典（`{"KEY": "value"}`）；文件缺失/损坏/非 Map → null，绝不抛。
  Map<String, String>? _readDict(String? path) {
    if (path == null) return null;
    try {
      final f = File(path);
      if (!f.existsSync()) return null;
      final m = jsonDecode(f.readAsStringSync());
      if (m is! Map) return null;
      return m.map((k, v) => MapEntry('$k', '${v ?? ''}'));
    } catch (_) {
      return null;
    }
  }

  /// 读改写镜像文件：保留其它 key；[value] 为 null 时移除该 key。
  void _writeMirror(String? path, String key, String? value) {
    if (path == null) return;
    try {
      final f = File(path);
      final dict = _readDict(path) ?? <String, String>{};
      if (value == null) {
        dict.remove(key);
      } else {
        dict[key] = value;
      }
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(dict));
    } catch (e) {
      stderr.writeln('[CredentialStore] ⚠ 镜像写入失败 $path: $e');
    }
  }
}

/// 直写凭据（不依赖 ConfigHttpServer / `.config_port`）——供 `save_credential` 类调用方
/// 在 ConfigHttpServer 未运行时降级使用：直写 SP + 镜像 `.greenix/config.json`。
///
/// 主题 A 第 4 点：去掉 `save_credential` 对 `.config_port` 端口文件的硬依赖——
/// 凭据写入不再要求 HTTP 服务在线。renderer 侧 `SaveCredentialTool` 可切换到本入口
/// （迁移属后续 renderer/T9 收尾，本任务仅提供 core-config 直写机制）。
Future<void> writeCredentialDirect({
  required SharedPreferences prefs,
  required String key,
  required String value,
  String? configPath,
  bool isSecure = true,
}) async {
  final store = CredentialStore(prefs: prefs, configPath: configPath);
  await store.set(key, value, isSecure: isSecure);
}

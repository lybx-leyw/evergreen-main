/// 爬虫环境变量存储（`ScraperEnvStore`）——AI/用户写入凭据的持久化载体。
///
/// 背景（用户反馈 bug）：探索模式此前**没有任何**写环境变量/写凭据的能力
/// （`run_terminal_command`/`save_credential` 被探索白名单禁用），AI 无法把
/// 用户账号密码写入环境变量，`verify_login_flow`/`execute_built_source` 的
/// `_get_config(key)` 也就读不到凭据。
///
/// 本存储：
/// - 持久化到 `.greenix/env.json`（扁平 `{"KEY": "value"}` 字典）；
/// - [envForSubprocess] 供所有 Python 子进程启动点合并进环境变量——
///   使 `_get_config()` Tier 3（`os.environ`）与直接 `os.environ.get(key)`
///   都能读到（Windows/桌面 + 安卓进程内解释器共用同一份 env 字典）；
/// - 同时把 key 镜像写入 `.greenix/config.json`（`_get_config()` Tier 1，
///   安卓 Chaquopy 原生桥按 `--greenix-config` 注入 GREENIX_CONFIG_PATH，
///   无需改动原生侧即可读到凭据）。
///
/// 纯 Dart + dart:io，可独立单测。
library scraper_env;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:evergreen_base/core/utils/greenix_path.dart';

/// 环境变量 key 合法格式：大写字母/数字/下划线，2-64 字符。
final RegExp envKeyPattern = RegExp(r'^[A-Z][A-Z0-9_]{1,63}$');

/// 校验环境变量 key；返回 null = 合法，否则为拒绝原因。
String? validateEnvKey(String key) {
  final t = key.trim();
  if (t.isEmpty) return 'key 不能为空';
  if (!envKeyPattern.hasMatch(t)) {
    return '环境变量名 "$t" 非法——仅允许大写字母/数字/下划线，'
        '字母开头，2-64 字符（如 SCRAPER_USERNAME）';
  }
  return null;
}

/// 爬虫环境变量存储。
class ScraperEnvStore {
  /// env.json 文件路径（默认 [greenixEnvPath]）。
  final String envFilePath;

  /// config.json 镜像路径（可为空：不镜像，仅子进程 env 注入）。
  final String? mirrorConfigPath;

  ScraperEnvStore({
    String? envFilePath,
    this.mirrorConfigPath,
  }) : envFilePath = envFilePath ?? greenixEnvPath;

  /// 读取当前存储的环境变量（文件缺失/损坏 → 空字典，绝不抛异常）。
  ///
  /// ⚠️ 必须返回**可变**空字典：调用方（[setVar]）会原地 `all[k] = v`，
  /// `const {}` 是不可变 map，首次写入（env.json 尚未创建）会抛
  /// "Cannot modify unmodifiable map"（用户反馈 bug）。
  Map<String, String> load() {
    try {
      final f = File(envFilePath);
      if (!f.existsSync()) return <String, String>{};
      final map = jsonDecode(f.readAsStringSync());
      if (map is! Map<String, dynamic>) return <String, String>{};
      return map.map((k, v) => MapEntry('$k', '${v ?? ''}'));
    } catch (e) {
      debugPrint('[ScraperEnvStore] ⚠ 读取环境变量存储失败: $e');
      return <String, String>{};
    }
  }

  /// 写入/更新一个环境变量（持久化到 env.json + 镜像 config.json）。
  ///
  /// 返回面向 AI 的确认文本（值打码）；失败返回 `[error: ...]`，绝不抛异常。
  String setVar(String key, String value) {
    final k = key.trim();
    final v = value.trim();
    final err = validateEnvKey(k);
    if (err != null) return '[error: $err]';

    try {
      final all = load();
      all[k] = v;
      File(envFilePath).parent.createSync(recursive: true);
      File(envFilePath).writeAsStringSync(jsonEncode(all));
    } catch (e) {
      return '[error: 写入环境变量存储失败: $e]';
    }

    // 镜像到 .greenix/config.json（Tier 1 兜底；保留文件中原有其它 key）
    if (mirrorConfigPath != null) {
      try {
        final cf = File(mirrorConfigPath!);
        final cfg = <String, String>{};
        if (cf.existsSync()) {
          try {
            final existing = jsonDecode(cf.readAsStringSync());
            if (existing is Map<String, dynamic>) {
              for (final e in existing.entries) {
                cfg['${e.key}'] = '${e.value ?? ''}';
              }
            }
          } catch (_) {}
        }
        cfg[k] = v;
        cf.parent.createSync(recursive: true);
        cf.writeAsStringSync(jsonEncode(cfg));
      } catch (e) {
        debugPrint('[ScraperEnvStore] ⚠ 镜像 config.json 失败（不阻断）: $e');
      }
    }

    debugPrint('[ScraperEnvStore] ✅ 环境变量已写入: $k (${v.length} chars)');
    return '✅ 环境变量 "$k" 已写入（${v.length} 字符）。'
        'scraper.py 中可用 _get_config("$k") 或 os.environ["$k"] 读取。';
  }

  /// 已设置的环境变量 key 列表（只读，值不回显）。
  List<String> keys() => load().keys.toList();

  /// 合并进子进程环境的完整字典（平台环境 + 本存储 + PROJECT_ROOT）。
  Map<String, String> envForSubprocess(String projectRoot) => {
        ...Map<String, String>.from(Platform.environment),
        ...load(),
        'PROJECT_ROOT': projectRoot,
      };

  /// 面向 AI 的已设置清单摘要（值打码）。
  String listSummary() {
    final keys = this.keys();
    if (keys.isEmpty) {
      return '(暂无已设置的环境变量。如需登录凭据，请调用 set_env_var 写入'
          ' SCRAPER_USERNAME / SCRAPER_PASSWORD / SCRAPER_COOKIE 等。)';
    }
    final buf = StringBuffer()
      ..writeln('已设置 ${keys.length} 个环境变量：');
    for (final k in keys) {
      buf.writeln('- $k（已设置）');
    }
    buf.writeln('值不回显；scraper.py 用 _get_config("KEY") 或 os.environ["KEY"] 读取。');
    return buf.toString();
  }
}

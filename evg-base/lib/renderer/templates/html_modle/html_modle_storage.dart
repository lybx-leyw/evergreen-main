/// 模块私有存储后端 —— `platform.storage.*` 与 localStorage polyfill 的落盘实现。
///
/// 契约对齐 core `ModuleStorageService`（另一子代理并行交付）：落盘路径同为
/// `{resolvePluginsRoot()}/{pluginId}/storage/storage.json`，方法签名一一对应
/// （[HtmlModleStorage.forPlugin] ↔ `ModuleStorageService.forPlugin`、[readSync] ↔
/// `readSync`、[write] ↔ `write`、[remove] ↔ `remove`、[clear] ↔ `clear`、
/// [readAll] ↔ `readAll`）。core 未交付时本类即为可用实现（同契约同路径、
/// 数据互通）；core 交付后如需切换，仅需把 `HtmlModleStorage.forPlugin` 内部
/// 实现替换为 `ModuleStorageService.forPlugin`（消费方签名不变）。
///
/// 语义：
/// - 落盘：`{resolvePluginsRoot()}/{pluginId}/storage/storage.json`（JSON 对象，
///   值为字符串）。
/// - [readSync]：**同步读**（storage.json 缺失/损坏 → null，不抛错）；
/// - [write] / [remove] / [clear]：**同步更新内存 + 异步 write-through 落盘**，
///   落盘失败静默降级为「会话内有效」（仅内存，重启丢失）；
/// - [readAll]：全量 `{key: value}` Map（缺失 → 空 Map）。
///
/// 纯 Dart（dart:async / dart:convert / dart:io + Flutter foundation
/// debugPrint + core greenix_path / path），不依赖 WebView 与 UI。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evergreen_base/core/utils/greenix_path.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

/// 插件级私有存储（key → String 值）。
///
/// 每个插件一个实例（按 [HtmlModleStorage.forPlugin] 的 pluginId 隔离）：
/// 内存态懒加载自磁盘，写路径经串行队列落盘（防并发覆写与读改写竞争）。
/// 所有公共方法均不抛异常（读缺失 → null、写失败 → 静默降级），保证
/// `platform.storage.*` / localStorage polyfill 在任何情况下都可用。
class HtmlModleStorage {
  HtmlModleStorage._(this._file);

  /// 为指定插件创建存储后端。
  ///
  /// [pluginId] 用于定位 `{pluginsRoot}/{pluginId}/storage/storage.json`；
  /// 路径解析失败（如 pluginsRoot 不可得）时返回**内存模式**实例（仅会话内
  /// 有效、不落盘），保证调用方永不因路径问题崩溃。
  factory HtmlModleStorage.forPlugin(String pluginId) {
    File? file;
    try {
      final root = resolvePluginsRoot();
      file = File(p.join(root, pluginId, 'storage', 'storage.json'));
    } catch (e) {
      debugPrint('[HtmlModleStorage] 路径解析失败，降级为内存模式: $e');
      file = null;
    }
    return HtmlModleStorage._(file);
  }

  /// 落盘文件；null = 内存模式（不落盘）。
  final File? _file;

  /// 内存态缓存（懒加载：首次读/写时从磁盘载入）。
  Map<String, dynamic>? _cache;

  /// 落盘串行队列（单 isolate Future 链式，避免并发覆写与读改写竞争）。
  Future<void> _writeQueue = Future.value();

  /// 同步读取 [key]；不存在 / storage.json 缺失或损坏 → null（不抛错）。
  String? readSync(String key) {
    final value = _load()[key];
    return value?.toString();
  }

  /// 全量读取（`{key: value}`）；storage.json 缺失 → 空 Map（不抛错）。
  Map<String, dynamic> readAll() => Map<String, dynamic>.of(_load());

  /// 写入 `[key] = [value]`（字符串语义）：同步更新内存 + 异步落盘。
  ///
  /// 返回的 Future 在**该次写入已持久化**（或静默降级完成）后 resolve；
  /// 落盘失败不抛错（降级为会话内有效）。
  Future<void> write(String key, String value) async {
    _load()[key] = value;
    await _persist();
  }

  /// 删除 [key]（不存在则跳过落盘）：同步更新内存 + 异步落盘。
  Future<void> remove(String key) async {
    if (_load().remove(key) != null) {
      await _persist();
    }
  }

  /// 清空全部键：同步更新内存 + 异步落盘。
  Future<void> clear() async {
    _load().clear();
    await _persist();
  }

  /// 内存态加载（磁盘 → 内存，仅一次）；缺失/损坏 → 空 Map（不抛错）。
  Map<String, dynamic> _load() {
    final cached = _cache;
    if (cached != null) return cached;
    var map = <String, dynamic>{};
    final file = _file;
    if (file != null) {
      try {
        if (file.existsSync()) {
          final decoded = jsonDecode(file.readAsStringSync());
          if (decoded is Map) {
            map = Map<String, dynamic>.from(decoded);
          }
        }
      } catch (e) {
        debugPrint('[HtmlModleStorage] 读取失败，按空存储处理: $e');
        map = <String, dynamic>{};
      }
    }
    _cache = map;
    return map;
  }

  /// 异步落盘当前内存快照（串行队列；内存模式 / 落盘失败 → 静默降级）。
  Future<void> _persist() {
    final snapshot = Map<String, dynamic>.of(_load());
    _writeQueue = _writeQueue.then((_) async {
      final file = _file;
      if (file == null) return; // 内存模式：不落盘
      try {
        file.parent.createSync(recursive: true);
        await file.writeAsString(jsonEncode(snapshot), flush: true);
      } catch (e) {
        debugPrint('[HtmlModleStorage] 落盘失败（会话内有效）: $e');
      }
    });
    return _writeQueue;
  }
}

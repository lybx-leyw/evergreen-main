/// HTML 插件模块存储器 —— 插件级 JSON 键值存储（localStorage polyfill 的落盘端）。
///
/// ⚠️ 副本 — 与 `lib/core/services/module_storage_service.dart` 同步（子包测试隔离用）。
///
/// 背景：HTML 插件经 WebView 加载，其 `localStorage` 按 origin（含随机端口）隔离，
/// 且 Windows WebView2 / Android webview_flutter 存储行为不一致，导致插件进度无法
/// 持久化。本服务在**平台侧**提供按插件隔离的 JSON 键值存储：
/// 落盘 `{resolvePluginsRoot()}/{pluginId}/storage/storage.json`，
/// 单文件内容为 `{key: value, ...}`（顶层 `Map<String, dynamic>`，值为 JSON 可序列化）。
///
/// 消费方（renderer 子代理）：
/// - localStorage polyfill：同步读 [readSync]（内存优先，首次访问同步读盘全量加载）
///   + 异步 write-through [write]/[remove]/[clear]；
/// - `platform.storage.*` 桥与数据源注册（data 域 `registerModuleStorageSource`）：
///   异步 [readAll]。
///
/// ## 安全
/// - [pluginId] 经 [moduleStoragePluginIdError] 校验（对齐 renderer `htmlPluginIdError`
///   语义：小写字母开头 kebab-case，拒绝路径穿越）；落盘路径再经 [PathSandbox]
///   confine（双保险）。
/// - 单文件上限 [kModuleStorageMaxBytes]（1MB），超限拒绝写入（抛
///   [ModuleStorageException]），避免单个插件撑爆磁盘/内存。
///
/// ## 并发模型
/// - 读路径同步（[readSync]/[readAll] 读内存 Map；首次访问同步读盘）。
/// - 写路径异步 write-through，经单 isolate Future 链串行（对齐 Cache 互斥队列）；
///   磁盘写为原子写（临时文件 + rename），崩溃不损坏已落盘数据。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../log.dart';
import '../utils/greenix_path.dart';
import '../utils/path_sandbox.dart';

/// 插件 ID 合法模式——与 renderer `html_export_service.dart` 的 `kHtmlPluginIdPattern`
/// **完全一致**（core 层不得反向依赖 renderer，此处等价实现并保持同一正则语义）：
/// 小写字母开头，后跟小写字母/数字，段间以单个 `-` 连接；拒绝纯数字/大写/空格/
/// 路径分隔符（防路径穿越）。
const String kModulePluginIdPattern = r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$';

/// 插件 ID 校验——对齐 renderer `htmlPluginIdError` 语义（core 不依赖 renderer，
/// 此为等价实现，注释说明对齐关系）。返回 `null` = 合法；否则返回**用户可展示**
/// 的错误信息（含 `plugin_id 非法` 前缀，与 renderer 测试文案保持一致）。
String? moduleStoragePluginIdError(String pluginId) {
  if (pluginId.isEmpty) {
    return 'plugin_id 非法: 不能为空';
  }
  if (pluginId.length > 64) {
    return 'plugin_id 非法: 过长（${pluginId.length} 字符，上限 64）';
  }
  if (!RegExp(kModulePluginIdPattern).hasMatch(pluginId)) {
    return 'plugin_id 非法: "$pluginId"——仅允许小写字母开头 + 小写字母/数字/'
        '连字符（如 my-dashboard），禁止纯数字/大写/空格/路径分隔符';
  }
  return null;
}

/// 单文件存储上限（字节）。storage.json 是插件 localStorage 的落盘镜像，正常很小；
/// 超限拒绝写入（抛 [ModuleStorageException]）。
const int kModuleStorageMaxBytes = 1024 * 1024; // 1MB

/// 存储子目录名（相对插件目录）。
const String kModuleStorageDirName = 'storage';

/// 存储文件名。
const String kModuleStorageFileName = 'storage.json';

/// 模块存储异常（路径越界 / 值不可 JSON 序列化 / 超限 / 磁盘 IO 失败）。
class ModuleStorageException implements Exception {
  final String message;
  const ModuleStorageException(this.message);
  @override
  String toString() => 'ModuleStorageException: $message';
}

/// 插件级 JSON 键值存储器。
///
/// ## 实例隔离
/// - 按 [pluginId] 隔离（不同插件目录互不可见）；同一插件建议复用同一实例。
/// - 跨实例一致性：写通过 write-through 落盘；[readAll] 在无待落盘写入时重新读盘，
///   使其它实例 / 数据源 fetcher 能看到最新磁盘状态。
///
/// ## 值语义
/// - 顶层 `Map<String, dynamic>`，值为 JSON 可序列化值（Map/List/String/num/bool/null
///   组合）；`write(key, null)` = 删除该 key（对齐 localStorage.removeItem 语义）。
class ModuleStorageService {
  final String _pluginId;
  final String _pluginsRoot;
  final String _storageFilePath;

  bool _loaded = false;
  Map<String, dynamic> _data = {};

  /// 待落盘写入数（已入队未完成）。>0 时 [readAll] 以内存为准，避免被旧盘覆盖
  /// 尚未落盘的写入（防内存↔磁盘回退丢失）。
  int _pendingWrites = 0;

  /// 写路径互斥队列（单 isolate Future 链式串行，对齐 Cache 写路径）。
  Future<void> _writeMutex = Future<void>.value();

  ModuleStorageService._(
      this._pluginId, this._pluginsRoot, this._storageFilePath);

  /// 构造指定插件的存储器实例。
  ///
  /// [pluginsRoot] 缺省用 [resolvePluginsRoot]（桌面=项目 plugins/、安卓=应用私有
  /// `.greenix/plugins`，跨平台单一解析）。[pluginId] 必须通过
  /// [moduleStoragePluginIdError] 校验（小写 kebab-case，拒绝路径穿越），
  /// 落盘路径再经 [PathSandbox] confine（双保险）；校验失败抛 [ArgumentError]，
  /// 越界抛 [ModuleStorageException]。
  factory ModuleStorageService.forPlugin(String pluginId,
      {String? pluginsRoot}) {
    final idErr = moduleStoragePluginIdError(pluginId);
    if (idErr != null) {
      throw ArgumentError(idErr);
    }
    final root = pluginsRoot ?? resolvePluginsRoot();
    final sandbox = PathSandbox(root);
    final rel = p.join(pluginId, kModuleStorageDirName, kModuleStorageFileName);
    final confined = sandbox.confine(rel);
    if (confined == null) {
      throw ModuleStorageException('存储路径越界（$rel）');
    }
    return ModuleStorageService._(pluginId, root, confined);
  }

  /// 插件 ID（构造时已通过校验）。
  String get pluginId => _pluginId;

  /// 插件根目录（构造时确定，绝对路径）。
  String get pluginsRoot => _pluginsRoot;

  /// storage.json 绝对路径（调试/测试用）。
  String get storagePath => _storageFilePath;

  /// 是否已加载内存缓存（首次读盘后为 true）。
  bool get isLoaded => _loaded;

  /// 同步读。内存命中即返回；首次访问同步读盘（全量加载；文件不存在 → 空 Map，
  /// 该 key 返回 null）。供 localStorage polyfill 热路径使用（零异步）。
  dynamic readSync(String key) {
    _ensureLoaded();
    return _data[key];
  }

  /// 全量读取（供数据源注册与 `platform.storage` 桥 list）。
  ///
  /// 无待落盘写入时重新读盘（同步），使外部实例 / 直写 storage.json 的改动可见；
  /// 有待落盘写入时返回当前内存（含已排队未落盘的最新写入，避免被旧盘覆盖）。
  /// 返回顶层 Map 的**浅拷贝**（值对象为共享引用，改动不影响内存态）。
  Future<Map<String, dynamic>> readAll() async {
    _maybeReloadFromDisk();
    return Map<String, dynamic>.of(_data);
  }

  /// 异步预热（若尚未加载则同步读盘——读路径保持同步语义，本方法仅为调用方提供
  /// Future 形态，便于 await 对齐加载完成）。
  Future<void> ensureLoaded() async {
    _ensureLoaded();
  }

  /// 写入（write-through）：先同步更新内存，再入队异步原子写盘。
  ///
  /// [value] 为 null = 删除该 key。值须 JSON 可序列化（Map/List/String/num/bool/null
  /// 组合），否则同步抛 [ModuleStorageException]（内存不变）。全文件编码后超过
  /// [kModuleStorageMaxBytes] 时异步抛 [ModuleStorageException]（内存已更新但未落盘，
  /// 调用方应视为写入失败并提示——超限属异常输入，不静默截断）。
  Future<void> write(String key, dynamic value) {
    _ensureLoaded(); // 首次写前先读盘合并，避免覆盖已有持久化数据
    if (value == null) {
      _data.remove(key);
    } else {
      _assertJsonSerializable(value);
      _data[key] = value;
    }
    return _enqueueFlush();
  }

  /// 删除 key（内存 + 落盘）。
  Future<void> remove(String key) {
    _ensureLoaded();
    _data.remove(key);
    return _enqueueFlush();
  }

  /// 清空（内存清空 + 删除 storage.json 文件）。
  Future<void> clear() {
    _ensureLoaded();
    _data = {};
    return _enqueueFlush(deleteFile: true);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════════════════════

  void _ensureLoaded() {
    if (_loaded) return;
    _loadFromDisk();
  }

  /// 有待落盘写入时以内存为准；否则从磁盘刷新（跨实例写入可见；文件缺失按空处理）。
  void _maybeReloadFromDisk() {
    if (_pendingWrites > 0) return;
    _loadFromDisk();
  }

  void _loadFromDisk() {
    _loaded = true;
    final file = File(_storageFilePath);
    if (!file.existsSync()) {
      _data = {};
      return;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      _data = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
    } catch (e) {
      // 损坏文件：按空处理（下次写覆盖），不抛——保证读路径可用性。
      Log().warn('ModuleStorageService: storage.json 解析失败，按空处理',
          data: {'plugin': _pluginId, 'error': e.toString()});
      _data = {};
    }
  }

  void _assertJsonSerializable(dynamic value) {
    try {
      jsonEncode(value);
    } on JsonUnsupportedObjectError catch (e) {
      throw ModuleStorageException('值不可 JSON 序列化: $e');
    }
  }

  /// 入队一次落盘（写/删/清空共用互斥队列，严格按调用顺序串行）。
  Future<void> _enqueueFlush({bool deleteFile = false}) {
    _pendingWrites++;
    final result =
        _writeMutex.then((_) => _flushToDisk(deleteFile: deleteFile));
    _writeMutex = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _flushToDisk({bool deleteFile = false}) async {
    try {
      if (deleteFile) {
        final file = File(_storageFilePath);
        if (await file.exists()) await file.delete();
        return;
      }
      final encoded = jsonEncode(_data);
      final bytes = utf8.encode(encoded);
      if (bytes.length > kModuleStorageMaxBytes) {
        throw ModuleStorageException(
            '存储超限：${bytes.length} 字节 > 上限 $kModuleStorageMaxBytes（1MB），拒绝写入');
      }
      await _atomicWrite(encoded);
    } finally {
      _pendingWrites--;
    }
  }

  /// 原子写盘：临时文件（同目录）+ rename（Dart [File.rename] 在目标存在时先删除
  /// 再替换）。崩溃时旧文件完整保留或新临时文件完整——不会出现半截 JSON。
  Future<void> _atomicWrite(String encoded) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    final tmp = File('$_storageFilePath.tmp');
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(_storageFilePath);
  }
}
